import XCTest
@testable import STMCore

final class BudgetTests: XCTestCase {
    let home = UUID()
    let account = UUID()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }

    private func movement(_ cents: Int, _ category: BudgetCategory?, on date: CalendarDay) -> Movement {
        Movement(householdId: home, accountId: account, categoryId: category?.id, bookedOn: date,
                 amount: Money(minor: cents), description: "Prueba")
    }

    func testMonthPeriodWithCustomStartDay() {
        let november = MonthKey(year: 2026, month: 11)
        XCTAssertEqual(november.period(), day(2026, 11, 1)...day(2026, 11, 30))
        XCTAssertEqual(november.period(startDay: 25), day(2026, 10, 25)...day(2026, 11, 24))
        XCTAssertEqual(MonthKey(year: 2027, month: 1).period(startDay: 25).lowerBound, day(2026, 12, 25))
        XCTAssertEqual(MonthKey.containing(day(2026, 10, 26), startDay: 25), november)
        XCTAssertEqual(MonthKey.containing(day(2026, 10, 24), startDay: 25), MonthKey(year: 2026, month: 10))
        XCTAssertEqual(MonthKey(year: 2026, month: 12).adding(months: 1), MonthKey(year: 2027, month: 1))
        XCTAssertEqual(november.title, "Noviembre de 2026")
    }

    func testReportGroupsLimitsAndTransfers() {
        let categories = BudgetCategory.defaults(for: home)
        func named(_ name: String) -> BudgetCategory { categories.first { $0.name == name }! }
        let movements = [
            movement(200_000, named("Nómina"), on: day(2026, 11, 1)),
            movement(-60_000, named("Vivienda"), on: day(2026, 11, 2)),
            movement(-45_000, named("Supermercado"), on: day(2026, 11, 5)),
            movement(2_000, named("Supermercado"), on: day(2026, 11, 6)), // devolución
            movement(-30_000, named("Restaurantes"), on: day(2026, 11, 8)),
            movement(-40_000, named("Ahorro"), on: day(2026, 11, 9)),
            movement(-50_000, named("Transferencia entre cuentas"), on: day(2026, 11, 9)),
            movement(-1_500, nil, on: day(2026, 11, 10)),
            movement(-99_999, named("Vivienda"), on: day(2026, 10, 31)), // otro mes
        ]
        let budget = Budget(householdId: home, month: MonthKey(year: 2026, month: 11),
                            expectedIncome: Money(minor: 200_000),
                            limits: [named("Supermercado").id: Money(minor: 40_000)])
        let report = BudgetReport(budget: budget, month: MonthKey(year: 2026, month: 11),
                                  categories: categories, movements: movements)

        XCTAssertEqual(report.income.minor, 200_000)
        XCTAssertEqual(report.groups.map(\.allocated.minor), [100_000, 60_000, 40_000])
        XCTAssertEqual(report.groups.map(\.spent.minor), [103_000, 30_000, 40_000], "la transferencia no cuenta")
        XCTAssertTrue(report.groups[0].isOver)
        XCTAssertEqual(report.uncategorized.minor, 1_500)
        XCTAssertEqual(report.totalSpent.minor, 174_500)
        XCTAssertEqual(report.remaining.minor, 25_500)

        let supermarket = report.lines.first { $0.category.name == "Supermercado" }
        XCTAssertEqual(supermarket?.spent.minor, 43_000)
        XCTAssertEqual(supermarket?.isOver, true)
        XCTAssertEqual(report.lines.first?.category.budgetGroup, .needs, "primero necesidades")
        XCTAssertEqual(report.incomeSources.map(\.title), ["Nómina"])
    }

    func testWithoutBudgetUsesRealIncome() {
        let categories = BudgetCategory.defaults(for: home)
        let salary = categories.first { $0.name == "Nómina" }
        let report = BudgetReport(budget: nil, month: MonthKey(year: 2026, month: 11), categories: categories,
                                  movements: [movement(100_000, salary, on: day(2026, 11, 3))])
        XCTAssertEqual(report.base.minor, 100_000)
        XCTAssertEqual(report.groups.map(\.allocated.minor), [50_000, 30_000, 20_000])
        XCTAssertTrue(report.lines.isEmpty)
    }

    func testCashFlowBalancesAndLaysOut() throws {
        let categories = BudgetCategory.defaults(for: home)
        func named(_ name: String) -> BudgetCategory { categories.first { $0.name == name }! }
        let movements = [
            movement(150_000, named("Nómina"), on: day(2026, 11, 1)),
            movement(50_000, nil, on: day(2026, 11, 2)),
            movement(-80_000, named("Vivienda"), on: day(2026, 11, 3)),
            movement(-20_000, named("Ocio"), on: day(2026, 11, 4)),
        ]
        let report = BudgetReport(budget: nil, month: MonthKey(year: 2026, month: 11), categories: categories, movements: movements)
        let flow = CashFlow(report: report)

        XCTAssertEqual(flow.nodes.filter { $0.column == 0 }.map(\.title), ["Nómina", "Sin categoría"])
        XCTAssertEqual(flow.nodes.filter { $0.column == 1 }.map(\.title), ["Necesidades", "Deseos", "Sin gastar"])
        XCTAssertEqual(flow.nodes.first { $0.id == "sin-gastar" }?.value, 100_000)
        // Lo que sale de cada fuente es lo que entra en la columna del medio.
        let out = flow.links.filter { $0.from.hasPrefix("ingreso") }.reduce(0) { $0 + $1.value }
        XCTAssertEqual(out, 200_000, accuracy: 0.001)

        let layout = SankeyLayout(flow: flow, width: 300, height: 200)
        let salary = try XCTUnwrap(layout.nodes["ingreso:0"])
        XCTAssertEqual(salary.x, 0)
        XCTAssertLessThanOrEqual(layout.nodes.values.map { $0.y + $0.height }.max() ?? 0, 200.001)
        let needs = try XCTUnwrap(layout.nodes["grupo:needs"])
        let into = layout.bands.filter { $0.to == "grupo:needs" }.reduce(0) { $0 + $1.thickness }
        XCTAssertEqual(into, needs.height, accuracy: 0.001, "las bandas llenan el nodo")
    }

    func testOverspendingAddsFromBalance() {
        let categories = BudgetCategory.defaults(for: home)
        let rent = categories.first { $0.name == "Vivienda" }
        let report = BudgetReport(budget: nil, month: MonthKey(year: 2026, month: 11), categories: categories,
                                  movements: [movement(-50_000, rent, on: day(2026, 11, 1))])
        let flow = CashFlow(report: report)
        XCTAssertEqual(flow.nodes.first { $0.column == 0 }?.title, "Del saldo")
        XCTAssertNil(flow.nodes.first { $0.id == "sin-gastar" })
    }

    func testBudgetServiceInMemory() async throws {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        let home = try await backend.createHousehold(name: "Casa")
        let october = MonthKey(year: 2026, month: 10)
        let november = MonthKey(year: 2026, month: 11)
        let none = try await backend.budget(for: november, in: home.id)
        XCTAssertNil(none)
        _ = try await backend.saveBudget(Budget(householdId: home.id, month: october, expectedIncome: Money(minor: 1_000)))
        let previous = try await backend.latestBudget(before: november, in: home.id)
        XCTAssertEqual(previous?.month, october)
        _ = try await backend.saveBudget(Budget(householdId: home.id, month: october, expectedIncome: Money(minor: 2_000)))
        let saved = try await backend.budget(for: october, in: home.id)
        XCTAssertEqual(saved?.expectedIncome.minor, 2_000, "guardar el mismo mes lo reemplaza")
    }
}
