import XCTest
@testable import STMCore

/// Casos de dinero sin cubrir hasta ahora: otra moneda, mes que no empieza el día 1,
/// revolving con aplazados a la vez y vender más de lo que se tiene. Datos inventados.
final class MoneyEdgeCaseTests: XCTestCase {
    let home = UUID()
    let account = UUID()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }
    private func dec(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    // MARK: Otra moneda

    func testArithmeticKeepsANonEuroCurrency() {
        let a = Money(minor: 1_050, currency: "USD")
        let b = Money(minor: 250, currency: "USD")
        XCTAssertEqual(a + b, Money(minor: 1_300, currency: "USD"))
        XCTAssertEqual(a - b, Money(minor: 800, currency: "USD"))
        XCTAssertEqual(-a, Money(minor: -1_050, currency: "USD"))
        XCTAssertEqual(Money(minor: 0, currency: "USD") + a, a)
        XCTAssertEqual(Money(minor: 1_000, currency: "USD").split(percentages: [50, 30, 20]),
                       [Money(minor: 500, currency: "USD"), Money(minor: 300, currency: "USD"), Money(minor: 200, currency: "USD")])
        XCTAssertEqual(Money(parsing: "1.234,56", currency: "GBP"), Money(minor: 123_456, currency: "GBP"))
        XCTAssertEqual(Money(decimal: dec("12.345"), currency: "USD"), Money(minor: 1_235, currency: "USD"))
        XCTAssertNotEqual(Money(minor: 100, currency: "USD"), Money(minor: 100), "mismo importe, otra moneda")
    }

    func testPositionOfAHoldingInDollarsStaysInDollars() {
        let holding = Holding(householdId: home, name: "ETF en dólares", kind: .etf, currency: "USD", price: dec("12"))
        let trades = [
            InvestmentTrade(householdId: home, holdingId: holding.id, tradedOn: day(2026, 1, 10), side: .buy,
                            quantity: dec("10"), price: dec("10"), fee: Money(minor: 100)),
            InvestmentTrade(householdId: home, holdingId: holding.id, tradedOn: day(2026, 2, 10), side: .sell,
                            quantity: dec("4"), price: dec("11"), fee: Money(minor: 40)),
        ]
        let position = Position(holding: holding, trades: trades)
        XCTAssertEqual(position.quantity, 6)
        XCTAssertEqual(position.invested, Money(minor: 10_100, currency: "USD"))
        // 101 $ de coste; salen 4/10 → 40,40 $; quedan 60,60 $.
        XCTAssertEqual(position.cost, Money(minor: 6_060, currency: "USD"))
        // 44 $ − 0,40 $ de comisión − 40,40 $ de coste = 3,20 $.
        XCTAssertEqual(position.realized, Money(minor: 320, currency: "USD"))
        XCTAssertEqual(position.value, Money(minor: 7_200, currency: "USD"))
        XCTAssertEqual(position.gain, Money(minor: 1_140, currency: "USD"))
    }

    // MARK: Mes que empieza otro día

    func testBudgetReportWithMonthStartingOnThe25th() {
        let categories = BudgetCategory.defaults(for: home)
        func named(_ name: String) -> BudgetCategory { categories.first { $0.name == name }! }
        func movement(_ cents: Int, _ name: String, on date: CalendarDay) -> Movement {
            Movement(householdId: home, accountId: account, categoryId: named(name).id, bookedOn: date,
                     amount: Money(minor: cents), description: "Prueba")
        }
        let movements = [
            movement(-11_111, "Supermercado", on: day(2026, 10, 24)),  // del periodo anterior
            movement(200_000, "Nómina", on: day(2026, 10, 25)),        // primer día
            movement(-30_000, "Supermercado", on: day(2026, 10, 31)),
            movement(-20_000, "Restaurantes", on: day(2026, 11, 1)),
            movement(-5_000, "Supermercado", on: day(2026, 11, 24)),   // último día
            movement(-22_222, "Supermercado", on: day(2026, 11, 25)),  // del periodo siguiente
        ]
        let november = MonthKey(year: 2026, month: 11)
        let report = BudgetReport(budget: nil, month: november, startDay: 25, categories: categories, movements: movements)

        XCTAssertEqual(report.month, november)
        XCTAssertEqual(report.period, day(2026, 10, 25)...day(2026, 11, 24))
        XCTAssertEqual(report.income, Money(minor: 200_000))
        XCTAssertEqual(report.lines.first { $0.category.name == "Supermercado" }?.spent, Money(minor: 35_000))
        XCTAssertEqual(report.lines.first { $0.category.name == "Restaurantes" }?.spent, Money(minor: 20_000))
        XCTAssertEqual(report.totalSpent, Money(minor: 55_000))
        XCTAssertEqual(report.remaining, Money(minor: 145_000))
        // Sin presupuesto: 50/30/20 sobre los ingresos reales.
        XCTAssertEqual(report.groups.map(\.allocated.minor), [100_000, 60_000, 40_000])
        XCTAssertEqual(report.groups.map(\.spent.minor), [35_000, 20_000, 0])

        // El mismo mes natural (día 1) cuenta otros movimientos.
        let natural = BudgetReport(budget: nil, month: november, categories: categories, movements: movements)
        XCTAssertEqual(natural.income, .zero)
        XCTAssertEqual(natural.totalSpent, Money(minor: 47_222))
    }

    // MARK: Revolving con aplazados

    func testRevolvingDebtAndInstallmentInTheSameSummary() {
        let card = UUID(), transfer = UUID()
        func move(_ amount: Int, on date: CalendarDay) -> Movement {
            Movement(householdId: home, accountId: card, bookedOn: date, amount: Money(minor: amount), description: "Compra de prueba")
        }
        let old = move(-100_000, on: day(2026, 9, 5))      // revolving: ya en extractos cerrados
        let recent = move(-5_000, on: day(2026, 11, 2))    // extracto abierto
        let deferred = move(-60_000, on: day(2026, 11, 3)) // aplazada a 6 meses al 14 %
        let movements = [old, recent, deferred]
        let terms = CreditCardTerms(accountId: card, householdId: home, creditLimit: Money(minor: 300_000), paymentMode: .minimum)
        let plan = CardInstallment(householdId: home, accountId: card, movementId: deferred.id, months: 6, rate: 14)
        let s = CreditCardCalculator.summary(terms: terms, balance: Money(minor: -165_000), movements: movements,
                                             installments: [plan], transferCategories: [transfer], today: day(2026, 11, 4))

        XCTAssertEqual(s.used, Money(minor: 165_000))
        // La compra aplazada no entra en el revolving ni en lo gastado del ciclo.
        XCTAssertEqual(s.revolvingBalance, Money(minor: 100_000))
        XCTAssertEqual(s.spentThisCycle, Money(minor: 5_000))
        // Extracto del 1 de noviembre: 1.000 € al 20 % → 16,67 € + 30 €.
        XCTAssertEqual(s.payments[0].amount, Money(minor: 4_667))
        XCTAssertEqual(s.payments[0].installments, .zero)
        // 1 de diciembre: revolving de 970 € + 50 € = 1.020 € → 17 € + 30,60 €, más la primera cuota (7 € de interés).
        XCTAssertEqual(s.payments[1].purchases, Money(minor: 4_760))
        XCTAssertEqual(s.payments[1].installments, Money(minor: 10_412))
        XCTAssertEqual(s.payments[1].amount, Money(minor: 15_172))
        XCTAssertEqual(s.payments[1].interest, Money(minor: 2_400))
        // 1 de enero: quedan 989,40 € → 16,49 € + 29,68 €; segunda cuota con 5,87 € de interés.
        XCTAssertEqual(s.payments[2].purchases, Money(minor: 4_617))
        XCTAssertEqual(s.payments[2].amount, Money(minor: 15_029))
        XCTAssertEqual(s.payments[2].interest, Money(minor: 2_236))
    }

    // MARK: Vender de más

    func testSellingMoreThanHeldOnlySellsWhatIsHeld() {
        let holding = Holding(householdId: home, name: "Fondo de prueba", price: dec("12"))
        let buy = InvestmentTrade(householdId: home, holdingId: holding.id, tradedOn: day(2026, 1, 10), side: .buy,
                                  quantity: dec("10"), price: dec("10"), fee: Money(minor: 100))
        let oversell = InvestmentTrade(householdId: home, holdingId: holding.id, tradedOn: day(2026, 2, 10), side: .sell,
                                       quantity: dec("15"), price: dec("12"), fee: Money(minor: 50))

        // Al apuntarla se rechaza.
        XCTAssertEqual(oversell.issue(given: [buy]), .notEnoughShares)

        // Si llega igualmente (datos antiguos o de otro dispositivo), la posición no queda en negativo.
        let position = Position(holding: holding, trades: [buy, oversell])
        XCTAssertEqual(position.quantity, 0)
        XCTAssertEqual(position.cost, .zero)
        XCTAssertEqual(position.value, .zero)
        // Sólo se venden las 10 que había: 120 € − 0,50 € − 101 € de coste = 18,50 €.
        XCTAssertEqual(position.realized, Money(minor: 1_850))
        XCTAssertEqual(position.invested, Money(minor: 10_100))
        XCTAssertEqual(Position.quantity(of: holding.id, in: [buy, oversell], through: nil), 0)
        XCTAssertTrue(Portfolio(holdings: [holding], trades: [buy, oversell]).positions.isEmpty)

        // Vender sin haber comprado nada no cambia nada.
        let empty = Position(holding: holding, trades: [oversell])
        XCTAssertEqual(empty.quantity, 0)
        XCTAssertEqual(empty.realized, .zero)
    }
}
