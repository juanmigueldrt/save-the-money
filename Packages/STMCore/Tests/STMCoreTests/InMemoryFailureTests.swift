import XCTest
@testable import STMCore

/// Los fallos a propósito del backend en memoria: sin pedirlos no cambia nada (modo demo),
/// y pedidos fallan la llamada que toca, ni antes ni después. Datos inventados.
final class InMemoryFailureTests: XCTestCase {
    private func signedIn() async throws -> (InMemoryBackend, Household, Account) {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        let home = try await backend.createHousehold(name: "Casa de prueba")
        let account = try await backend.createAccount(AccountDraft(name: "Corriente"), in: home.id)
        return (backend, home, account)
    }

    private func draft(_ account: Account, _ cents: Int) -> MovementDraft {
        MovementDraft(accountId: account.id, bookedOn: CalendarDay(year: 2026, month: 11, day: 1)!,
                      amount: Money(minor: cents), description: "Prueba")
    }

    func testWithoutInjectedFailuresEverythingWorks() async throws {
        let (backend, home, account) = try await signedIn()
        _ = try await backend.addMovement(draft(account, -1_000), in: home.id)
        _ = try await backend.addMovement(draft(account, -2_000), in: home.id)
        let balances = try await backend.balances(in: home.id)
        XCTAssertEqual(balances[account.id], Money(minor: -3_000))
    }

    func testNetworkFailureOnEveryCall() async throws {
        let (backend, home, account) = try await signedIn()
        await backend.failCalls()
        do {
            _ = try await backend.addMovement(draft(account, -1_000), in: home.id)
            XCTFail("tenía que fallar")
        } catch {
            XCTAssertEqual(error as? AppError, .network)
        }
        do {
            _ = try await backend.accounts(in: home.id)
            XCTFail("tenía que fallar")
        } catch {
            XCTAssertEqual(error as? AppError, .network)
        }
        await backend.clearFailures()
        let stored = try await backend.movements(in: home.id, accountId: nil, limit: 10)
        XCTAssertTrue(stored.isEmpty, "lo que falla no se guarda")
    }

    func testCancellation() async throws {
        let (backend, home, account) = try await signedIn()
        await backend.failCalls("addMovement(_:in:)", with: CancellationError())
        do {
            _ = try await backend.addMovement(draft(account, -1_000), in: home.id)
            XCTFail("tenía que fallar")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        // Las demás llamadas siguen funcionando.
        let accounts = try await backend.accounts(in: home.id)
        XCTAssertEqual(accounts.count, 1)
    }

    func testSecondWriteFailsAfterTheFirstSucceeds() async throws {
        let (backend, home, account) = try await signedIn()
        await backend.failCalls("addMovement(_:in:)", after: 1)
        _ = try await backend.addMovement(draft(account, -1_000), in: home.id)
        do {
            _ = try await backend.addMovement(draft(account, 1_000), in: home.id)
            XCTFail("la segunda tenía que fallar")
        } catch {
            XCTAssertEqual(error as? AppError, .network)
        }
        // Las lecturas no cuentan ni fallan.
        let stored = try await backend.movements(in: home.id, accountId: nil, limit: 10)
        XCTAssertEqual(stored.map(\.amount.minor), [-1_000])
    }

    func testSignOutCanFail() async throws {
        let (backend, _, _) = try await signedIn()
        await backend.failCalls("signOut()")
        do {
            try await backend.signOut()
            XCTFail("tenía que fallar")
        } catch {
            XCTAssertEqual(error as? AppError, .network)
        }
        let user = await backend.currentUserId()
        XCTAssertNotNil(user)
    }
}
