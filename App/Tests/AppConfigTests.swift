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
