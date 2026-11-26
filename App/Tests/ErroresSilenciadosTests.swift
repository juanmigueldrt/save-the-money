import XCTest
import STMCore
@testable import SaveTheMoney

/// Un hogar listo en modo demo, con su backend en memoria a mano para hacerlo fallar.
@MainActor
private func hogarDeDemo() async throws -> (AppServices, Household) {
    let services = AppServices.demo()
    let session = SessionModel(services: services)
    try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
    try await session.createHousehold(name: "Casa de prueba")
    guard case .ready(_, let home) = session.state else { throw AppError.unknown("sin hogar") }
    return (services, home)
}

private let mensajeSinRed = AppError.network.errorDescription ?? ""

@MainActor
final class ErroresSilenciadosTests: XCTestCase {
    func testMovimientosDeCuentaSinRedLanzanErrorYNoSeVacian() async throws {
        let (services, home) = try await hogarDeDemo()
        let backend = try XCTUnwrap(services.finance as? InMemoryBackend)
        let finance = FinanceModel(household: home, service: services.finance)
        _ = await finance.createAccount(AccountDraft(name: "Corriente"))
        let account = try XCTUnwrap(finance.activeAccounts.first)

        // Con red, una cuenta sin movimientos da una lista vacía de verdad.
        let vacia = try await finance.movements(of: account)
        XCTAssertTrue(vacia.isEmpty)

        // Sin red, no es «vacía»: el error llega a quien llama.
        await backend.failCalls()
        do {
            _ = try await finance.movements(of: account)
            XCTFail("sin red debería lanzar el error")
        } catch {
            XCTAssertEqual((error as? AppError)?.errorDescription, mensajeSinRed)
        }
    }

    func testCerrarSesionSinRedDesconectaYAvisa() async throws {
        let (services, _) = try await hogarDeDemo()
        let backend = try XCTUnwrap(services.finance as? InMemoryBackend)
        let session = SessionModel(services: services)
        try await session.refresh()

        await backend.failCalls("signOut()")
        await session.signOut()

        XCTAssertEqual(session.state, .signedOut)
        XCTAssertEqual(session.signOutError, "No se ha podido cerrar la sesión en el servidor. " + mensajeSinRed)
    }

    func testCerrarSesionCorrectaNoAvisa() async throws {
        let (services, _) = try await hogarDeDemo()
        let session = SessionModel(services: services)
        try await session.refresh()

        await session.signOut()

        XCTAssertEqual(session.state, .signedOut)
        XCTAssertNil(session.signOutError)
    }
}
