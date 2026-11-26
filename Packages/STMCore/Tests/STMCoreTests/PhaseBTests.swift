import XCTest
@testable import STMCore

/// Fase B: excluidos, revisados, etiquetas, beneficiario, edición masiva, parecidos,
/// cuenta predeterminada, cuentas fuera del patrimonio y formatos de CSV recordados.
final class PhaseBTests: XCTestCase {
    private let home = UUID()
    private let account = UUID()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }

    private func movement(_ text: String, _ minor: Int, on date: CalendarDay? = nil, category: UUID? = nil,
                          excluded: Bool = false, tags: [String] = [], payee: String? = nil) -> Movement {
        Movement(householdId: home, accountId: account, categoryId: category, bookedOn: date ?? day(2026, 11, 10),
                 amount: Money(minor: minor), description: text, excluded: excluded, payee: payee, tags: tags)
    }

    // MARK: Etiquetas y beneficiario

    func testTagsNormalizeAndValidate() {
        XCTAssertEqual(MovementTags.normalize("#Viaje, cumple  viaje;Boda-Ana"), ["viaje", "cumple", "boda-ana"])
        XCTAssertEqual(MovementTags.normalize("  ,, "), [])
        XCTAssertEqual(MovementTags.clean("#Año!"), "año")
        XCTAssertNil(MovementTags.issue(["viaje", "año_2026"]))
        XCTAssertNotNil(MovementTags.issue(["Viaje"]))
        XCTAssertNotNil(MovementTags.issue(["con espacio"]))
        XCTAssertNotNil(MovementTags.issue([String(repeating: "a", count: 31)]))
        XCTAssertNotNil(MovementTags.issue((1...11).map { "t\($0)" }))
        let draft = MovementDraft(accountId: account, bookedOn: day(2026, 11, 1), amount: Money(minor: -100),
                                  description: "CAFE", tags: ["Mal"])
        XCTAssertNotNil(draft.issue)
        XCTAssertEqual(Payee.clean("  Tienda   del  barrio "), "Tienda del barrio")
        XCTAssertNil(Payee.clean("   "))
    }

    func testTagsAndPayeesByUse() {
        let list = [movement("A", -100, tags: ["casa", "obra"], payee: "Ferretería"),
                    movement("B", -100, tags: ["obra"], payee: "ferretería"),
                    movement("C", -100, tags: ["viaje"], payee: "Hotel")]
        XCTAssertEqual(MovementTags.all(in: list), ["obra", "casa", "viaje"])
        XCTAssertEqual(Payee.all(in: list).count, 2)
        XCTAssertEqual(Payee.all(in: list).last, "Hotel")
    }

    // MARK: Excluidos

    func testExcludedMovementsSkipBudgetReportsAndDayTotals() {
        let food = BudgetCategory(householdId: home, name: "Comida", kind: .expense, budgetGroup: .needs)
        let list = [movement("SUPER", -5_000, category: food.id),
                    movement("REGALO DEVUELTO", -2_000, category: food.id, excluded: true)]
        let range = day(2026, 11, 1)...day(2026, 11, 30)
        XCTAssertEqual(SpendingReport(movements: list, categories: [food], range: range).total.minor, 5_000)
        let budget = BudgetReport(budget: nil, month: MonthKey(year: 2026, month: 11), categories: [food], movements: list)
        XCTAssertEqual(budget.totalSpent.minor, 5_000)
        XCTAssertEqual(MovementDay.group(list, categories: [food]).first?.total.minor, -5_000)
        // Pero el filtro de excluidos los enseña para poder volver a incluirlos.
        var filter = MovementFilter()
        filter.status = .excluded
        XCTAssertEqual(filter.apply(to: list, categories: [food]).map(\.description), ["REGALO DEVUELTO"])
    }

    // MARK: Revisados y filtro por etiqueta

    func testReviewedAndTagFilters() {
        var reviewed = movement("LUZ", -6_000, tags: ["casa"])
        reviewed.reviewedAt = Date()
        let list = [reviewed, movement("CINE", -1_200, tags: ["ocio"], payee: "Cines Centro")]
        var filter = MovementFilter(status: .unreviewed)
        XCTAssertEqual(filter.apply(to: list, categories: []).map(\.description), ["CINE"])
        filter.status = .reviewed
        XCTAssertEqual(filter.apply(to: list, categories: []).map(\.description), ["LUZ"])
        filter = MovementFilter(tag: "casa")
        XCTAssertEqual(filter.apply(to: list, categories: []).map(\.description), ["LUZ"])
        XCTAssertEqual(filter.activeCount, 1)
        XCTAssertEqual(MovementFilter(search: "#ocio").apply(to: list, categories: []).map(\.description), ["CINE"])
        XCTAssertEqual(MovementFilter(search: "centro").apply(to: list, categories: []).map(\.description), ["CINE"])
    }

    // MARK: Edición masiva

    func testBulkEdit() {
        let other = UUID()
        let category = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var already = movement("B", -200, tags: ["viaje"])
        already.reviewedAt = Date(timeIntervalSince1970: 1)
        let list = [movement("A", -100, tags: ["casa"]), already]
        let edit = MovementBulkEdit(bookedOn: day(2026, 11, 3), categoryId: .some(category), accountId: other,
                                    reviewed: true, addTags: ["viaje"], removeTags: ["casa"])
        let changed = edit.changes(for: list, now: now)
        XCTAssertEqual(changed.count, 2)
        XCTAssertEqual(changed[0].tags, ["viaje"])
        XCTAssertEqual(changed[0].reviewedAt, now)
        XCTAssertEqual(changed[1].reviewedAt, Date(timeIntervalSince1970: 1), "conserva la fecha de revisado")
        XCTAssertTrue(changed.allSatisfy { $0.accountId == other && $0.categoryId == category && $0.bookedOn == day(2026, 11, 3) })
        // Quitar la categoría y no tocar lo que ya está igual.
        XCTAssertEqual(MovementBulkEdit(categoryId: .some(nil)).changes(for: list).count, 0)
        XCTAssertEqual(MovementBulkEdit(excluded: true).changes(for: list).count, 2)
        XCTAssertTrue(MovementBulkEdit().isEmpty)
        XCTAssertEqual(MovementBulkEdit(reviewed: false).applied(to: already).reviewedAt, nil)
    }

    // MARK: Cambiar los parecidos

    func testSimilarMovements() {
        let food = UUID()
        let first = movement("COMPRA MERCADONA 1234", -3_000)
        let list = [first,
                    movement("Compra Mercadona 99", -1_500),
                    movement("COMPRA MERCADONA", -900, category: food),
                    movement("DEVOLUCION MERCADONA", 900),
                    movement("COMPRA LIDL", -2_000)]
        XCTAssertEqual(SimilarMovements.key("COMPRA MERCADONA 1234 TARJ. 5678"), "compra mercadona tarj")
        XCTAssertEqual(SimilarMovements.matches(for: first, in: list, categoryId: food).map(\.description),
                       ["Compra Mercadona 99"])
        XCTAssertEqual(SimilarMovements.matches(for: first, in: list, categoryId: nil).map(\.description),
                       ["COMPRA MERCADONA"])
    }

    // MARK: Informes por etiqueta y por beneficiario

    func testGroupedSpending() {
        let transfer = BudgetCategory(householdId: home, name: "Traspaso", kind: .transfer)
        let list = [movement("HOTEL", -20_000, tags: ["viaje"], payee: "Hotel Sol"),
                    movement("TREN", -5_000, tags: ["viaje", "trabajo"]),
                    movement("DIETAS", 3_000, tags: ["trabajo"]),
                    movement("OCULTO", -9_000, excluded: true, tags: ["viaje"]),
                    movement("A AHORRO", -10_000, category: transfer.id, tags: ["viaje"]),
                    movement("FUERA", -1_000, on: day(2026, 10, 1), tags: ["viaje"])]
        let range = day(2026, 11, 1)...day(2026, 11, 30)
        let byTag = GroupedSpending.report(.tag, movements: list, categories: [transfer], range: range)
        XCTAssertEqual(byTag.map(\.title), ["viaje", "trabajo"])
        XCTAssertEqual(byTag[0].spent.minor, 25_000)
        XCTAssertEqual(byTag[1].spent.minor, 5_000)
        XCTAssertEqual(byTag[1].income.minor, 3_000)
        let byPayee = GroupedSpending.report(.payee, movements: list, categories: [transfer], range: range)
        XCTAssertEqual(byPayee.map(\.title), ["Hotel Sol"])
    }

    /// Un traspaso importado (dos movimientos sin categoría, mismo día, importes opuestos, cuentas distintas) no es gasto ni ingreso.
    func testGroupedSpendingSkipsUncategorizedTransfers() {
        var entrada = movement("DE NOMINA", 10_000, tags: ["ahorro"])
        entrada.accountId = UUID()
        let list = [movement("A AHORRO", -10_000, tags: ["ahorro"]), entrada, movement("HUCHA", -700, tags: ["ahorro"])]
        let byTag = GroupedSpending.report(.tag, movements: list, categories: [], range: day(2026, 11, 1)...day(2026, 11, 30))
        XCTAssertEqual(byTag.map(\.spent.minor), [700])
        XCTAssertEqual(byTag.map(\.income.minor), [0])
    }

    // MARK: Cuentas

    func testDefaultAccountAndNetWorth() async throws {
        let a = Account(householdId: home, name: "Nómina", kind: .checking, openingBalance: Money(minor: 10_000))
        var b = Account(householdId: home, name: "Tarjeta", kind: .checking, openingBalance: .zero, isDefault: true)
        let c = Account(householdId: home, name: "Coche", kind: .savings, openingBalance: Money(minor: 500_000),
                        includeInNetWorth: false)
        XCTAssertEqual([a, b, c].defaultAccount?.id, b.id)
        b.archivedAt = Date()
        XCTAssertEqual([a, b, c].defaultAccount?.id, a.id)
        XCTAssertNil([Account]().defaultAccount)
        let point = NetWorth.current(accounts: [a, c], balances: [:])
        XCTAssertEqual(point.net.minor, 10_000)
        let history = NetWorth.history(accounts: [a, c], movements: [], months: 1, through: MonthKey(year: 2026, month: 11))
        XCTAssertEqual(history.last?.net.minor, 10_000)
    }

    func testInMemoryKeepsOneDefaultAccountAndNewFields() async throws {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        let house = try await backend.createHousehold(name: "Casa")
        var first = try await backend.createAccount(AccountDraft(name: "Corriente"), in: house.id)
        var second = try await backend.createAccount(AccountDraft(name: "Ahorro"), in: house.id)
        first.isDefault = true
        _ = try await backend.updateAccount(first)
        second.isDefault = true
        _ = try await backend.updateAccount(second)
        let after = try await backend.accounts(in: house.id)
        XCTAssertEqual(after.filter(\.isDefault).map(\.id), [second.id])

        let draft = MovementDraft(accountId: second.id, bookedOn: CalendarDay(), amount: Money(minor: -1_000),
                                  description: "PRUEBA", excluded: true, payee: "  Tienda  ", tags: ["prueba"])
        var saved = try await backend.addMovement(draft, in: house.id)
        XCTAssertTrue(saved.excluded)
        XCTAssertEqual(saved.payee, "Tienda")
        XCTAssertEqual(saved.tags, ["prueba"])
        saved.reviewedAt = Date()
        saved.excluded = false
        let updated = try await backend.updateMovement(saved)
        XCTAssertTrue(updated.isReviewed)
        XCTAssertFalse(updated.excluded)
        // El excluido sigue contando en el saldo.
        let balances = try await backend.balances(in: house.id)
        XCTAssertEqual(balances[second.id]?.minor, -1_000)
    }

    // MARK: Formatos de CSV recordados

    func testSavedCSVFormat() throws {
        let text = "Banco de prueba\nFecha;Concepto;Cargo;Abono\n01/11/2026;CAFE;1,50;\n02/11/2026;NOMINA;;1000\n"
        let table = CSVTable.parse(text)
        let mapping = try XCTUnwrap(CSVMapping.detect(in: table))
        let format = CSVSavedFormat(table: table, mapping: mapping, accountId: account)
        XCTAssertEqual(format.mapping, mapping)
        let saved = CSVSavedFormat.remember(format, in: [])
        let sameBank = "Otro titular\nFecha;Concepto;Cargo;Abono\n05/11/2026;PAN;1;\n"
        XCTAssertEqual(CSVSavedFormat.match(text: sameBank, in: saved)?.format.accountId, account)
        XCTAssertNil(CSVSavedFormat.match(text: "Date,Amount,Text\n2026-11-01,1,a\n", in: saved))
        // Guardar otra vez el mismo formato no lo duplica.
        XCTAssertEqual(CSVSavedFormat.remember(format, in: saved).count, 1)
        let data = try JSONEncoder().encode(saved)
        XCTAssertEqual(try JSONDecoder().decode([CSVSavedFormat].self, from: data), saved)
    }

    func testSavedCSVFormatRemembersDelimiter() throws {
        // Separador elegido a mano (coma): el siguiente archivo del banco se lee con él.
        let table = CSVTable.parse("Banco de prueba\nFecha,Concepto,Importe\n01/11/2026,CAFE,-1.50\n02/11/2026,NOMINA,1000\n", delimiter: ",")
        let mapping = try XCTUnwrap(CSVMapping.detect(in: table))
        let format = CSVSavedFormat(table: table, mapping: mapping, accountId: account)
        XCTAssertEqual(format.delimiter, ",")
        let saved = CSVSavedFormat.remember(format, in: [])
        let sameBank = "Otro titular\nFecha,Concepto,Importe\n05/11/2026,PAN,-2.00\n"
        let found = try XCTUnwrap(CSVSavedFormat.match(text: sameBank, in: saved))
        XCTAssertEqual(found.table.delimiter, ",")
        XCTAssertEqual(found.table.rows, CSVTable.parse(sameBank, delimiter: ",").rows)
        // Un formato guardado sin separador (anterior a recordarlo) se lee con el detectado.
        var legacy = format
        legacy.delimiter = nil
        XCTAssertEqual(CSVSavedFormat.match(text: sameBank, in: [legacy])?.table.delimiter, CSVTable.parse(sameBank).delimiter)
    }

    func testCSVRowReview() throws {
        let table = CSVTable.parse("Fecha;Concepto;Importe\n01/11/2026;CAFE;-1,50\n02/11/2026;REGALO;-30\n03/11/2026;NOMINA;1000\n")
        let mapping = try XCTUnwrap(CSVMapping.detect(in: table))
        let rows = CSVImporter.rows(in: table, mapping: mapping, accountId: account)
        let gift = UUID()
        var review = CSVRowReview()
        review.skipped.insert(rows[0].line)
        review.excluded.insert(rows[1].line)
        review.categories[rows[1].line] = .some(gift)
        let result = review.apply(to: rows)
        XCTAssertEqual(result.map(\.draft?.description), ["REGALO", "NOMINA"])
        XCTAssertEqual(result[0].draft?.excluded, true)
        XCTAssertEqual(result[0].draft?.categoryId, gift)
        XCTAssertEqual(result[1].draft?.excluded, false)
        review.keep([rows[1].line])
        XCTAssertTrue(review.skipped.isEmpty)
        XCTAssertEqual(review.excluded, [rows[1].line])
    }
}
