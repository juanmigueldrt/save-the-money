import XCTest
import STMCore
@testable import SaveTheMoney

/// ORC-106: el patrimonio se guarda en el modelo y no se rehace en cada pintado, pero sigue al día.
@MainActor
final class RendimientoPatrimonioTests: XCTestCase {
    func testPatrimonioGuardadoSeRehaceAlCargarOtrosMovimientos() async throws {
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
        _ = await finance.add(MovementDraft(accountId: account.id, bookedOn: try XCTUnwrap(CalendarDay(year: 2026, month: 9, day: 3)),
                                            amount: Money(minor: -4_000), description: "Compra"))

        let tracking = TrackingModel(household: home, finance: services.finance, budgets: services.budgets,
                                     scores: services.creditScores, today: { today })
        await tracking.loadHistory()
        // Tramo «Todo»: desde el mes del primer movimiento (septiembre) hasta noviembre.
        XCTAssertEqual(tracking.history(accounts: finance.accounts, range: .all).map(\.net.minor), [96_000, 96_000, 96_000])
        // Pedirlo otra vez (otro pintado) da lo mismo.
        XCTAssertEqual(tracking.history(accounts: finance.accounts, range: .all).map(\.net.minor), [96_000, 96_000, 96_000])

        // Recargar sin cambios no cambia nada.
        await tracking.loadHistory()
        XCTAssertEqual(tracking.history(accounts: finance.accounts, months: 2).map(\.net.minor), [96_000, 96_000])

        // Un movimiento nuevo, más antiguo, se ve tras recargar: también cambia el primer mes del tramo «Todo».
        _ = await finance.add(MovementDraft(accountId: account.id, bookedOn: try XCTUnwrap(CalendarDay(year: 2026, month: 8, day: 10)),
                                            amount: Money(minor: 10_000), description: "Nómina"))
        _ = await finance.add(MovementDraft(accountId: account.id, bookedOn: try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 2)),
                                            amount: Money(minor: -1_000), description: "Café"))
        await tracking.loadHistory()
        XCTAssertEqual(tracking.history(accounts: finance.accounts, range: .all).map(\.net.minor),
                       [110_000, 106_000, 106_000, 105_000])
        XCTAssertEqual(tracking.history(accounts: finance.accounts, months: 2).map(\.net.minor), [106_000, 105_000])

        // Con otras cuentas (p. ej. una que deja de contar) no se reutiliza lo calculado.
        var excluded = finance.accounts
        excluded[0].includeInNetWorth = false
        XCTAssertEqual(tracking.history(accounts: excluded, months: 2).map(\.net.minor), [0, 0])
    }
}
