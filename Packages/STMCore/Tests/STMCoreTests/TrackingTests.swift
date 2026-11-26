import XCTest
@testable import STMCore

/// Patrimonio, score, informes, presupuesto flexible y avisos de límites. Datos inventados.
final class TrackingTests: XCTestCase {
    let home = UUID()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }

    private func move(_ account: Account, _ minor: Int, on date: CalendarDay, _ category: BudgetCategory? = nil,
                      _ text: String = "Movimiento") -> Movement {
        Movement(householdId: home, accountId: account.id, categoryId: category?.id, bookedOn: date,
                 amount: Money(minor: minor), description: text)
    }

    func testNetWorthNowAndHistory() {
        let checking = Account(householdId: home, name: "Cuenta común", openingBalance: Money(minor: 100_000))
        let card = Account(householdId: home, name: "Tarjeta", kind: .creditCard)
        let old = Account(householdId: home, name: "Antigua", openingBalance: Money(minor: 9_999), archivedAt: day(2026, 8, 15).date())
        let movements = [
            move(checking, 50_000, on: day(2026, 9, 28)),
            move(checking, -20_000, on: day(2026, 10, 15)),
            move(card, -30_000, on: day(2026, 11, 1)),
        ]
        let now = NetWorth.current(accounts: [checking, card, old],
                                   balances: [checking.id: Money(minor: 130_000), card.id: Money(minor: -30_000)],
                                   today: day(2026, 11, 2))
        XCTAssertEqual(now.assets, Money(minor: 130_000))
        XCTAssertEqual(now.liabilities, Money(minor: 30_000))
        XCTAssertEqual(now.net, Money(minor: 100_000), "las cuentas archivadas no cuentan")

        let history = NetWorth.history(accounts: [checking, card, old], movements: movements, months: 3,
                                       through: MonthKey(year: 2026, month: 11))
        XCTAssertEqual(history.map(\.month), [MonthKey(year: 2026, month: 9), MonthKey(year: 2026, month: 10),
                                              MonthKey(year: 2026, month: 11)])
        XCTAssertEqual(history.map(\.net.minor), [150_000, 130_000, 100_000])
        XCTAssertEqual(history.last?.liabilities, Money(minor: 30_000))
    }

    func testOpeningBalanceCountsFromCreation() {
        let today = day(2026, 11, 26)
        let fresh = Account(householdId: home, name: "Nueva", openingBalance: Money(minor: 2_000_000), createdAt: today.date())
        let history = NetWorth.history(accounts: [fresh], movements: [], months: 12, through: MonthKey(today))
        XCTAssertEqual(history.count, 12)
        XCTAssertEqual(history.dropLast().map(\.net.minor), Array(repeating: 0, count: 11),
                       "una cuenta creada hoy no existía los meses anteriores")
        XCTAssertEqual(history.last?.net, Money(minor: 2_000_000))

        let imported = Account(householdId: home, name: "Importada", openingBalance: Money(minor: 10_000),
                               createdAt: today.date())
        let older = NetWorth.history(accounts: [imported], movements: [move(imported, 5_000, on: day(2026, 9, 10))],
                                     months: 4, through: MonthKey(today))
        XCTAssertEqual(older.map(\.net.minor), [0, 15_000, 15_000, 15_000],
                       "con movimientos de antes del alta, el saldo inicial cuenta desde el primero")
    }

    func testArchivedAccountStaysUntilArchived() {
        let closed = Account(householdId: home, name: "Cerrada", openingBalance: Money(minor: 40_000),
                             archivedAt: day(2026, 10, 20).date())
        let history = NetWorth.history(accounts: [closed], movements: [], months: 3, through: MonthKey(year: 2026, month: 11))
        XCTAssertEqual(history.map(\.net.minor), [40_000, 0, 0], "cuenta en septiembre; en octubre ya estaba archivada")
        XCTAssertEqual(NetWorth.current(accounts: [closed], balances: [closed.id: Money(minor: 40_000)],
                                        today: day(2026, 11, 26)).net, .zero)
    }

    func testCreditScoreRatingAndValidation() {
        XCTAssertEqual(CreditScore(score: 760).rating, .excellent)
        XCTAssertEqual(CreditScore(score: 700).rating, .good)
        XCTAssertEqual(CreditScore(score: 600).rating, .fair)
        XCTAssertEqual(CreditScore(score: 500).rating, .poor)
        XCTAssertEqual(CreditScore(score: 900, maxScore: 1000).rating, .excellent)
        XCTAssertNotNil(CreditScore(score: 900).issue, "no puede pasar de la escala")
        XCTAssertNotNil(CreditScore(score: 50, maxScore: 50).issue)
        XCTAssertNil(CreditScore(score: 720, provider: "  ").issue)
        XCTAssertNil(CreditScore(score: 720, provider: "  ").trimmedProvider)
    }

    func testCreditScoresArePersonal() async throws {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        _ = try await backend.addCreditScore(CreditScore(score: 700, recordedOn: day(2026, 10, 1)))
        let latest = try await backend.addCreditScore(CreditScore(score: 720, recordedOn: day(2026, 11, 1)))
        let mine = try await backend.creditScores()
        XCTAssertEqual(mine.first?.id, latest.id, "el más reciente primero")
        do {
            _ = try await backend.addCreditScore(CreditScore(score: 900))
            XCTFail("score fuera de escala")
        } catch {}

        try await backend.signOut()
        _ = try await backend.signUp(username: Username("bruno"), password: "contrasena-de-prueba", displayName: nil)
        let others = try await backend.creditScores()
        XCTAssertTrue(others.isEmpty, "Bruno no ve los de Ana")
    }

    func testSpendingReport() {
        let account = Account(householdId: home, name: "Cuenta común")
        let food = BudgetCategory(householdId: home, name: "Supermercado", kind: .expense, budgetGroup: .needs, icon: "cart")
        let fun = BudgetCategory(householdId: home, name: "Ocio", kind: .expense, budgetGroup: .wants)
        let salary = BudgetCategory(householdId: home, name: "Nómina", kind: .income)
        let transfer = BudgetCategory(householdId: home, name: "Transferencia", kind: .transfer)
        let movements = [
            move(account, -6_000, on: day(2026, 9, 3), food),
            move(account, -3_000, on: day(2026, 10, 3), food),
            move(account, 500, on: day(2026, 10, 4), food, "Devolución"),
            move(account, -1_500, on: day(2026, 10, 9), fun),
            move(account, -1_000, on: day(2026, 10, 9)),
            move(account, 200_000, on: day(2026, 10, 28), salary),
            move(account, -50_000, on: day(2026, 10, 29), transfer),
            move(account, -9_999, on: day(2026, 8, 31), food),
        ]
        let range = day(2026, 9, 1)...day(2026, 10, 31)
        let report = SpendingReport(movements: movements, categories: [food, fun, salary, transfer], range: range)
        XCTAssertEqual(report.total, Money(minor: 11_000), "sin transferencias ni lo que queda fuera del periodo")
        XCTAssertEqual(report.byCategory.map(\.title), ["Supermercado", "Ocio", "Sin categoría"])
        XCTAssertEqual(report.byCategory.first?.amount, Money(minor: 8_500), "la devolución resta")
        XCTAssertEqual(report.byCategory.first?.count, 3)
        XCTAssertEqual(report.byMonth.map(\.amount.minor), [6_000, 5_000])
        XCTAssertEqual(report.averagePerMonth, Money(minor: 5_500))

        let onlyFun = SpendingReport(movements: movements, categories: [food, fun, salary, transfer], range: range,
                                     categoryIds: [fun.id])
        XCTAssertEqual(onlyFun.total, Money(minor: 1_500))
        let income = SpendingReport(movements: movements, categories: [food, fun, salary, transfer], range: range, kind: .income)
        XCTAssertEqual(income.total, Money(minor: 200_000))

        XCTAssertEqual(ReportPeriod.lastMonth.range(today: day(2026, 3, 15)), day(2026, 2, 1)...day(2026, 2, 28))
        XCTAssertEqual(ReportPeriod.thisYear.range(today: day(2026, 3, 15)).lowerBound, day(2026, 1, 1))
    }

    /// ORC-80: un traspaso importado del CSV, sin categoría, no sale en gastos ni ingresos, aunque se mire una sola cuenta.
    func testInformeSinTraspasoImportado() {
        let common = Account(householdId: home, name: "Cuenta común")
        let savings = Account(householdId: home, name: "Ahorro")
        var salida = move(common, -50_000, on: day(2026, 10, 9), nil, "Traspaso a ahorro")
        salida.importHash = "hash-salida"
        var entrada = move(savings, 50_000, on: day(2026, 10, 9), nil, "Traspaso desde cuenta común")
        entrada.importHash = "hash-entrada"
        let movements = [salida, entrada, move(common, -1_000, on: day(2026, 10, 10))]
        let range = day(2026, 10, 1)...day(2026, 10, 31)
        XCTAssertEqual(SpendingReport(movements: movements, categories: [], range: range).total, Money(minor: 1_000))
        XCTAssertEqual(SpendingReport(movements: movements, categories: [], range: range, kind: .income).total, .zero)
        XCTAssertEqual(SpendingReport(movements: movements, categories: [], range: range, accountIds: [common.id]).total,
                       Money(minor: 1_000), "la otra pata está en una cuenta que no se mira")
        XCTAssertEqual(SpendingReport(movements: movements, categories: [], range: range, kind: .income,
                                      accountIds: [savings.id]).total, .zero)
    }

    func testInformesConInicioDeMesDia25() {
        let account = Account(householdId: home, name: "Cuenta común")
        let movements = [
            move(account, -1_000, on: day(2026, 10, 24)),
            move(account, -2_000, on: day(2026, 10, 25)),
            move(account, -3_000, on: day(2026, 11, 10)),
            move(account, -4_000, on: day(2026, 9, 25)),
            move(account, -5_000, on: day(2026, 9, 24)),
            move(account, -8_000, on: day(2026, 11, 11))
        ]
        let today = day(2026, 11, 10)

        // El mes del hogar va del 25 al 24: "este mes" es del 25 de octubre al 10 de noviembre.
        let thisMonth = ReportPeriod.thisMonth.range(today: today, monthStartDay: 25)
        XCTAssertEqual(thisMonth, day(2026, 10, 25)...day(2026, 11, 10))
        let report = SpendingReport(movements: movements, categories: [], range: thisMonth, monthStartDay: 25)
        XCTAssertEqual(report.total, Money(minor: 5_000), "el 24 de octubre es del mes anterior; el 11 aún no ha llegado")
        XCTAssertEqual(report.byMonth.map(\.month), [MonthKey(year: 2026, month: 11)])

        // Frente al mes anterior, del 25 de septiembre al 11 de octubre (mismo día del periodo).
        XCTAssertEqual(ReportPeriod.thisMonth.previousRange(today: today, monthStartDay: 25), day(2026, 9, 25)...day(2026, 10, 11))

        // El mes pasado es el periodo completo, del 25 de septiembre al 24 de octubre.
        let lastMonth = ReportPeriod.lastMonth.range(today: today, monthStartDay: 25)
        XCTAssertEqual(lastMonth, day(2026, 9, 25)...day(2026, 10, 24))
        XCTAssertEqual(SpendingReport(movements: movements, categories: [], range: lastMonth, monthStartDay: 25).total,
                       Money(minor: 5_000))
        XCTAssertEqual(ReportPeriod.lastMonth.previousRange(today: today, monthStartDay: 25), day(2026, 8, 25)...day(2026, 9, 24))

        // Con inicio 1 no cambia nada.
        XCTAssertEqual(ReportPeriod.thisMonth.range(today: today), day(2026, 11, 1)...today)
    }

    func testParityWithAndroidSummaryAndReports() {
        let checking = Account(householdId: home, name: "Cuenta común", openingBalance: Money(minor: 100_000))
        let savings = Account(householdId: home, name: "Ahorro")
        let archivedOn = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 5))!
        let old = Account(householdId: home, name: "Antigua", archivedAt: archivedOn)
        let food = BudgetCategory(householdId: home, name: "Supermercado", kind: .expense, budgetGroup: .needs, icon: "cart")
        let fun = BudgetCategory(householdId: home, name: "Ocio", kind: .expense, budgetGroup: .wants)
        let transfer = BudgetCategory(householdId: home, name: "Transferencia", kind: .transfer)
        let categories = [food, fun, transfer]
        let movements = [
            move(checking, -10_000, on: day(2026, 10, 5), food),
            move(checking, -2_000, on: day(2026, 10, 6), fun),
            move(checking, -4_000, on: day(2026, 11, 2), food),
            move(checking, -5_000, on: day(2026, 11, 3), fun),
            move(checking, -30_000, on: day(2026, 11, 4), transfer),
            move(savings, 30_000, on: day(2026, 11, 4), transfer),
            move(old, -99_000, on: day(2026, 11, 4)),
            move(checking, -1_000, on: day(2026, 11, 20), food, "Después de hoy"),
        ]
        let today = day(2026, 11, 10)
        let open = movements.filter { $0.accountId != old.id }
        XCTAssertEqual(MonthSummary.spent(movements: open, categories: categories, today: today), Money(minor: 9_000),
                       "sin traspasos ni lo de después de hoy")
        XCTAssertEqual(MonthSummary.netWorthChange(accounts: [checking, savings, old], movements: movements, today: today),
                       Money(minor: -108_000), "el traspaso se anula; la cuenta archivada el 5 cuenta lo del 4")
        XCTAssertEqual(MonthSummary.netWorthChange(accounts: [checking, savings, old],
                                                   movements: [move(checking, -7_000, on: day(2026, 10, 26), food)],
                                                   today: today), Money(minor: 0), "inicio 1: octubre no cuenta")
        XCTAssertEqual(MonthSummary.netWorthChange(accounts: [checking, savings, old],
                                                   movements: [move(checking, -7_000, on: day(2026, 10, 26), food)],
                                                   today: today, monthStartDay: 25), Money(minor: -7_000),
                       "con inicio 25 el mes va del 25 de octubre")

        let rise = BiggestRise.find(movements: open, categories: categories, month: MonthKey(today))
        XCTAssertEqual(rise?.title, "Ocio")
        XCTAssertEqual(rise?.percent, 150)
        XCTAssertEqual(rise?.previous, MonthKey(year: 2026, month: 10))
        XCTAssertNil(BiggestRise.find(movements: [], categories: categories, month: MonthKey(today)))

        let through = MonthKey(today)
        XCTAssertEqual(NetWorthRange.oneMonth.months(firstMovement: nil, through: through), 2)
        XCTAssertEqual(NetWorthRange.oneYear.months(firstMovement: nil, through: through), 13)
        XCTAssertEqual(NetWorthRange.all.months(firstMovement: day(2025, 12, 31), through: through), 12)
        XCTAssertEqual(NetWorthRange.all.months(firstMovement: day(2026, 11, 1), through: through), 2)
        let history = NetWorth.history(accounts: [checking, savings], movements: movements, months: 2, through: through)
        XCTAssertEqual(NetWorthRange.change(history), Money(minor: -10_000))
    }

    func testFlexBudget() {
        let account = Account(householdId: home, name: "Cuenta común")
        let rent = BudgetCategory(householdId: home, name: "Vivienda", kind: .expense, budgetGroup: .needs)
        let food = BudgetCategory(householdId: home, name: "Supermercado", kind: .expense, budgetGroup: .needs)
        let fun = BudgetCategory(householdId: home, name: "Ocio", kind: .expense, budgetGroup: .wants)
        let saving = BudgetCategory(householdId: home, name: "Ahorro", kind: .expense, budgetGroup: .savings)
        let month = MonthKey(year: 2026, month: 11)
        let budget = Budget(householdId: home, month: month, expectedIncome: Money(minor: 200_000))
        let movements = [
            move(account, -80_000, on: day(2026, 11, 1), rent),
            move(account, -20_000, on: day(2026, 11, 3), food),
            move(account, -5_000, on: day(2026, 11, 5), fun),
            move(account, -2_000, on: day(2026, 11, 6)),
            move(account, -40_000, on: day(2026, 11, 7), saving),
        ]
        let report = BudgetReport(budget: budget, month: month, categories: [rent, food, fun, saving], movements: movements)
        let series = [
            RecurringSeries(householdId: home, name: "Alquiler", kind: .essential, amount: Money(minor: 80_000),
                            categoryId: rent.id, startsOn: day(2026, 1, 1)),
            RecurringSeries(householdId: home, name: "Música", amount: Money(minor: 1_000), startsOn: day(2026, 1, 5)),
            RecurringSeries(householdId: home, name: "Nómina", kind: .income, amount: Money(minor: 200_000), startsOn: day(2026, 1, 28)),
        ]
        let flex = FlexBudget(report: report, series: series, today: day(2026, 11, 21))
        XCTAssertEqual(flex.income, Money(minor: 200_000))
        XCTAssertEqual(flex.fixed, Money(minor: 81_000))
        XCTAssertEqual(flex.savings, Money(minor: 40_000), "el 20 % del 50/30/20")
        XCTAssertEqual(flex.flexible, Money(minor: 79_000))
        XCTAssertEqual(flex.fixedSpent, Money(minor: 80_000))
        XCTAssertEqual(flex.flexibleSpent, Money(minor: 27_000), "super, ocio y lo que no tiene categoría")
        XCTAssertEqual(flex.remaining, Money(minor: 52_000))
        XCTAssertEqual(flex.daysLeft, 10)
        XCTAssertEqual(flex.perDay, Money(minor: 5_200))
    }

    func testBudgetAlertAtExactLimitDoesNotSayPasado() {
        let account = Account(householdId: home, name: "Cuenta común")
        let fun = BudgetCategory(householdId: home, name: "Ocio", kind: .expense, budgetGroup: .wants)
        let month = MonthKey(year: 2026, month: 11)
        let budget = Budget(householdId: home, month: month, expectedIncome: Money(minor: 100_000),
                            limits: [fun.id: Money(minor: 10_000)])
        let movements = [move(account, -10_000, on: day(2026, 11, 5), fun)]
        let report = BudgetReport(budget: budget, month: month, categories: [fun], movements: movements)
        let alerts = BudgetAlertPlanner.alerts(for: report)
        XCTAssertEqual(alerts.map(\.title), ["Has llegado al límite en Ocio"])
    }

    func testBudgetAlerts() {
        let account = Account(householdId: home, name: "Cuenta común")
        let food = BudgetCategory(householdId: home, name: "Supermercado", kind: .expense, budgetGroup: .needs)
        let fun = BudgetCategory(householdId: home, name: "Ocio", kind: .expense, budgetGroup: .wants)
        let month = MonthKey(year: 2026, month: 11)
        let budget = Budget(householdId: home, month: month, expectedIncome: Money(minor: 100_000),
                            limits: [food.id: Money(minor: 30_000), fun.id: Money(minor: 10_000)])
        let movements = [
            move(account, -25_000, on: day(2026, 11, 3), food),
            move(account, -12_000, on: day(2026, 11, 5), fun),
        ]
        let report = BudgetReport(budget: budget, month: month, categories: [food, fun], movements: movements)
        let alerts = BudgetAlertPlanner.alerts(for: report)
        XCTAssertEqual(alerts.count, 2, "super al 83 %, ocio pasado; los grupos aún no")
        XCTAssertTrue(alerts.contains { $0.id == "stm.budget.2026-11.\(food.id.uuidString).80" })
        XCTAssertTrue(alerts.contains { $0.id == "stm.budget.2026-11.\(fun.id.uuidString).100" && $0.title == "Te has pasado en Ocio" })
    }
}
