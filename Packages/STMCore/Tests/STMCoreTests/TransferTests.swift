import XCTest
@testable import STMCore

/// El pago de una tarjeta con el servicio en memoria: las dos patas o ninguna, y sin duplicar. Datos inventados.
final class TransferTests: XCTestCase {
    private struct Home {
        let backend: InMemoryBackend
        let id: UUID
        let checking: Account
        let card: Account
    }

    private let day = CalendarDay(year: 2026, month: 11, day: 4)!

    private func home() async throws -> Home {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        let home = try await backend.createHousehold(name: "Casa de prueba")
        let checking = try await backend.createAccount(AccountDraft(name: "Corriente", openingBalance: Money(minor: 100_000)), in: home.id)
        let card = try await backend.createAccount(AccountDraft(name: "Tarjeta", kind: .creditCard), in: home.id)
        _ = try await backend.addMovement(MovementDraft(accountId: card.id, bookedOn: day, amount: Money(minor: -30_000),
                                                        description: "Compra de prueba"), in: home.id)
        return Home(backend: backend, id: home.id, checking: checking, card: card)
    }

    private func payment(_ home: Home, id: UUID = UUID(), cents: Int = 30_000) -> TransferDraft {
        TransferDraft(id: id, fromAccountId: home.checking.id, toAccountId: home.card.id, bookedOn: day,
                      amount: Money(minor: cents), fromDescription: "Pago de Tarjeta", toDescription: "Pago de la tarjeta")
    }

    private func payments(_ home: Home) async throws -> [Movement] {
        try await home.backend.movements(in: home.id, accountId: nil, limit: 50).filter { $0.description.hasPrefix("Pago de") }
    }

    func testStoresBothLegs() async throws {
        let home = try await home()
        let legs = try await home.backend.addTransfer(payment(home), in: home.id)
        XCTAssertEqual(legs.map(\.accountId), [home.checking.id, home.card.id], "primero la salida")
        XCTAssertEqual(legs.map(\.amount), [Money(minor: -30_000), Money(minor: 30_000)])
        XCTAssertEqual(legs.map(\.description), ["Pago de Tarjeta", "Pago de la tarjeta"])
        let balances = try await home.backend.balances(in: home.id)
        XCTAssertEqual(balances[home.checking.id], Money(minor: 70_000))
        XCTAssertEqual(balances[home.card.id], .zero)
    }

    func testNothingIsStoredWhenTheSecondLegFails() async throws {
        let home = try await home()
        let draft = payment(home)
        await home.backend.failCalls("addMovement(_:in:)", after: 1)
        do {
            _ = try await home.backend.addTransfer(draft, in: home.id)
            XCTFail("tenía que fallar")
        } catch {
            XCTAssertEqual(error as? AppError, .network)
        }
        await home.backend.clearFailures()
        var balances = try await home.backend.balances(in: home.id)
        XCTAssertEqual(balances[home.checking.id], Money(minor: 100_000), "un pago a medias no saca dinero de la cuenta")
        XCTAssertEqual(balances[home.card.id], Money(minor: -30_000))
        var stored = try await payments(home)
        XCTAssertTrue(stored.isEmpty, "no queda ninguna de las dos patas")

        // Reintentar la misma petición la guarda entera, una sola vez.
        _ = try await home.backend.addTransfer(draft, in: home.id)
        balances = try await home.backend.balances(in: home.id)
        XCTAssertEqual(balances[home.checking.id], Money(minor: 70_000))
        XCTAssertEqual(balances[home.card.id], .zero)
        stored = try await payments(home)
        XCTAssertEqual(stored.count, 2)
    }

    func testRepeatingTheSameRequestDoesNotDuplicate() async throws {
        let home = try await home()
        let draft = payment(home)
        let first = try await home.backend.addTransfer(draft, in: home.id)
        let again = try await home.backend.addTransfer(draft, in: home.id)
        XCTAssertEqual(again, first, "devuelve las dos patas que ya estaban")
        // El concepto no cuenta: con las mismas cuentas, importe y día manda lo guardado.
        var renamed = draft
        renamed.toDescription = "Otro concepto"
        let sameData = try await home.backend.addTransfer(renamed, in: home.id)
        XCTAssertEqual(sameData, first)
        let stored = try await payments(home)
        XCTAssertEqual(stored.count, 2)
        let balances = try await home.backend.balances(in: home.id)
        XCTAssertEqual(balances[home.checking.id], Money(minor: 70_000))

        // Otro id es otro pago.
        _ = try await home.backend.addTransfer(payment(home, cents: 5_000), in: home.id)
        let afterSecond = try await home.backend.balances(in: home.id)
        XCTAssertEqual(afterSecond[home.checking.id], Money(minor: 65_000))
    }

    func testRepeatingWithOtherDataFailsInsteadOfLookingSaved() async throws {
        let home = try await home()
        let draft = payment(home)
        _ = try await home.backend.addTransfer(draft, in: home.id)
        var otherDay = draft
        otherDay.bookedOn = CalendarDay(year: 2026, month: 11, day: 5)!
        var swapped = draft
        swapped.fromAccountId = draft.toAccountId
        swapped.toAccountId = draft.fromAccountId
        for changed in [payment(home, id: draft.id, cents: 99_900), otherDay, swapped] {
            do {
                _ = try await home.backend.addTransfer(changed, in: home.id)
                XCTFail("con otros datos no se da por guardada")
            } catch {
                XCTAssertEqual(error as? AppError, .invalidInput(TransferDraft.storedWithOtherData))
            }
        }
        let stored = try await payments(home)
        XCTAssertEqual(stored.count, 2, "y no se apunta nada")
        let balances = try await home.backend.balances(in: home.id)
        XCTAssertEqual(balances[home.checking.id], Money(minor: 70_000), "el pago guardado sigue como estaba")
        XCTAssertEqual(balances[home.card.id], .zero)
    }

    func testRejectsWhatTheServerRejects() async throws {
        let home = try await home()
        func assertRejected(_ draft: TransferDraft, in householdId: UUID, _ message: String) async {
            do {
                _ = try await home.backend.addTransfer(draft, in: householdId)
                XCTFail(message)
            } catch {}
        }
        await assertRejected(payment(home, cents: 0), in: home.id, "el importe no puede ser cero")
        await assertRejected(payment(home, cents: -5_000), in: home.id, "ni negativo")
        var same = payment(home)
        same.toAccountId = same.fromAccountId
        await assertRejected(same, in: home.id, "las dos cuentas tienen que ser distintas")
        var blank = payment(home)
        blank.toDescription = "   "
        await assertRejected(blank, in: home.id, "la segunda pata necesita concepto")

        // Carla, de otro hogar: ni entra en el de Ana ni usa sus cuentas desde el suyo.
        try await home.backend.signOut()
        _ = try await home.backend.signUp(username: Username("carla"), password: "contrasena-de-prueba", displayName: nil)
        let other = try await home.backend.createHousehold(name: "Piso de Carla")
        await assertRejected(payment(home), in: home.id, "quien no es del hogar no transfiere")
        await assertRejected(payment(home), in: other.id, "no se usan cuentas de otro hogar")
        let own = try await home.backend.createAccount(AccountDraft(name: "Cuenta de Carla"), in: other.id)
        var mixed = payment(home)
        mixed.fromAccountId = own.id
        await assertRejected(mixed, in: other.id, "ni una sola cuenta de otro hogar")
        let stored = try await home.backend.movements(in: other.id, accountId: nil, limit: 50)
        XCTAssertTrue(stored.isEmpty, "lo rechazado no deja ninguna pata")
    }
}
