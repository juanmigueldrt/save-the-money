import XCTest
import STMCore
@testable import SaveTheMoney

/// Un contador seguro entre hilos para ver cuántas veces se llama a la limpieza al cerrar sesión.
private actor LlamadasDeLimpieza {
    private(set) var total = 0

    func sumar() { total += 1 }
}

@MainActor
final class LimpiezaAlSalirTests: XCTestCase {
    func testSoloSeQuitanLosAvisosDeLaApp() {
        let ids = ["stm.recurring.alquiler", "stm.budget.2026-11.comida", "otra.app.aviso", "stm", "stm.card.x"]

        XCTAssertEqual(LocalAccountData.ownIdentifiers(ids), ["stm.recurring.alquiler", "stm.budget.2026-11.comida", "stm.card.x"])
    }

    func testSeBorranLasPreferenciasDeLaCuentaYSeConservanLasDelDispositivo() throws {
        let suite = "limpieza-al-salir-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for key in LocalAccountData.accountKeys { defaults.set(true, forKey: key) }
        defaults.set("dark", forKey: SessionModel.themeKey)
        defaults.set(true, forKey: DisplayPreferences.incognitoKey)

        LocalAccountData.clearPreferences(in: defaults)

        for key in LocalAccountData.accountKeys {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
        XCTAssertEqual(defaults.string(forKey: SessionModel.themeKey), "dark")
        XCTAssertEqual(defaults.object(forKey: DisplayPreferences.incognitoKey) as? Bool, true)
    }

    func testExportarBorraLoExportadoAnterior() throws {
        let antiguo = try ExportFiles.write(Data("antiguo".utf8), named: "antiguo-\(UUID().uuidString).csv")

        let nuevo = try ExportFiles.write(Data("nuevo".utf8), named: "nuevo-\(UUID().uuidString).csv")

        XCTAssertFalse(FileManager.default.fileExists(atPath: antiguo.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nuevo.path))
    }

    func testAlCerrarSesionSeLlamaALaLimpiezaAunqueFalleElServidor() async throws {
        let services = AppServices.demo()
        let llamadas = LlamadasDeLimpieza()
        let session = SessionModel(services: services, clearLocalData: { await llamadas.sumar() })
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        let backend = try XCTUnwrap(services.auth as? InMemoryBackend)
        await backend.failCalls("signOut()")

        await session.signOut()

        let total = await llamadas.total
        XCTAssertEqual(total, 1)
        XCTAssertEqual(session.state, .signedOut)
        XCTAssertNotNil(session.signOutError)
    }
}
