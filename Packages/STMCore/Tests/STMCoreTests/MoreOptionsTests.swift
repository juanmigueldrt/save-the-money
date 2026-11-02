import XCTest
@testable import STMCore

/// Categorías propias, exportar y empezar de cero. Datos inventados.
final class MoreOptionsTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }

    private func signedInHome() async throws -> (InMemoryBackend, Household) {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("prueba"), password: "contrasena-de-prueba", displayName: nil)
        let home = try await backend.createHousehold(name: "Casa de prueba")
        return (backend, home)
    }

    func testCategoryValidation() {
        let home = UUID()
        let existing = BudgetCategory(householdId: home, name: "Mascotas", kind: .expense)
        XCTAssertNotNil(BudgetCategory(householdId: home, name: "  ").issue(among: []))
        XCTAssertNotNil(BudgetCategory(householdId: home, name: String(repeating: "a", count: 41)).issue(among: []))
        XCTAssertNotNil(BudgetCategory(householdId: home, name: "mascotas ").issue(among: [existing]))
        XCTAssertNil(BudgetCategory(householdId: home, name: "Mascotas", kind: .income).issue(among: [existing]))
        XCTAssertNil(existing.issue(among: [existing]), "una categoría no choca consigo misma")
        XCTAssertNotNil(BudgetCategory(householdId: home, name: "Bono", kind: .income, budgetGroup: .wants).issue(among: []))
    }

    func testCustomCategoryLifecycle() async throws {
        let (backend, home) = try await signedInHome()
        let pets = try await backend.createCategory(BudgetCategory(householdId: home.id, name: " Mascotas ", kind: .expense,
                                                                   budgetGroup: .needs, icon: "pawprint"))
        XCTAssertEqual(pets.name, "Mascotas")
        do {
            _ = try await backend.createCategory(BudgetCategory(householdId: home.id, name: "MASCOTAS"))
            XCTFail("no debería permitir el nombre repetido")
        } catch {}

        var renamed = pets
        renamed.name = "Animales"
        renamed.kind = .income // el tipo no se cambia
        let updated = try await backend.updateCategory(renamed)
        XCTAssertEqual(updated.name, "Animales")
        XCTAssertEqual(updated.kind, .expense)

        let account = try await backend.createAccount(AccountDraft(name: "Cuenta común"), in: home.id)
        let movement = try await backend.addMovement(
            MovementDraft(accountId: account.id, categoryId: pets.id, bookedOn: day(2026, 11, 1),
                          amount: Money(minor: -1_500), description: "Pienso"), in: home.id)
        try await backend.deleteCategory(pets.id)
        let movements = try await backend.movements(in: home.id, accountId: nil, limit: 10)
        XCTAssertEqual(movements.first?.id, movement.id)
        XCTAssertNil(movements.first?.categoryId, "el movimiento se queda sin categoría")
        let count = try await backend.categories(in: home.id).count
        XCTAssertEqual(count, BudgetCategory.defaults(for: home.id).count)
    }

    func testResetHouseholdLeavesDefaults() async throws {
        let (backend, home) = try await signedInHome()
        _ = try await backend.createCategory(BudgetCategory(householdId: home.id, name: "Mascotas"))
        let account = try await backend.createAccount(AccountDraft(name: "Cuenta común"), in: home.id)
        _ = try await backend.addMovement(MovementDraft(accountId: account.id, bookedOn: day(2026, 11, 1),
                                                        amount: Money(minor: -500), description: "Café"), in: home.id)
        _ = try await backend.createRecurring(RecurringSeries(householdId: home.id, name: "Música", amount: Money(minor: 999),
                                                             startsOn: day(2026, 11, 5)))
        _ = try await backend.createGoal(Goal(householdId: home.id, name: "Viaje", target: Money(minor: 100_000)))

        try await backend.resetHousehold(home.id)

        let accounts = try await backend.accounts(in: home.id)
        let movements = try await backend.movements(in: home.id, accountId: nil, limit: 10)
        let series = try await backend.recurringSeries(in: home.id)
        let goals = try await backend.goals(in: home.id)
        let categories = try await backend.categories(in: home.id)
        XCTAssertTrue(accounts.isEmpty && movements.isEmpty && series.isEmpty && goals.isEmpty)
        XCTAssertEqual(categories.map(\.name).sorted(), BudgetCategory.defaults(for: home.id).map(\.name).sorted())
        let households = try await backend.households()
        XCTAssertEqual(households.map(\.id), [home.id], "el hogar sigue ahí")
    }

    func testMovementsCSVForSpanishExcel() {
        let home = UUID()
        let account = Account(householdId: home, name: "Cuenta; común")
        let food = BudgetCategory(householdId: home, name: "Supermercado")
        let movements = [
            Movement(householdId: home, accountId: account.id, categoryId: food.id, bookedOn: day(2026, 11, 3),
                     amount: Money(minor: -123_456), description: "Compra \"grande\""),
            Movement(householdId: home, accountId: account.id, bookedOn: day(2026, 11, 1),
                     amount: Money(minor: 5), description: "=HYPERLINK(\"x\")", notes: "línea 1\nlínea 2"),
        ]
        let text = MovementsCSV.text(movements, accounts: [account], categories: [food])
        let lines = text.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0], "Fecha;Cuenta;Categoría;Descripción;Importe;Moneda;Notas")
        XCTAssertEqual(lines[1], "01/11/2026;\"Cuenta; común\";;\"'=HYPERLINK(\"\"x\"\")\";0,05;EUR;\"línea 1\nlínea 2\"",
                       "los más antiguos primero; las fórmulas se desactivan")
        XCTAssertEqual(lines[2], "03/11/2026;\"Cuenta; común\";Supermercado;\"Compra \"\"grande\"\"\";-1234,56;EUR;")
        let data = MovementsCSV.data(movements, accounts: [account], categories: [food])
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertEqual(MovementsCSV.amountText(Money(minor: -7)), "-0,07")
    }

    func testMonthlyBills() {
        let home = UUID()
        let account = Account(householdId: home, name: "Cuenta común")
        let series = [
            RecurringSeries(householdId: home, name: "Alquiler", kind: .essential, amount: Money(minor: 80_000),
                            accountId: account.id, startsOn: day(2026, 1, 31)),
            RecurringSeries(householdId: home, name: "Gimnasio", amount: Money(minor: 1_000),
                            recurrence: Recurrence(every: 2, unit: .week), startsOn: day(2026, 11, 2)),
            RecurringSeries(householdId: home, name: "Nómina", kind: .income, amount: Money(minor: 200_000),
                            startsOn: day(2026, 1, 28)),
            RecurringSeries(householdId: home, name: "Antigua", amount: Money(minor: 500), startsOn: day(2026, 1, 1),
                            archivedAt: Date()),
        ]
        let bills = MonthlyBills(series: series, month: MonthKey(year: 2026, month: 11), accounts: [account])
        XCTAssertEqual(bills.lines.map(\.due), [day(2026, 11, 2), day(2026, 11, 16), day(2026, 11, 30), day(2026, 11, 30)])
        XCTAssertEqual(bills.lines.last?.name, "Gimnasio")
        XCTAssertEqual(bills.lines.first(where: { $0.name == "Alquiler" })?.accountName, "Cuenta común")
        XCTAssertEqual(bills.total, Money(minor: 83_000))
        XCTAssertEqual(bills.total(of: .essential), Money(minor: 80_000))
        XCTAssertEqual(bills.pending(from: day(2026, 11, 17)), Money(minor: 81_000))
        XCTAssertEqual(bills.fileName, "pagos-2026-11.pdf")
    }
}
