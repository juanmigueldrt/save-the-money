import XCTest
@testable import STMCore

final class FinanceTests: XCTestCase {
    func testDecodesServerRows() throws {
        let account = try JSONDecoder().decode(Account.self, from: Data("""
        {"id":"00000000-0000-0000-0000-0000000000a1","household_id":"00000000-0000-0000-0000-0000000000f1",
         "name":"Corriente","kind":"credit_card","currency":"EUR","opening_balance_minor":-1250,
         "owner_id":null,"archived_at":"2026-10-28T10:00:00.123456+00:00"}
        """.utf8))
        XCTAssertEqual(account.kind, .creditCard)
        XCTAssertEqual(account.openingBalance.minor, -1250)
        XCTAssertTrue(account.isShared)
        XCTAssertTrue(account.isArchived)

        let movement = try JSONDecoder().decode(Movement.self, from: Data("""
        {"id":"00000000-0000-0000-0000-0000000000b1","household_id":"00000000-0000-0000-0000-0000000000f1",
         "account_id":"00000000-0000-0000-0000-0000000000a1","category_id":null,"booked_on":"2026-10-03",
         "amount_minor":-4520,"description":"Compra","notes":null,"import_hash":null}
        """.utf8))
        XCTAssertEqual(movement.bookedOn, CalendarDay(year: 2026, month: 10, day: 3))
        XCTAssertTrue(movement.isExpense)

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(movement)) as? [String: Any]
        XCTAssertEqual(encoded?["booked_on"] as? String, "2026-10-03")
        XCTAssertEqual(encoded?["amount_minor"] as? Int, -4520)
    }

    func testDraftValidation() {
        let day = CalendarDay(year: 2026, month: 10, day: 1)!
        XCTAssertNotNil(MovementDraft(accountId: UUID(), bookedOn: day, amount: Money(minor: 100), description: "  ").issue)
        XCTAssertNotNil(MovementDraft(accountId: UUID(), bookedOn: day, amount: .zero, description: "Algo").issue)
        XCTAssertNil(MovementDraft(accountId: UUID(), bookedOn: day, amount: Money(minor: -1), description: "Algo").issue)
        XCTAssertNotNil(AccountDraft(name: " ").issue)
        XCTAssertEqual(BudgetCategory.defaults(for: UUID()).count, 17, "las mismas que siembra el servidor")
    }

    func testOtherHouseholdsAreInvisible() async throws {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        let home = try await backend.createHousehold(name: "Casa")
        let account = try await backend.createAccount(AccountDraft(name: "Corriente", openingBalance: Money(minor: 1000)), in: home.id)
        let day = CalendarDay(year: 2026, month: 10, day: 1)!
        _ = try await backend.addMovement(MovementDraft(accountId: account.id, bookedOn: day, amount: Money(minor: -300), description: "Pan"), in: home.id)
        try await backend.signOut()

        _ = try await backend.signUp(username: Username("carla"), password: "contrasena-de-prueba", displayName: nil)
        let other = try await backend.createHousehold(name: "Otro")
        do {
            _ = try await backend.accounts(in: home.id)
            XCTFail("Carla no debe ver cuentas ajenas")
        } catch {}
        do {
            _ = try await backend.addMovement(MovementDraft(accountId: account.id, bookedOn: day, amount: Money(minor: -1), description: "Truco"), in: other.id)
            XCTFail("no se apunta en una cuenta de otro hogar")
        } catch {}
        let categories = try await backend.categories(in: other.id)
        XCTAssertEqual(categories.count, 17)
    }
}
