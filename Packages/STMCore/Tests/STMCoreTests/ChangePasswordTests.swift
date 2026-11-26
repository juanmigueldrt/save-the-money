import XCTest
@testable import STMCore

/// Cambiar la contraseña con la sesión abierta (ORC-57), sobre el backend en memoria. Datos inventados.
final class ChangePasswordTests: XCTestCase {
    private func signedIn() async throws -> InMemoryBackend {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        return backend
    }

    private func error(_ operation: () async throws -> Void) async -> AppError? {
        do {
            try await operation()
            return nil
        } catch {
            return error as? AppError
        }
    }

    func testCambiaLaContrasenaYLaSesionSigueAbierta() async throws {
        let backend = try await signedIn()
        let ana = await backend.currentUserId()
        try await backend.changePassword(currentPassword: "contrasena-de-prueba", newPassword: "otra-contrasena-1")
        let sigue = await backend.currentUserId()
        XCTAssertEqual(sigue, ana)

        try await backend.signOut()
        let vieja = await error { _ = try await backend.signIn(username: Username("ana"), password: "contrasena-de-prueba") }
        XCTAssertEqual(vieja, .invalidCredentials)
        let id = try await backend.signIn(username: Username("ana"), password: "otra-contrasena-1")
        XCTAssertEqual(id, ana)
    }

    func testLaActualIncorrectaNoCambiaNadaNiCierraLaSesion() async throws {
        let backend = try await signedIn()
        let ana = await backend.currentUserId()
        let mal = await error { try await backend.changePassword(currentPassword: "no-es-esta", newPassword: "otra-contrasena-1") }
        XCTAssertEqual(mal, .wrongCurrentPassword)
        XCTAssertEqual(mal?.errorDescription, "La contraseña actual no es correcta.")
        let sigue = await backend.currentUserId()
        XCTAssertEqual(sigue, ana)

        try await backend.signOut()
        let id = try await backend.signIn(username: Username("ana"), password: "contrasena-de-prueba")
        XCTAssertEqual(id, ana)
    }

    func testLaNuevaSigueLaReglaDelRegistro() async throws {
        let backend = try await signedIn()
        let corta = await error { try await backend.changePassword(currentPassword: "contrasena-de-prueba", newPassword: "123456789") }
        XCTAssertEqual(corta, .weakPassword)
        let igual = await error { try await backend.changePassword(currentPassword: "contrasena-de-prueba", newPassword: "contrasena-de-prueba") }
        XCTAssertEqual(igual, .invalidInput(ChangePasswordForm.Issue.samePassword.message))
    }

    func testSinSesionNoSePuede() async throws {
        let backend = try await signedIn()
        try await backend.signOut()
        let sinSesion = await error { try await backend.changePassword(currentPassword: "contrasena-de-prueba", newPassword: "otra-contrasena-1") }
        XCTAssertEqual(sinSesion, .notSignedIn)
    }

    func testUnFalloDeRedNoCambiaLaContrasena() async throws {
        let backend = try await signedIn()
        await backend.failCalls("changePassword(currentPassword:newPassword:)")
        let red = await error { try await backend.changePassword(currentPassword: "contrasena-de-prueba", newPassword: "otra-contrasena-1") }
        XCTAssertEqual(red, .network)
        await backend.clearFailures()

        try await backend.signOut()
        _ = try await backend.signIn(username: Username("ana"), password: "contrasena-de-prueba")
    }
}
