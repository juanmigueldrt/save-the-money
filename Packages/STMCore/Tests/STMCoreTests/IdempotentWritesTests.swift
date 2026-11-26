import XCTest
@testable import STMCore

/// Apuntar dos veces lo mismo no duplica y no se cambia sobre una versión antigua (ORC-69). Datos inventados.
final class IdempotentWritesTests: XCTestCase {
    private struct Home {
        let backend: InMemoryBackend
        let id: UUID
        let checking: Account
        let savings: Account
    }

    private let day = CalendarDay(year: 2026, month: 11, day: 5)!

    private func home() async throws -> Home {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        let home = try await backend.createHousehold(name: "Casa de prueba")
        let checking = try await backend.createAccount(AccountDraft(name: "Corriente", openingBalance: Money(minor: 100_000)), in: home.id)
        let savings = try await backend.createAccount(AccountDraft(name: "Ahorro"), in: home.id)
        return Home(backend: backend, id: home.id, checking: checking, savings: savings)
    }

    private func coffee(_ home: Home, id: UUID = UUID(), cents: Int = -1_250) -> MovementDraft {
        MovementDraft(id: id, accountId: home.checking.id, bookedOn: day, amount: Money(minor: cents), description: "Café de prueba")
    }

    private func assertThrows(_ expected: AppError, _ message: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("debería fallar: " + message)
        } catch {
            XCTAssertEqual(error as? AppError, expected, message)
        }
    }

    func testRepetirLaMismaInsercionNoCreaOtraFila() async throws {
        let home = try await home()
        let draft = coffee(home)
        let first = try await home.backend.addMovement(draft, in: home.id)
        let second = try await home.backend.addMovement(draft, in: home.id)
        XCTAssertEqual(first.id, draft.id, "el movimiento lleva el identificador que eligió la app")
        XCTAssertEqual(second, first, "repetirlo devuelve el guardado")
        let stored = try await home.backend.movements(in: home.id, accountId: nil, limit: 50)
        XCTAssertEqual(stored.count, 1)
        let balances = try await home.backend.balances(in: home.id)
        XCTAssertEqual(balances[home.checking.id], Money(minor: 98_750), "el dinero se descuenta una sola vez")
    }

    func testReintentarTrasUnFalloDeRedGuardaUnaSolaVez() async throws {
        let home = try await home()
        let draft = coffee(home)
        await home.backend.failCalls("addMovement(_:in:)")
        await assertThrows(.network, "sin red no se guarda") { _ = try await home.backend.addMovement(draft, in: home.id) }
        await home.backend.clearFailures()
        _ = try await home.backend.addMovement(draft, in: home.id)
        _ = try await home.backend.addMovement(draft, in: home.id)
        let stored = try await home.backend.movements(in: home.id, accountId: nil, limit: 50)
        XCTAssertEqual(stored.map(\.id), [draft.id])
    }

    func testRepetirConOtrosDatosFalla() async throws {
        let home = try await home()
        let id = UUID()
        _ = try await home.backend.addMovement(coffee(home, id: id), in: home.id)
        let other = AppError.invalidInput(TransferDraft.storedWithOtherData)
        await assertThrows(other, "otro importe") { _ = try await home.backend.addMovement(coffee(home, id: id, cents: -9_999), in: home.id) }
        var moved = coffee(home, id: id)
        moved.accountId = home.savings.id
        await assertThrows(other, "otra cuenta") { _ = try await home.backend.addMovement(moved, in: home.id) }
        var later = coffee(home, id: id)
        later.bookedOn = CalendarDay(year: 2026, month: 11, day: 6)!
        await assertThrows(other, "otro día") { _ = try await home.backend.addMovement(later, in: home.id) }
        let stored = try await home.backend.movements(in: home.id, accountId: nil, limit: 50)
        XCTAssertEqual(stored.map(\.amount), [Money(minor: -1_250)], "queda el primero, sin cambios")
    }

    func testCambiarSobreUnaVersionAntiguaSeRechaza() async throws {
        let home = try await home()
        let read = try await home.backend.addMovement(coffee(home), in: home.id)
        XCTAssertNotNil(read.updatedAt, "cada movimiento guardado tiene versión")

        // Un dispositivo lo cambia; el otro todavía tiene la versión que leyó antes.
        var phone = read
        phone.amount = Money(minor: -2_000)
        let saved = try await home.backend.updateMovement(phone)
        XCTAssertNotEqual(saved.updatedAt, read.updatedAt, "cambiarlo cambia la versión")

        var tablet = read
        tablet.amount = Money(minor: -3_000)
        await assertThrows(.movementChanged, "la versión antigua no pisa el cambio") { _ = try await home.backend.updateMovement(tablet) }
        var unread = saved
        unread.updatedAt = nil
        await assertThrows(.movementChanged, "sin versión tampoco") { _ = try await home.backend.updateMovement(unread) }
        let stored = try await home.backend.movements(in: home.id, accountId: nil, limit: 50)
        XCTAssertEqual(stored.map(\.amount), [Money(minor: -2_000)])

        // Con la versión recargada sí se puede.
        var reloaded = try XCTUnwrap(stored.first)
        reloaded.amount = Money(minor: -3_000)
        let again = try await home.backend.updateMovement(reloaded)
        XCTAssertEqual(again.amount, Money(minor: -3_000))
    }

    func testCambiarUnMovimientoBorradoSeRechaza() async throws {
        let home = try await home()
        let read = try await home.backend.addMovement(coffee(home), in: home.id)
        try await home.backend.deleteMovement(read.id)
        await assertThrows(.movementChanged, "ya no existe") { _ = try await home.backend.updateMovement(read) }
    }

    func testLaVersionSeGuardaComoTextoSinPerderMicrosegundos() throws {
        // Lo que devuelve el servidor: seis decimales y desplazamiento horario.
        let json = """
        {"id":"20000000-0000-0000-0000-000000000001","household_id":"20000000-0000-0000-0000-0000000000aa",
         "account_id":"20000000-0000-0000-0000-0000000000bb","booked_on":"2026-11-05","amount_minor":-1250,
         "description":"Café de prueba","updated_at":"2026-11-01T10:00:00.123456+00:00"}
        """
        let movement = try JSONDecoder().decode(Movement.self, from: Data(json.utf8))
        XCTAssertEqual(movement.updatedAt, "2026-11-01T10:00:00.123456+00:00")
        let again = try JSONDecoder().decode(Movement.self, from: JSONEncoder().encode(movement))
        XCTAssertEqual(again.updatedAt, "2026-11-01T10:00:00.123456+00:00")
    }

    func testElAvisoDiceQueCambioEnOtroDispositivo() {
        let text = AppError.movementChanged.errorDescription ?? ""
        XCTAssertTrue(text.contains("ha cambiado en otro dispositivo"))
        XCTAssertTrue(text.contains("se ha vuelto a cargar"))
        XCTAssertNotEqual(text, AppError.unknown("").errorDescription)
    }
}
