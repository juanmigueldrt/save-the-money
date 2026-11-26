import XCTest
import SwiftUI
@testable import SaveTheMoney

/// Regla del bloqueo y estado del modelo, sin el diálogo del sistema.
@MainActor
final class AppLockTests: XCTestCase {
    private let salida = Date(timeIntervalSince1970: 1_800_000_000)

    func testDesactivadoNuncaBloquea() {
        XCTAssertFalse(AppLock.shouldLock(enabled: false, backgroundedAt: .distantPast, now: salida))
    }

    func testSinPasarPorSegundoPlanoNoBloquea() {
        XCTAssertFalse(AppLock.shouldLock(enabled: true, backgroundedAt: nil, now: salida))
    }

    func testDentroDelMargenNoBloquea() {
        XCTAssertFalse(AppLock.shouldLock(enabled: true, backgroundedAt: salida, now: salida.addingTimeInterval(59)))
    }

    func testAlCumplirseElMargenBloquea() {
        XCTAssertEqual(AppLock.gracePeriod, 60)
        XCTAssertTrue(AppLock.shouldLock(enabled: true, backgroundedAt: salida, now: salida.addingTimeInterval(60)))
    }

    func testRelojHaciaAtrasBloquea() {
        XCTAssertTrue(AppLock.shouldLock(enabled: true, backgroundedAt: salida, now: salida.addingTimeInterval(-1)))
    }

    func testActivadoArrancaBloqueadaAntesDeCualquierCambioDeEscena() {
        XCTAssertTrue(AppLockModel(isEnabled: { true }, authenticate: { true }).isLocked)
    }

    func testDesactivadoArrancaAbierta() {
        XCTAssertFalse(AppLockModel(isEnabled: { false }, authenticate: { true }).isLocked)
    }

    func testEnlaceConLaAppBloqueadaEsperaAlDesbloqueo() async {
        let modelo = AppLockModel(isEnabled: { true }, authenticate: { true })
        var abierto = 0
        modelo.whenUnlocked(now: salida) { abierto += 1 }
        XCTAssertEqual(abierto, 0)
        await modelo.unlock()
        XCTAssertEqual(abierto, 1)
        modelo.whenUnlocked(now: salida) { abierto += 1 }
        XCTAssertEqual(abierto, 2, "Desbloqueada, el enlace se abre ya")
    }

    func testEnlaceAlVolverTrasElMargenEsperaAunqueNoSeHayaBloqueadoTodavia() async {
        let modelo = AppLockModel(isEnabled: { true }, authenticate: { true })
        await modelo.sceneChanged(to: .active, now: salida)
        await modelo.sceneChanged(to: .background, now: salida)
        var abierto = false
        // El enlace llega antes que el paso a activa.
        modelo.whenUnlocked(now: salida.addingTimeInterval(120)) { abierto = true }
        XCTAssertFalse(abierto)
        await modelo.sceneChanged(to: .active, now: salida.addingTimeInterval(120))
        XCTAssertTrue(abierto)
    }

    func testEnlaceConElBloqueoDesactivadoSeAbreYa() {
        let modelo = AppLockModel(isEnabled: { false }, authenticate: { false })
        var abierto = false
        modelo.whenUnlocked(now: salida) { abierto = true }
        XCTAssertTrue(abierto)
    }

    func testAlArrancarBloqueaYDesbloqueaSiSeAutentica() async {
        var peticiones = 0
        let modelo = AppLockModel(isEnabled: { true }, authenticate: { peticiones += 1; return true })
        await modelo.sceneChanged(to: .active, now: salida)
        XCTAssertEqual(peticiones, 1)
        XCTAssertFalse(modelo.isLocked)
    }

    func testSiSeCancelaSigueBloqueadaYNoVuelveAPedirSolo() async {
        var peticiones = 0
        let modelo = AppLockModel(isEnabled: { true }, authenticate: { peticiones += 1; return false })
        await modelo.sceneChanged(to: .active, now: salida)
        XCTAssertTrue(modelo.isLocked)
        // El diálogo pasa la escena a inactiva y luego a activa: no debe volver a pedirse en bucle.
        await modelo.sceneChanged(to: .inactive, now: salida)
        await modelo.sceneChanged(to: .active, now: salida)
        XCTAssertEqual(peticiones, 1)
        XCTAssertTrue(modelo.isLocked)
    }

    func testVolverTrasElMargenVuelveAPedir() async {
        var peticiones = 0
        let modelo = AppLockModel(isEnabled: { true }, authenticate: { peticiones += 1; return true })
        await modelo.sceneChanged(to: .active, now: salida)
        await modelo.sceneChanged(to: .background, now: salida)
        await modelo.sceneChanged(to: .active, now: salida.addingTimeInterval(30))
        XCTAssertEqual(peticiones, 1, "Dentro del minuto no se vuelve a pedir")
        await modelo.sceneChanged(to: .background, now: salida.addingTimeInterval(30))
        await modelo.sceneChanged(to: .active, now: salida.addingTimeInterval(91))
        XCTAssertEqual(peticiones, 2)
        XCTAssertFalse(modelo.isLocked)
    }

    func testSinBiometriaNiCodigoNuncaDejaFuera() async {
        var activado = true
        let modelo = AppLockModel(isEnabled: { activado }, authenticate: { false })
        await modelo.sceneChanged(to: .active, now: salida)
        XCTAssertTrue(modelo.isLocked)
        activado = false // Se quitó el código del dispositivo.
        await modelo.unlock()
        XCTAssertFalse(modelo.isLocked)
    }
}
