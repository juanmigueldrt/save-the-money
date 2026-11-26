import XCTest
import STMCore
@testable import STMData
@testable import SaveTheMoney

/// Cambiar la contraseña desde Ajustes (ORC-57). Datos inventados.
@MainActor
final class CambiarContrasenaTests: XCTestCase {
    func testCambiaLaContrasenaYSigueDentro() async throws {
        let session = SessionModel(services: .demo())
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        let antes = session.state

        try await session.changePassword(ChangePasswordForm(
            currentPassword: "contrasena-de-prueba", newPassword: "otra-contrasena-1", newPasswordConfirmation: "otra-contrasena-1"))
        XCTAssertEqual(session.state, antes)

        await session.signOut()
        try await session.signIn(username: "ana", password: "otra-contrasena-1")
        XCTAssertNotEqual(session.state, .signedOut)
    }

    func testUnFormularioMalNoLlegaAlServidorYLaActualMalTieneSuMensaje() async throws {
        let session = SessionModel(services: .demo())
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))

        do {
            try await session.changePassword(ChangePasswordForm(
                currentPassword: "contrasena-de-prueba", newPassword: "otra-contrasena-1", newPasswordConfirmation: "otra-cosa"))
            XCTFail("las contraseñas no coinciden")
        } catch {
            XCTAssertEqual(error as? AppError, .invalidInput("Las contraseñas no coinciden."))
        }
        do {
            try await session.changePassword(ChangePasswordForm(
                currentPassword: "no-es-esta", newPassword: "otra-contrasena-1", newPasswordConfirmation: "otra-contrasena-1"))
            XCTFail("la actual no es")
        } catch {
            XCTAssertEqual((error as? AppError)?.errorDescription, "La contraseña actual no es correcta.")
        }
    }

    /// Mensajes reales de Supabase Auth: sin pistas de más, y el límite del servidor pide esperar.
    func testLosErroresDelServidorNoDicenMasQueAntes() {
        XCTAssertEqual(SupabaseBackend.appError(authMessage: "api(message: \"Invalid login credentials\", errorCode: invalid_credentials)"),
                       .invalidCredentials)
        XCTAssertEqual(SupabaseBackend.appError(authMessage: "api(message: \"Request rate limit reached\", errorCode: over_request_rate_limit)"),
                       .tooManyAttempts)
        XCTAssertEqual(
            SupabaseBackend.appError(authMessage: "api(message: \"New password should be different from the old password.\", errorCode: same_password)"),
            .invalidInput(ChangePasswordForm.Issue.samePassword.message))
        XCTAssertEqual(SupabaseBackend.appError(authMessage: "weakPassword(message: \"Password should be at least 10 characters.\")"),
                       .weakPassword)
    }
}
