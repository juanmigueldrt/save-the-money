import XCTest
import STMCore
@testable import SaveTheMoney

/// Guardar dos veces el mismo formulario no duplica, y un cambio sobre una versión antigua avisa y recarga (ORC-69).
@MainActor
final class EscriturasIdempotentesTests: XCTestCase {
    private struct Hogar {
        let backend: InMemoryBackend
        let finance: FinanceModel
        let account: Account
    }

    private func hogar() async throws -> Hogar {
        let services = AppServices.demo()
        let session = SessionModel(services: services)
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        try await session.createHousehold(name: "Casa de prueba")
        guard case .ready(_, let home) = session.state else { throw AppError.unknown("sin hogar") }
        let backend = try XCTUnwrap(services.finance as? InMemoryBackend)
        let finance = FinanceModel(household: home, service: services.finance)
        _ = await finance.createAccount(AccountDraft(name: "Corriente", openingBalance: Money(minor: 100_000)))
        return Hogar(backend: backend, finance: finance, account: try XCTUnwrap(finance.activeAccounts.first))
    }

    private func cafe(_ account: Account) throws -> MovementDraft {
        MovementDraft(accountId: account.id, bookedOn: try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 5)),
                      amount: Money(minor: -1_250), description: "Café de prueba")
    }

    /// «Guardar» falla por la red y la persona vuelve a pulsarlo, una vez o varias, con el mismo formulario:
    /// es decir, con el mismo borrador y el mismo id. También vale si el primero sí llegó y solo se perdió la respuesta.
    func testGuardarOtraVezTrasUnFalloDeRedNoDuplica() async throws {
        let hogar = try await hogar()
        let (backend, finance) = (hogar.backend, hogar.finance)
        let account = hogar.account
        let draft = try cafe(account)

        await backend.failCalls("addMovement(_:in:)")
        let primera = await finance.add(draft)
        XCTAssertFalse(primera)
        XCTAssertEqual(finance.error, AppError.network.errorDescription)

        await backend.clearFailures()
        let segunda = await finance.add(draft)
        let tercera = await finance.add(draft)
        XCTAssertTrue(segunda)
        XCTAssertTrue(tercera, "repetirlo ya guardado no es un error")
        XCTAssertEqual(finance.recent.map(\.id), [draft.id], "queda una sola fila")
        XCTAssertEqual(finance.balance(of: account), Money(minor: 98_750), "y el dinero se descuenta una vez")
    }

    func testCambiarUnaVersionAntiguaAvisaYRecarga() async throws {
        let hogar = try await hogar()
        let (backend, finance) = (hogar.backend, hogar.finance)
        _ = await finance.add(try cafe(hogar.account))
        let leido = try XCTUnwrap(finance.recent.first)

        // Otro dispositivo lo cambia mientras este tiene abierta la versión anterior.
        var desdeOtro = leido
        desdeOtro.amount = Money(minor: -2_000)
        _ = try await backend.updateMovement(desdeOtro)

        var aqui = leido
        aqui.amount = Money(minor: -3_000)
        let guardado = await finance.update(aqui)
        XCTAssertFalse(guardado)
        XCTAssertEqual(finance.error, AppError.movementChanged.errorDescription)
        XCTAssertEqual(finance.recent.map(\.amount), [Money(minor: -2_000)], "se ve lo que guardó el otro dispositivo, no se pisa")

        // Con el movimiento recargado, el cambio entra.
        var recargado = try XCTUnwrap(finance.recent.first)
        recargado.amount = Money(minor: -3_000)
        let repetido = await finance.update(recargado)
        XCTAssertTrue(repetido)
        XCTAssertEqual(finance.recent.map(\.amount), [Money(minor: -3_000)])
    }
}
