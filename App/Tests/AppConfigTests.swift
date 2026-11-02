import XCTest
import STMCore
@testable import SaveTheMoney

final class AppConfigTests: XCTestCase {
    func testEveryPhoneTabIsASection() {
        XCTAssertEqual(AppSection.phoneTabs.count, 5)
        XCTAssertTrue(AppSection.phoneTabs.allSatisfy(AppSection.allCases.contains))
    }

    func testMissingOrPlaceholderKeyMeansDemo() {
        let url = URL(string: "http://127.0.0.1:54321")!
        XCTAssertTrue(AppConfig(supabaseURL: url, supabaseAnonKey: "").isMissingSupabaseKey)
        XCTAssertTrue(AppConfig(supabaseURL: url, supabaseAnonKey: "pega-aqui-la-clave-anon").isMissingSupabaseKey)
        XCTAssertFalse(AppConfig(supabaseURL: url, supabaseAnonKey: "clave-real").isMissingSupabaseKey)
    }
}

@MainActor
final class SessionModelTests: XCTestCase {
    func testSignUpCreateHouseholdAndSignOut() async throws {
        let session = SessionModel(services: .demo())
        await session.start()
        XCTAssertEqual(session.state, .signedOut)

        try await session.signUp(SignUpForm(username: "ana", displayName: "Ana",
                                            password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        guard case .needsHousehold(let profile) = session.state else {
            return XCTFail("tras crear la cuenta falta el hogar, no \(session.state)")
        }
        XCTAssertEqual(profile.name, "Ana")

        try await session.createHousehold(name: "Casa de prueba")
        guard case .ready(_, let home) = session.state else {
            return XCTFail("debería estar listo, no \(session.state)")
        }
        XCTAssertEqual(home.name, "Casa de prueba")

        await session.signOut()
        XCTAssertEqual(session.state, .signedOut)
    }

    func testInviteLinkIsRemembered() {
        let session = SessionModel(services: .demo())
        session.handle(url: URL(string: "savethemoney://unirse/4K9Q2X")!)
        XCTAssertEqual(session.pendingInvite?.value, "4K9Q2X")
        session.handle(url: URL(string: "https://example.com")!)
        XCTAssertEqual(session.pendingInvite?.value, "4K9Q2X")
    }
}

@MainActor
final class FinanceModelTests: XCTestCase {
    func testAccountMovementAndImport() async throws {
        let services = AppServices.demo()
        let session = SessionModel(services: services)
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        try await session.createHousehold(name: "Casa de prueba")
        guard case .ready(_, let home) = session.state else { return XCTFail("sin hogar") }

        let finance = FinanceModel(household: home, service: services.finance)
        await finance.load()
        XCTAssertEqual(finance.categories.count, 17)

        let created = await finance.createAccount(AccountDraft(name: "Corriente", openingBalance: Money(minor: 10_000)))
        XCTAssertTrue(created)
        let account = try XCTUnwrap(finance.activeAccounts.first)

        let day = try XCTUnwrap(CalendarDay(year: 2026, month: 10, day: 1))
        let added = await finance.add(MovementDraft(accountId: account.id, bookedOn: day, amount: Money(minor: -2_500), description: "Compra"))
        XCTAssertTrue(added)
        XCTAssertEqual(finance.totalBalance.minor, 7_500)

        let table = CSVTable.parse("Fecha;Concepto;Importe\n02/10/2026;Café;-1,50")
        let mapping = try XCTUnwrap(CSVMapping.detect(in: table))
        let drafts = CSVImporter.rows(in: table, mapping: mapping, accountId: account.id).compactMap(\.draft)
        let first = await finance.importMovements(drafts)
        XCTAssertEqual(first?.inserted, 1)
        let again = await finance.importMovements(drafts)
        XCTAssertEqual(again?.duplicates, 1)
        XCTAssertEqual(finance.recent.count, 2)
        XCTAssertEqual(finance.totalBalance.minor, 7_350)

        let failed = await finance.add(MovementDraft(accountId: account.id, bookedOn: day, amount: .zero, description: "Nada"))
        XCTAssertFalse(failed)
        XCTAssertEqual(finance.error, "El importe no puede ser cero.")
    }
}

@MainActor
final class BudgetModelTests: XCTestCase {
    func testProposalSaveAndReport() async throws {
        let services = AppServices.demo()
        let session = SessionModel(services: services)
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        try await session.createHousehold(name: "Casa de prueba")
        guard case .ready(_, let home) = session.state else { return XCTFail("sin hogar") }

        let finance = FinanceModel(household: home, service: services.finance)
        await finance.load()
        _ = await finance.createAccount(AccountDraft(name: "Corriente"))
        let account = try XCTUnwrap(finance.activeAccounts.first)
        let rent = try XCTUnwrap(finance.categories.first { $0.name == "Vivienda" })
        let today = try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 10))
        _ = await finance.add(MovementDraft(accountId: account.id, categoryId: rent.id, bookedOn: today,
                                            amount: Money(minor: -70_000), description: "Alquiler"))

        let october = BudgetModel(household: home, service: services.budgets, today: { CalendarDay(year: 2026, month: 10, day: 5)! })
        await october.load()
        let savedOctober = await october.save(Budget(householdId: home.id, month: october.month, expectedIncome: Money(minor: 200_000)))
        XCTAssertTrue(savedOctober)

        let budgets = BudgetModel(household: home, service: services.budgets, today: { today })
        await budgets.load()
        XCTAssertNil(budgets.budget)
        XCTAssertEqual(budgets.proposal?.month, MonthKey(year: 2026, month: 10), "propone el del mes anterior")
        XCTAssertEqual(budgets.draft.month, MonthKey(year: 2026, month: 11))
        XCTAssertEqual(budgets.draft.expectedIncome.minor, 200_000)

        let savedNovember = await budgets.save(budgets.draft)
        XCTAssertTrue(savedNovember)
        let report = budgets.report(categories: finance.categories)
        XCTAssertEqual(report.groups.first?.allocated.minor, 100_000)
        XCTAssertEqual(report.groups.first?.spent.minor, 70_000)
        XCTAssertFalse(CashFlow(report: report).isEmpty)
    }
}

