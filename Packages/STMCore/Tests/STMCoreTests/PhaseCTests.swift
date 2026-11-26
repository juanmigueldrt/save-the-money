import XCTest
@testable import STMCore

/// Fase C: periodos según el día de cobro, «puedes gastar hoy», arrastre, presupuesto
/// inteligente, avisos configurables y presupuestos extra.
final class PhaseCTests: XCTestCase {
    private let home = UUID()
    private let account = UUID()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }

    private func spend(_ minor: Int, on date: CalendarDay, category: UUID? = nil, excluded: Bool = false,
                       accountId: UUID? = nil) -> Movement {
        Movement(householdId: home, accountId: accountId ?? account, categoryId: category, bookedOn: date,
                 amount: Money(minor: -minor), description: "GASTO", excluded: excluded)
    }

    // MARK: Periodos

    func testMonthlyPeriodsFromPayday() {
        let schedule = PaySchedule(frequency: .monthly, day1: 25)
        let period = schedule.period(containing: day(2026, 11, 15))
        XCTAssertEqual(period.start, day(2026, 10, 25))
        XCTAssertEqual(period.end, day(2026, 11, 24))
        XCTAssertEqual(period.month, MonthKey(year: 2026, month: 11))
        XCTAssertEqual(schedule.period(after: period).start, day(2026, 11, 25))
        XCTAssertEqual(schedule.period(before: period).end, day(2026, 10, 24))
        // Día 31: en meses cortos cobra el último día.
        let end = PaySchedule(frequency: .monthly, day1: 31)
        XCTAssertEqual(end.period(containing: day(2027, 2, 10)).start, day(2027, 1, 31))
        XCTAssertEqual(end.period(containing: day(2027, 2, 10)).end, day(2027, 2, 27))
        XCTAssertEqual(end.nextPayday(after: day(2027, 2, 10)), day(2027, 2, 28))
        // Día 1 = mes natural, con su nombre.
        let natural = PaySchedule.monthly(startDay: 1).period(containing: day(2026, 11, 15))
        XCTAssertEqual(natural, BudgetPeriod(month: MonthKey(year: 2026, month: 11)))
        XCTAssertEqual(natural.title, "Noviembre de 2026")
        XCTAssertEqual(period.title, "25 oct – 24 nov")
    }

    func testTwiceMonthlyWeeklyBiweeklyAndYearly() {
        let twice = PaySchedule(frequency: .twiceMonthly, day1: 1, day2: 15)
        XCTAssertEqual(twice.period(containing: day(2026, 11, 20)), BudgetPeriod(start: day(2026, 11, 15), end: day(2026, 11, 30)))
        XCTAssertEqual(twice.period(containing: day(2026, 11, 3)), BudgetPeriod(start: day(2026, 11, 1), end: day(2026, 11, 14)))

        // 2026-11-06 es viernes.
        let weekly = PaySchedule(frequency: .weekly, anchor: day(2026, 11, 6))
        XCTAssertEqual(day(2026, 11, 6).weekdayName, "viernes")
        XCTAssertEqual(weekly.period(containing: day(2026, 11, 15)), BudgetPeriod(start: day(2026, 11, 13), end: day(2026, 11, 19)))
        XCTAssertEqual(weekly.period(containing: day(2026, 10, 1)).start, day(2026, 9, 25), "también hacia atrás")

        let biweekly = PaySchedule(frequency: .biweekly, anchor: day(2026, 11, 6))
        XCTAssertEqual(biweekly.period(containing: day(2026, 11, 15)), BudgetPeriod(start: day(2026, 11, 6), end: day(2026, 11, 19)))
        XCTAssertEqual(biweekly.nextPayday(after: day(2026, 11, 15)), day(2026, 11, 20))

        let yearly = PaySchedule(frequency: .yearly, anchor: day(2025, 3, 1))
        XCTAssertEqual(yearly.period(containing: day(2026, 11, 15)), BudgetPeriod(start: day(2026, 3, 1), end: day(2027, 2, 28)))
    }

    func testScheduleValidation() {
        XCTAssertNil(PaySchedule(frequency: .monthly, day1: 25).issue)
        XCTAssertNotNil(PaySchedule(frequency: .monthly, day1: 0).issue)
        XCTAssertNotNil(PaySchedule(frequency: .twiceMonthly, day1: 15, day2: 1).issue)
        XCTAssertNotNil(PaySchedule(frequency: .weekly).issue)
        XCTAssertEqual(PaySchedule(frequency: .twiceMonthly, day1: 1, day2: 15).summary, "Los días 1 y 15")
    }

    // MARK: Puedes gastar hoy, proyección y queda por presupuestar

    func testPeriodInsights() {
        let food = BudgetCategory(householdId: home, name: "Comida", kind: .expense, budgetGroup: .needs)
        let fun = BudgetCategory(householdId: home, name: "Ocio", kind: .expense, budgetGroup: .wants)
        let period = BudgetPeriod(start: day(2026, 11, 1), end: day(2026, 11, 30))
        let budget = Budget(householdId: home, period: period, expectedIncome: Money(minor: 200_000),
                            limits: [food.id: Money(minor: 40_000), fun.id: Money(minor: 20_000)])
        let movements = [spend(30_000, on: day(2026, 11, 3), category: food.id),
                         spend(10_000, on: day(2026, 11, 9), category: fun.id),
                         spend(50_000, on: day(2026, 11, 9), category: fun.id, excluded: true)]
        let report = BudgetReport(budget: budget, period: period, categories: [food, fun], movements: movements)
        let insights = PeriodInsights(report: report, budget: budget, today: day(2026, 11, 10))
        // 50 % + 30 % de 2.000 € = 1.600 € para gastar; llevas 400 €.
        XCTAssertEqual(insights.spendable.minor, 160_000)
        XCTAssertEqual(insights.left.minor, 120_000)
        XCTAssertEqual(insights.perDay.minor, 120_000 / 21, "del 10 al 30 son 21 días")
        XCTAssertEqual(insights.daysToPayday, 21)
        XCTAssertEqual(insights.projectedSpent.minor, 120_000, "400 € en 10 días son 1.200 € en 30")
        XCTAssertEqual(insights.unbudgeted.minor, 140_000)
        // Pasado el periodo ya no queda nada por día.
        XCTAssertEqual(PeriodInsights(report: report, budget: budget, today: day(2026, 12, 2)).perDay, .zero)
    }

    // MARK: Arrastre

    func testCarryOver() {
        let food = BudgetCategory(householdId: home, name: "Comida", kind: .expense, budgetGroup: .needs)
        let fun = BudgetCategory(householdId: home, name: "Ocio", kind: .expense, budgetGroup: .wants)
        let october = BudgetPeriod(month: MonthKey(year: 2026, month: 10))
        let november = BudgetPeriod(month: MonthKey(year: 2026, month: 11))
        var budget = Budget(householdId: home, period: october,
                            limits: [food.id: Money(minor: 40_000), fun.id: Money(minor: 10_000)], carryOver: true)
        let movements = [spend(30_000, on: day(2026, 10, 5), category: food.id),
                         spend(15_000, on: day(2026, 10, 6), category: fun.id),
                         spend(5_000, on: day(2026, 11, 2), category: food.id)]
        let previous = BudgetReport(budget: budget, period: october, categories: [food, fun], movements: movements)
        let carried = BudgetCarryOver.amounts(previous: previous)
        XCTAssertEqual(carried[food.id]?.minor, 10_000, "sobraron 100 €")
        XCTAssertEqual(carried[fun.id]?.minor, -5_000, "te pasaste 50 €")

        budget = budget.copied(to: november)
        let report = BudgetReport(budget: budget, period: november, categories: [food, fun], movements: movements, carried: carried)
        let foodLine = report.lines.first { $0.category.id == food.id }!
        XCTAssertEqual(foodLine.available?.minor, 50_000)
        XCTAssertEqual(report.lines.first { $0.category.id == fun.id }?.available?.minor, 5_000)
        // Sin arrastre activado no se suma nada.
        budget.carryOver = false
        let plain = BudgetReport(budget: budget, period: november, categories: [food, fun], movements: movements, carried: carried)
        XCTAssertEqual(plain.lines.first { $0.category.id == food.id }?.available?.minor, 40_000)
        XCTAssertTrue(plain.carried.isEmpty)
    }

    // MARK: Presupuesto inteligente y vaciar plan

    func testSmartBudgetAndClear() {
        let food = BudgetCategory(householdId: home, name: "Comida", kind: .expense, budgetGroup: .needs)
        let schedule = PaySchedule.monthly(startDay: 1)
        let november = schedule.period(containing: day(2026, 11, 10))
        let previous = (1...3).reduce(into: [BudgetPeriod]()) { list, _ in
            list.append(schedule.period(before: list.last ?? november))
        }
        XCTAssertEqual(previous.map(\.month.month), [10, 9, 8])
        let movements = [spend(30_000, on: day(2026, 10, 5), category: food.id),
                         spend(20_000, on: day(2026, 9, 5), category: food.id),
                         spend(10_050, on: day(2026, 8, 5), category: food.id),
                         spend(99_000, on: day(2026, 7, 5), category: food.id),
                         spend(99_000, on: day(2026, 10, 7), category: food.id, excluded: true)]
        let limits = SmartBudget.suggestedLimits(movements: movements, categories: [food], periods: previous)
        XCTAssertEqual(limits[food.id]?.minor, 20_100, "media 200,17 € redondeada al euro de arriba")

        let budget = Budget(householdId: home, period: november, limits: limits)
        XCTAssertTrue(budget.cleared().limits.isEmpty)
        XCTAssertNotNil(Budget(householdId: home, period: november, warnPercent: 40).issue)
    }

    // MARK: Aviso configurable

    func testConfigurableWarning() {
        let food = BudgetCategory(householdId: home, name: "Comida", kind: .expense, budgetGroup: .needs)
        let period = BudgetPeriod(start: day(2026, 11, 15), end: day(2026, 11, 30))
        let movements = [spend(7_000, on: day(2026, 11, 16), category: food.id)]
        var budget = Budget(householdId: home, period: period, limits: [food.id: Money(minor: 10_000)], warnPercent: 90)
        var report = BudgetReport(budget: budget, period: period, categories: [food], movements: movements)
        XCTAssertTrue(BudgetAlertPlanner.alerts(for: report).filter { $0.id.contains(food.id.uuidString) }.isEmpty,
                      "al 70 % no avisa si el aviso está al 90 %")
        budget.warnPercent = 60
        report = BudgetReport(budget: budget, period: period, categories: [food], movements: movements)
        let alert = BudgetAlertPlanner.alerts(for: report).first { $0.id.contains(food.id.uuidString) }
        XCTAssertEqual(alert?.id, "\(BudgetAlertPlanner.prefix)2026-11-15.\(food.id.uuidString).60")
    }

    // MARK: Presupuestos extra

    func testExtraBudgetSpent() throws {
        let travel = BudgetCategory(householdId: home, name: "Viajes", kind: .expense, budgetGroup: .wants)
        let food = BudgetCategory(householdId: home, name: "Comida", kind: .expense, budgetGroup: .needs)
        let card = UUID()
        let extra = ExtraBudget(householdId: home, name: " Vacaciones ", limit: Money(minor: 80_000),
                                startsOn: day(2026, 12, 1), endsOn: day(2026, 12, 15), categoryIds: [travel.id, food.id],
                                accountIds: [card])
        let movements = [spend(30_000, on: day(2026, 12, 2), category: travel.id, accountId: card),
                         spend(5_000, on: day(2026, 12, 3), category: food.id, accountId: card),
                         spend(5_000, on: day(2026, 12, 3), category: food.id),
                         spend(9_000, on: day(2026, 12, 20), category: travel.id, accountId: card),
                         spend(9_000, on: day(2026, 12, 4), category: travel.id, excluded: true, accountId: card)]
        XCTAssertEqual(extra.spent(movements: movements, categories: [travel, food]).minor, 35_000)
        XCTAssertNil(extra.issue)
        XCTAssertNotNil(ExtraBudget(householdId: home, name: "X", limit: .zero).issue)
        let data = try JSONEncoder().encode(extra)
        let decoded = try JSONDecoder().decode(ExtraBudget.self, from: data)
        XCTAssertEqual(decoded, extra, "vuelve igual; el nombre se limpia al guardarlo en el servidor, no al codificarlo")
        XCTAssertEqual(decoded.endsOn, day(2026, 12, 15))
    }

    func testInMemoryScheduleAndExtras() async throws {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        let house = try await backend.createHousehold(name: "Casa")
        let empty = try await backend.paySchedule()
        XCTAssertNil(empty)
        _ = try await backend.savePaySchedule(PaySchedule(frequency: .twiceMonthly, day1: 1, day2: 15))
        let schedule = try await backend.paySchedule()
        XCTAssertEqual(schedule?.frequency, .twiceMonthly)

        let period = BudgetPeriod(start: day(2026, 11, 15), end: day(2026, 11, 30))
        _ = try await backend.saveBudget(Budget(householdId: house.id, period: period, carryOver: true))
        let saved = try await backend.budget(startingOn: day(2026, 11, 15), in: house.id)
        XCTAssertEqual(saved?.carryOver, true)
        let before = try await backend.latestBudget(before: day(2026, 12, 1), in: house.id)
        XCTAssertEqual(before?.period, period)

        _ = try await backend.saveExtraBudget(ExtraBudget(householdId: house.id, name: "A", limit: Money(minor: 100), isFavorite: true))
        let b = try await backend.saveExtraBudget(ExtraBudget(householdId: house.id, name: "B", limit: Money(minor: 100), isFavorite: true))
        let list = try await backend.extraBudgets(in: house.id)
        XCTAssertEqual(list.filter(\.isFavorite).map(\.id), [b.id])
        try await backend.deleteExtraBudget(b.id)
        let remaining = try await backend.extraBudgets(in: house.id)
        XCTAssertEqual(remaining.map(\.name), ["A"])
    }
}
