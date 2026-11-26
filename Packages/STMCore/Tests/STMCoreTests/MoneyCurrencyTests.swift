import XCTest
@testable import STMCore

/// ORC-71: importes de monedas distintas no se suman sin convertir, y mezclarlos no cierra la app.
/// Los casos compartidos con Android están en `testdata/vectors/money_currencies.json`.
final class MoneyCurrencyTests: XCTestCase {
    private let euros = Money(minor: 1_000)
    private let dollars = Money(minor: 500, currency: "USD")
    private let home = UUID()

    private func holding(_ name: String, currency: String) -> Holding {
        Holding(householdId: home, name: name, kind: .fund, currency: currency, price: 20,
                priceOn: CalendarDay(year: 2026, month: 11, day: 1))
    }

    private func buy(_ holding: Holding, quantity: Decimal, price: Decimal) -> InvestmentTrade {
        InvestmentTrade(householdId: home, holdingId: holding.id, tradedOn: CalendarDay(year: 2026, month: 1, day: 1)!,
                        side: .buy, quantity: quantity, price: price)
    }

    // Antes de ORC-71 estas tres operaciones cerraban la app con un `precondition`.
    func testSumarORestarMonedasDistintasNoDaUnImporte() {
        XCTAssertTrue((euros + dollars).isMixed)
        XCTAssertTrue((euros - dollars).isMixed)
        XCTAssertTrue((dollars - euros).isMixed)
        XCTAssertEqual((euros + dollars).minor, 0, "no queda ninguna cifra que se pueda enseñar por error")
    }

    func testLaMezclaSeContagia() {
        let mixed = euros + dollars
        XCTAssertTrue((mixed + euros).isMixed)
        XCTAssertTrue((mixed - dollars).isMixed)
        XCTAssertTrue((euros + mixed).isMixed)
        XCTAssertTrue((Money.zero + mixed).isMixed)
        XCTAssertTrue((mixed + .zero).isMixed)
        XCTAssertTrue((-mixed).isMixed)
    }

    func testLaMismaMonedaSeSumaComoSiempre() {
        XCTAssertEqual(dollars + dollars, Money(minor: 1_000, currency: "USD"))
        XCTAssertEqual(dollars - Money(minor: 700, currency: "USD"), Money(minor: -200, currency: "USD"))
        XCTAssertFalse((dollars - dollars).isMixed)
    }

    func testUnCeroNoMezcla() {
        XCTAssertEqual(Money.zero + dollars, dollars)
        XCTAssertEqual(dollars + .zero, dollars)
        XCTAssertEqual(dollars - .zero, dollars)
        XCTAssertEqual(Money.zero - dollars, Money(minor: -500, currency: "USD"))
        XCTAssertEqual([dollars, dollars].reduce(Money.zero, +), Money(minor: 1_000, currency: "USD"))
    }

    func testEnPantallaSaleVariasMonedasYNoUnaCifra() {
        let mixed = euros + dollars
        XCTAssertEqual(mixed.formatted(options: .standard), "Varias monedas")
        XCTAssertEqual(mixed.formatted(options: MoneyDisplayOptions(hidesAmounts: true)), "Varias monedas")
        XCTAssertEqual(mixed.signedText(options: .standard), "Varias monedas")
    }

    func testConConversionExplicitaSiSeSuman() {
        // 5,00 $ a 0,92 € por dólar son 4,60 €.
        let converted = dollars.converted(to: "EUR", rate: Decimal(string: "0.92")!)
        XCTAssertEqual(converted, Money(minor: 460))
        XCTAssertEqual(euros + converted, Money(minor: 1_460))
    }

    func testCompararMonedasDistintasNoCierraLaApp() {
        XCTAssertTrue(euros < dollars, "se ordena por moneda: EUR antes que USD")
        XCTAssertFalse(dollars < euros)
        XCTAssertEqual([dollars, euros, Money(minor: 5)].sorted(), [Money(minor: 5), euros, dollars])
        XCTAssertEqual(max(Money(minor: 5), euros), euros)
    }

    // El caso del ticket: un hogar cuyo único activo está en dólares cerraba la app.
    func testCarteraSoloEnDolares() {
        let fund = holding("Fondo en dólares", currency: "USD")
        let portfolio = Portfolio(holdings: [fund], trades: [buy(fund, quantity: 10, price: 15)])
        XCTAssertEqual(portfolio.value, Money(minor: 20_000, currency: "USD"))
        XCTAssertEqual(portfolio.cost, Money(minor: 15_000, currency: "USD"))
        XCTAssertEqual(portfolio.gain, Money(minor: 5_000, currency: "USD"))
        XCTAssertEqual(portfolio.allocation.map(\.fraction), [1])
    }

    func testCarteraConDosMonedasNoDaTotal() {
        let american = holding("Fondo en dólares", currency: "USD")
        let european = holding("Fondo en euros", currency: "EUR")
        let portfolio = Portfolio(holdings: [american, european],
                                  trades: [buy(american, quantity: 10, price: 15), buy(european, quantity: 5, price: 20)])
        XCTAssertEqual(portfolio.positions.count, 2)
        XCTAssertEqual(portfolio.value.formatted(options: .standard), "Varias monedas")
        XCTAssertTrue(portfolio.cost.isMixed)
        XCTAssertTrue(portfolio.gain.isMixed)
        XCTAssertNil(portfolio.gainFraction)
        XCTAssertTrue(portfolio.allocation.isEmpty, "sin total no hay reparto")
    }
}