/// Guarda los avisos que se programarían, en vez de lanzarlos.
private actor RecordingReminders: ReminderScheduling {
    private(set) var last: [PlannedReminder] = []
    func replace(with reminders: [PlannedReminder]) async { last = reminders }
}

@MainActor
final class PlanningModelTests: XCTestCase {
    func testRecurringRemindersAndGoalCompletion() async throws {
        let services = AppServices.demo()
        let session = SessionModel(services: services)
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        try await session.createHousehold(name: "Casa de prueba")
        guard case .ready(_, let home) = session.state else { return XCTFail("sin hogar") }

        let today = try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 2))
        let reminders = RecordingReminders()
        let planning = PlanningModel(household: home, recurring: services.recurring, goals: services.goals,
                                     reminders: reminders, today: { today })
        await planning.load()

        let music = RecurringSeries(householdId: home.id, name: "Música", amount: Money(minor: 999),
                                    startsOn: try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 5)), remindDaysBefore: 2)
        let saved = await planning.save(music)
        XCTAssertTrue(saved)
        XCTAssertEqual(planning.upcoming.count, 1)
        XCTAssertEqual(planning.monthlyTotal(of: .subscription).minor, 999)
        let planned = await reminders.last
        XCTAssertEqual(planned.first?.fireOn, CalendarDay(year: 2026, month: 11, day: 3))

        var archived = music
        archived.archivedAt = Date()
        _ = await planning.save(archived)
        let afterArchive = await reminders.last
        XCTAssertTrue(afterArchive.isEmpty, "una serie archivada no avisa")

        let trip = Goal(householdId: home.id, name: "Viaje", target: Money(minor: 50_000))
        let goalSaved = await planning.save(trip)
        XCTAssertTrue(goalSaved)
        let contributed = await planning.contribute(Money(minor: 50_000), to: trip, on: today, note: "  ")
        XCTAssertTrue(contributed)
        XCTAssertNil(planning.contributions.first?.note, "una nota en blanco no se guarda")
        XCTAssertTrue(planning.progress(of: trip).isReached)
        XCTAssertNotNil(planning.goals.first?.completedAt, "al llegar al objetivo se marca como conseguida")
    }
}

