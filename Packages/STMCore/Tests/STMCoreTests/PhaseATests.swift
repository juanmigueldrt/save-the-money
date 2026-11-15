import XCTest
@testable import STMCore

/// Fase A: calculadora, filtros, lista por días, vista de importes, ajuste de saldo,
/// total anual de pagos fijos, comparación de informes y predicción del patrimonio.
final class PhaseATests: XCTestCase {
    private let home = UUID()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }

    // MARK: Calculadora

    func testAmountExpression() {
        XCTAssertEqual(AmountExpression.evaluate("12,50+3×2")?.minor, 1_850)
        XCTAssertEqual(AmountExpression.evaluate("12.50 + 3*2")?.minor, 1_850)
        XCTAssertEqual(AmountExpression.evaluate("(10+5)×2")?.minor, 3_000)
        XCTAssertEqual(AmountExpression.evaluate("100/3")?.minor, 3_333)
        XCTAssertEqual(AmountExpression.evaluate("10÷4")?.minor, 250)
        XCTAssertEqual(AmountExpression.evaluate("20−7,40")?.minor, 1_260)
        XCTAssertEqual(AmountExpression.evaluate("-5+2")?.minor, -300)
        XCTAssertEqual(AmountExpression.evaluate("1.234,56+0,44")?.minor, 123_500)
        XCTAssertNil(AmountExpression.evaluate("10/0"))
        XCTAssertNil(AmountExpression.evaluate("10+"))
        XCTAssertNil(AmountExpression.evaluate("(10+2"))
        XCTAssertNil(AmountExpression.evaluate("abc"))
        XCTAssertNil(AmountExpression.evaluate(""))
    }

    func testEnteredAmountAndOperationDetection() {
        XCTAssertEqual(Money(entered: "12,50")?.minor, 1_250)
        XCTAssertEqual(Money(entered: "25+7,40")?.minor, 3_240)
        XCTAssertEqual(Money(entered: "-12")?.minor, -1_200)
        XCTAssertNil(Money(entered: "12,5x"))
        XCTAssertTrue(AmountExpression.hasOperation("25+7"))
        XCTAssertTrue(AmountExpression.hasOperation("(3)"))
        XCTAssertFalse(AmountExpression.hasOperation("-25"))
        XCTAssertFalse(AmountExpression.hasOperation("1.234,56"))
    }

    // MARK: Filtros y lista por días

    private func fixture() -> (categories: [BudgetCategory], movements: [Movement], a: UUID, b: UUID) {
        let a = UUID(), b = UUID()
        let food = BudgetCategory(householdId: home, name: "Supermercado", kind: .expense)
        let salary = BudgetCategory(householdId: home, name: "Nómina", kind: .income)
        let transfer = BudgetCategory(householdId: home, name: "Transferencia entre cuentas", kind: .transfer)
        let movements = [
            Movement(householdId: home, accountId: a, categoryId: food.id, bookedOn: day(2026, 11, 14),
                     amount: Money(minor: -1_250), description: "MERCADONA"),
            Movement(householdId: home, accountId: a, categoryId: salary.id, bookedOn: day(2026, 11, 1),
                     amount: Money(minor: 200_000), description: "NOMINA"),
            Movement(householdId: home, accountId: a, categoryId: transfer.id, bookedOn: day(2026, 11, 14),
                     amount: Money(minor: -5_000), description: "A AHORRO"),
            Movement(householdId: home, accountId: b, categoryId: transfer.id, bookedOn: day(2026, 11, 14),
                     amount: Money(minor: 5_000), description: "A AHORRO"),
            Movement(householdId: home, accountId: b, categoryId: nil, bookedOn: day(2026, 10, 20),
                     amount: Money(minor: -899), description: "CINE", notes: "con amigos"),
        ]
        return ([food, salary, transfer], movements, a, b)
    }

    func testFilterByAccountKindAndDates() {
        let f = fixture()
        let today = day(2026, 11, 15)
        XCTAssertEqual(MovementFilter(accountId: f.b).apply(to: f.movements, categories: f.categories, today: today).count, 2)
        XCTAssertEqual(MovementFilter(kind: .expense).apply(to: f.movements, categories: f.categories, today: today)
            .map(\.description), ["MERCADONA", "CINE"])
        XCTAssertEqual(MovementFilter(kind: .income).apply(to: f.movements, categories: f.categories, today: today)
            .map(\.description), ["NOMINA"])
        XCTAssertEqual(MovementFilter(kind: .transfer).apply(to: f.movements, categories: f.categories, today: today).count, 2)
        XCTAssertEqual(MovementFilter(dates: .thisMonth).apply(to: f.movements, categories: f.categories, today: today).count, 4)
        XCTAssertEqual(MovementFilter(dates: .lastMonth).apply(to: f.movements, categories: f.categories, today: today)
            .map(\.description), ["CINE"])
        let custom = MovementFilter(dates: .custom, customFrom: day(2026, 11, 2), customThrough: day(2026, 10, 1))
        XCTAssertEqual(custom.apply(to: f.movements, categories: f.categories, today: today).map(\.description), ["NOMINA", "CINE"])
        XCTAssertEqual(MovementFilter(accountId: f.a, kind: .expense, dates: .thisMonth).activeCount, 3)
    }

    func testSearchByTextNotesCategoryAndAmount() {
        let f = fixture()
        func search(_ q: String) -> [String] {
            MovementFilter(search: q).apply(to: f.movements, categories: f.categories, today: day(2026, 11, 15)).map(\.description)
        }
        XCTAssertEqual(search("merca"), ["MERCADONA"])
        XCTAssertEqual(search("amigos"), ["CINE"])
        XCTAssertEqual(search("super"), ["MERCADONA"])
        XCTAssertEqual(search("12,50"), ["MERCADONA"])
        XCTAssertEqual(search("8.99"), ["CINE"])
        XCTAssertEqual(search("50"), ["A AHORRO", "A AHORRO"])
        XCTAssertEqual(search("-50"), ["A AHORRO"])
        XCTAssertEqual(search("2000"), ["NOMINA"])
    }

    func testGroupsByDayWithoutCountingTransfers() {
        let f = fixture()
        let days = MovementDay.group(f.movements, categories: f.categories)
        XCTAssertEqual(days.map(\.day), [day(2026, 11, 14), day(2026, 11, 1), day(2026, 10, 20)])
        XCTAssertEqual(days[0].movements.count, 3)
        XCTAssertEqual(days[0].total.minor, -1_250)
        XCTAssertEqual(days[1].total.minor, 200_000)
    }

    // MARK: Vista de importes

    func testDisplayOptions() {
        let money = Money(minor: 123_456)
        XCTAssertEqual(money.formatted(options: MoneyDisplayOptions(hidesAmounts: true)), "•••• €")
        XCTAssertEqual(money.formatted(options: MoneyDisplayOptions(roundsToUnits: true)).filter(\.isNumber), "1235")
        XCTAssertEqual(money.formatted(options: .standard).filter(\.isNumber), "123456")
        XCTAssertTrue(money.signedText(options: .standard).hasPrefix("+"))
        XCTAssertTrue(Money(minor: -500).signedText(options: .standard).hasPrefix("\u{2212}"))
        XCTAssertEqual(Money(minor: -500).signedText(options: MoneyDisplayOptions(hidesAmounts: true)), "•••• €")

        let saved = Money.display
        defer { Money.display = saved }
        Money.display = MoneyDisplayOptions(hidesAmounts: true)
        XCTAssertEqual(money.formatted(), "•••• €")
        Money.display = .standard
        XCTAssertNotEqual(money.formatted(), "•••• €")
    }

    // MARK: Actualizar saldo

    func testBalanceAdjustment() {
        let f = fixture()
        let account = Account(householdId: home, name: "Nómina")
        let draft = BalanceAdjustment.draft(account: account, current: Money(minor: 10_000), actual: Money(minor: 9_250),
                                            on: day(2026, 11, 15), categories: f.categories)
        XCTAssertEqual(draft?.amount.minor, -750)
        XCTAssertEqual(draft?.categoryId, f.categories[2].id)
        XCTAssertEqual(draft?.description, BalanceAdjustment.description)
        XCTAssertNil(draft?.issue)
        XCTAssertNil(BalanceAdjustment.draft(account: account, current: Money(minor: 10_000), actual: Money(minor: 10_000),
                                             on: day(2026, 11, 15), categories: f.categories))
    }

    // MARK: Pagos fijos: total del año

    func testYearlyTotalCountsIntroPriceAndEndDate() {
        let music = RecurringSeries(householdId: home, name: "Música", kind: .subscription, amount: Money(minor: 1_199),
                                    startsOn: day(2026, 11, 20), introAmount: Money(minor: 699), introCharges: 3)
        let gym = RecurringSeries(householdId: home, name: "Gimnasio", kind: .essential, amount: Money(minor: 3_000),
                                  startsOn: day(2026, 1, 5), endsOn: day(2027, 2, 5))
        let salary = RecurringSeries(householdId: home, name: "Nómina", kind: .income, amount: Money(minor: 200_000),
                                     startsOn: day(2026, 1, 28))
        let total = [music, gym, salary].yearlyTotal(of: [.subscription, .essential], from: day(2026, 11, 15))
        // Música: 3 × 6,99 + 9 × 11,99. Gimnasio: dic, ene, feb = 3 × 30.
        XCTAssertEqual(total.minor, 3 * 699 + 9 * 1_199 + 3 * 3_000)
    }

    // MARK: Informes

    func testPreviousRanges() {
        let today = day(2026, 3, 31)
        XCTAssertEqual(ReportPeriod.thisMonth.previousRange(today: today), day(2026, 2, 1)...day(2026, 2, 28))
        XCTAssertEqual(ReportPeriod.lastMonth.previousRange(today: today), day(2026, 1, 1)...day(2026, 1, 31))
        XCTAssertEqual(ReportPeriod.last3Months.previousRange(today: today), day(2025, 10, 1)...day(2025, 12, 31))
        XCTAssertEqual(ReportPeriod.thisYear.previousRange(today: today), day(2025, 1, 1)...day(2025, 3, 31))
        XCTAssertEqual(ReportPeriod.lastMonth.previousRange(today: day(2026, 4, 10)), day(2026, 2, 1)...day(2026, 2, 28))
    }

    func testAveragePerDayAndChange() {
        let f = fixture()
        let now = SpendingReport(movements: f.movements, categories: f.categories, range: day(2026, 11, 1)...day(2026, 11, 10))
        XCTAssertEqual(now.dayCount, 10)
        let november = SpendingReport(movements: f.movements, categories: f.categories, range: day(2026, 11, 1)...day(2026, 11, 15))
        let october = SpendingReport(movements: f.movements, categories: f.categories, range: day(2026, 10, 1)...day(2026, 10, 15))
        XCTAssertEqual(november.total.minor, 1_250)
        XCTAssertEqual(november.averagePerDay.minor, 83)
        XCTAssertEqual(october.total.minor, 0)
        XCTAssertNil(november.change(from: october).percent)
        let late = SpendingReport(movements: f.movements, categories: f.categories, range: day(2026, 10, 1)...day(2026, 10, 31))
        let change = november.change(from: late)
        XCTAssertEqual(change.difference.minor, 351)
        XCTAssertEqual(change.percent, 39)
    }

    // MARK: Patrimonio a final de año

    func testNetWorthProjection() {
        func point(_ m: Int, _ net: Int) -> NetWorthPoint {
            NetWorthPoint(month: MonthKey(year: 2026, month: m), assets: Money(minor: net), liabilities: .zero)
        }
        let projection = NetWorthProjection(history: [point(8, 100_000), point(9, 110_000), point(10, 115_000), point(11, 130_000)])
        XCTAssertEqual(projection?.monthlyChange.minor, 10_000)
        XCTAssertEqual(projection?.points.map(\.month.month), [11, 12])
        XCTAssertEqual(projection?.endOfYear.minor, 140_000)
        XCTAssertNil(NetWorthProjection(history: [point(11, 1)]))
        XCTAssertNil(NetWorthProjection(history: [point(11, 1), point(12, 2)]))
    }

    // MARK: Renombrar hogar

    func testOnlyOwnerRenamesHousehold() async throws {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: "Ana")
        let home = try await backend.createHousehold(name: "Casa")
        let renamed = try await backend.renameHousehold(home.id, to: "  Piso nuevo  ")
        XCTAssertEqual(renamed.name, "Piso nuevo")
        let stored = try await backend.households()
        XCTAssertEqual(stored.first?.name, "Piso nuevo")
        do {
            _ = try await backend.renameHousehold(home.id, to: "   ")
            XCTFail("Un nombre vacío no vale")
        } catch {}

        let invite = try await backend.createInvite(for: home.id)
        try await backend.signOut()
        _ = try await backend.signUp(username: Username("luis"), password: "contrasena-de-prueba", displayName: "Luis")
        _ = try await backend.acceptInvite(InviteCode(invite.code)!)
        do {
            _ = try await backend.renameHousehold(home.id, to: "Mío")
            XCTFail("Sólo el dueño cambia el nombre")
        } catch {}
    }
}
