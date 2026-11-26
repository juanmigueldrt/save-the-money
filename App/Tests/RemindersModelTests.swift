import XCTest
import STMCore
@testable import SaveTheMoney

/// Guarda los avisos que se programarían y cada vez que se sustituyen, por prefijo.
private actor RecordedReminders: ReminderScheduling {
    private(set) var byPrefix: [String: [PlannedReminder]] = [:]
    private(set) var calls: [String] = []

    func replace(with reminders: [PlannedReminder], prefix: String) async {
        byPrefix[prefix] = reminders
        calls.append(prefix)
    }

    func count(_ prefix: String) -> Int { calls.filter { $0 == prefix }.count }
}

/// Un hogar listo en modo demo, con su backend en memoria a mano para hacerlo fallar.
@MainActor
private func demoHome() async throws -> (InMemoryBackend, Household) {
    let services = AppServices.demo()
    let session = SessionModel(services: services)
    try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
    try await session.createHousehold(name: "Casa de prueba")
    guard case .ready(_, let home) = session.state else { throw AppError.unknown("sin hogar") }
    return (try XCTUnwrap(services.finance as? InMemoryBackend), home)
}

private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }

/// Si la carga falla, los avisos que ya había programados no se tocan (ORC-86).
@MainActor
final class RemindersModelTests: XCTestCase {
    func testPagosFijosCargaFallidaNoBorraLosAvisos() async throws {
        let (backend, home) = try await demoHome()
        let today = day(2026, 11, 10)
        _ = try await backend.createRecurring(RecurringSeries(householdId: home.id, name: "Gimnasio", amount: Money(minor: 3_000),
                                                              startsOn: day(2026, 11, 20), remindDaysBefore: 1))
        let reminders = RecordedReminders()
        await PlanningModel(household: home, recurring: backend, goals: backend, reminders: reminders, today: { today }).load()
        let scheduled = await reminders.byPrefix[ReminderPlanner.prefix] ?? []
        XCTAssertEqual(scheduled.map(\.fireOn), [day(2026, 11, 19), day(2026, 12, 19)])

        // La app se vuelve a abrir sin conexión.
        await backend.failCalls()
        let reopened = PlanningModel(household: home, recurring: backend, goals: backend, reminders: reminders, today: { today })
        await reopened.load()
        XCTAssertEqual(reopened.error, AppError.network.errorDescription)
        let calls = await reminders.count(ReminderPlanner.prefix)
        XCTAssertEqual(calls, 1, "una carga fallida no reprograma")
        let kept = await reminders.byPrefix[ReminderPlanner.prefix]
        XCTAssertEqual(kept, scheduled)
    }

    func testAportacionesCargaFallidaNoBorraLosAvisos() async throws {
        let (backend, home) = try await demoHome()
        let today = day(2026, 11, 10)
        let fund = try await backend.createHolding(Holding(householdId: home.id, name: "Fondo de prueba", price: 10))
        _ = try await backend.createPlan(InvestmentPlan(householdId: home.id, holdingId: fund.id, amount: Money(minor: 5_000),
                                                        startsOn: day(2026, 11, 15), remindDaysBefore: 1))
        let reminders = RecordedReminders()
        await InvestmentModel(household: home, service: backend, households: backend, reminders: reminders, today: { today }).load()
        let scheduled = await reminders.byPrefix[ReminderPlanner.investmentPrefix] ?? []
        XCTAssertEqual(scheduled.map(\.fireOn), [day(2026, 11, 14), day(2026, 12, 14)])

        await backend.failCalls()
        let reopened = InvestmentModel(household: home, service: backend, households: backend, reminders: reminders, today: { today })
        await reopened.load()
        XCTAssertEqual(reopened.error, AppError.network.errorDescription)
        let calls = await reminders.count(ReminderPlanner.investmentPrefix)
        XCTAssertEqual(calls, 1, "una carga fallida no reprograma")
        let kept = await reminders.byPrefix[ReminderPlanner.investmentPrefix]
        XCTAssertEqual(kept, scheduled)
    }

    func testTarjetasCargaFallidaNoBorraLosAvisos() async throws {
        let (backend, home) = try await demoHome()
        let today = day(2026, 11, 4)
        let card = try await backend.createAccount(AccountDraft(name: "Tarjeta", kind: .creditCard), in: home.id)
        _ = try await backend.addMovement(MovementDraft(accountId: card.id, bookedOn: day(2026, 10, 10), amount: Money(minor: -30_000),
                                                        description: "Compra de prueba"), in: home.id)
        _ = try await backend.saveCreditCard(CreditCardTerms(accountId: card.id, householdId: home.id, creditLimit: Money(minor: 300_000)))
        let accounts = try await backend.accounts(in: home.id)
        let balances = try await backend.balances(in: home.id)
        let reminders = RecordedReminders()
        let first = CreditCardModel(household: home, service: backend, finance: backend, reminders: reminders, today: { today })
        await first.load(accounts: accounts, balances: balances, categories: [])
        let scheduled = await reminders.byPrefix[ReminderPlanner.cardPrefix] ?? []
        XCTAssertEqual(scheduled.count, 1)

        await backend.failCalls()
        let reopened = CreditCardModel(household: home, service: backend, finance: backend, reminders: reminders, today: { today })
        await reopened.load(accounts: accounts, balances: balances, categories: [])
        XCTAssertEqual(reopened.error, AppError.network.errorDescription)
        let calls = await reminders.count(ReminderPlanner.cardPrefix)
        XCTAssertEqual(calls, 1, "una carga fallida no reprograma")
        let kept = await reminders.byPrefix[ReminderPlanner.cardPrefix]
        XCTAssertEqual(kept, scheduled)

        // El interruptor de Más opciones vuelve a programar los de tarjetas con lo último cargado.
        await first.reschedule()
        let afterSwitch = await reminders.count(ReminderPlanner.cardPrefix)
        XCTAssertEqual(afterSwitch, 2)
    }
}