@MainActor
final class MoreOptionsModelTests: XCTestCase {
    private func readyHome() async throws -> (AppServices, SessionModel, Household) {
        let services = AppServices.demo()
        let session = SessionModel(services: services)
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        try await session.createHousehold(name: "Casa de prueba")
        guard case .ready(_, let home) = session.state else { throw AppError.unknown("sin hogar") }
        return (services, session, home)
    }

    func testThemeIsSavedInProfile() async throws {
        let (_, session, _) = try await readyHome()
        XCTAssertEqual(session.theme, .system)
        try await session.setTheme(.dark)
        XCTAssertEqual(session.theme, .dark)
        guard case .ready(let profile, _) = session.state else { return XCTFail("sin sesión") }
        XCTAssertEqual(profile.theme, .dark)
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
        XCTAssertNil(AppTheme.system.colorScheme)
    }

    func testCategoriesExportAndReset() async throws {
        let (services, _, home) = try await readyHome()
        let finance = FinanceModel(household: home, service: services.finance)
        await finance.load()
        let start = finance.categories.count

        let pets = BudgetCategory(householdId: home.id, name: "Mascotas", kind: .expense, budgetGroup: .needs, icon: "pawprint")
        let saved = await finance.save(pets)
        XCTAssertTrue(saved)
        XCTAssertEqual(finance.categories.count, start + 1)
        let repeated = await finance.save(BudgetCategory(householdId: home.id, name: "mascotas"))
        XCTAssertFalse(repeated)
        XCTAssertNotNil(finance.error)

        _ = await finance.createAccount(AccountDraft(name: "Cuenta común"))
        let account = try XCTUnwrap(finance.accounts.first)
        _ = await finance.add(MovementDraft(accountId: account.id, bookedOn: try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 1)),
                                            amount: Money(minor: -1_500), description: "Pienso"))
        let exported = await finance.exportCSV()
        let csv = try XCTUnwrap(exported)
        let text = try XCTUnwrap(String(data: csv.dropFirst(3), encoding: .utf8))
        XCTAssertTrue(text.contains("01/11/2026;Cuenta común;;Pienso;-15,00;EUR;"))

        let reset = await finance.resetHousehold()
        XCTAssertTrue(reset)
        XCTAssertTrue(finance.accounts.isEmpty)
        XCTAssertTrue(finance.recent.isEmpty)
        XCTAssertEqual(finance.categories.count, start)
    }
}

@MainActor
final class TrackingModelTests: XCTestCase {
    func testNetWorthScoresAndReports() async throws {
        let services = AppServices.demo()
        let session = SessionModel(services: services)
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        try await session.createHousehold(name: "Casa de prueba")
        guard case .ready(_, let home) = session.state else { return XCTFail("sin hogar") }
        let today = try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 20))

        let finance = FinanceModel(household: home, service: services.finance)
        await finance.load()
        _ = await finance.createAccount(AccountDraft(name: "Cuenta común", openingBalance: Money(minor: 100_000)))
        let account = try XCTUnwrap(finance.accounts.first)
        let food = try XCTUnwrap(finance.categories.first { $0.name == "Supermercado" })
        _ = await finance.add(MovementDraft(accountId: account.id, categoryId: food.id,
                                            bookedOn: try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 3)),
                                            amount: Money(minor: -4_000), description: "Compra"))

        let tracking = TrackingModel(household: home, finance: services.finance, budgets: services.budgets,
                                     scores: services.creditScores, today: { today })
        await tracking.loadHistory()
        let history = tracking.history(accounts: finance.accounts, months: 2)
        XCTAssertEqual(history.map(\.net.minor), [100_000, 96_000])

        let added = await tracking.add(CreditScore(score: 720, recordedOn: today))
        XCTAssertTrue(added)
        XCTAssertEqual(tracking.latestScore?.score, 720)
        let invalid = await tracking.add(CreditScore(score: 2_000))
        XCTAssertFalse(invalid)

        tracking.period = .thisMonth
        await tracking.loadReport()
        let report = tracking.report(categories: finance.categories)
        XCTAssertEqual(report.total, Money(minor: 4_000))
        XCTAssertEqual(report.byCategory.first?.title, "Supermercado")
    }
}
