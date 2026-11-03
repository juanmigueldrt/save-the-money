import XCTest
@testable import STMCore

/// Posiciones, cartera, evolución, compra y aportaciones automáticas. Datos inventados.
final class InvestmentTests: XCTestCase {
    let home = UUID()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }
    private func dec(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    private func fund(_ name: String = "Fondo indexado mundial", price: String = "10", kind: InvestmentKind = .fund,
                      fee: String = "0") -> Holding {
        Holding(householdId: home, name: name, kind: kind, price: dec(price), priceOn: day(2026, 11, 1), feeRate: dec(fee))
    }

    private func trade(_ holding: Holding, _ side: TradeSide, _ quantity: String, at price: String,
                       on date: CalendarDay, fee: Int = 0) -> InvestmentTrade {
        InvestmentTrade(householdId: home, holdingId: holding.id, tradedOn: date, side: side,
                        quantity: dec(quantity), price: dec(price), fee: Money(minor: fee))
    }

    func testMoneyFromDecimalRoundsToCents() {
        XCTAssertEqual(Money(decimal: dec("12.345")), Money(minor: 1235))
        XCTAssertEqual(Money(decimal: dec("12.344")), Money(minor: 1234))
        XCTAssertEqual(Money(decimal: dec("-3.005")), Money(minor: -301))
        XCTAssertEqual(dec("1.123456789").rounded(scale: 8, .down), dec("1.12345678"))
    }

    func testPositionWithAveragePrice() {
        let holding = fund(price: "12")
        let trades = [
            trade(holding, .buy, "10", at: "10", on: day(2026, 1, 10), fee: 100),   // 100 € + 1 €
            trade(holding, .buy, "10", at: "11", on: day(2026, 2, 10), fee: 100),   // 110 € + 1 €
            trade(holding, .sell, "5", at: "12", on: day(2026, 3, 10), fee: 50),    // 60 € − 0,50 €
        ]
        let position = Position(holding: holding, trades: trades)
        XCTAssertEqual(position.quantity, 15)
        XCTAssertEqual(position.invested, Money(minor: 21_200))
        // Coste medio 212 / 20 = 10,60; se venden 5 → quedan 159 €.
        XCTAssertEqual(position.cost, Money(minor: 15_900))
        XCTAssertEqual(position.averagePrice, dec("10.6"))
        XCTAssertEqual(position.realized, Money(minor: 6_000 - 50 - 5_300))
        XCTAssertEqual(position.value, Money(minor: 18_000))
        XCTAssertEqual(position.gain, Money(minor: 2_100))
        XCTAssertEqual(position.gainFraction ?? 0, 2_100.0 / 15_900.0, accuracy: 1e-9)

        let before = Position(holding: holding, trades: trades, through: day(2026, 1, 31))
        XCTAssertEqual(before.quantity, 10)
    }

    func testSellCannotExceedHolding() {
        let holding = fund()
        let bought = [trade(holding, .buy, "2.5", at: "10", on: day(2026, 5, 1))]
        XCTAssertNil(trade(holding, .sell, "2.5", at: "11", on: day(2026, 6, 1)).issue(given: bought))
        XCTAssertNotNil(trade(holding, .sell, "3", at: "11", on: day(2026, 6, 1)).issue(given: bought))
        XCTAssertNotNil(trade(holding, .sell, "1", at: "11", on: day(2026, 4, 1)).issue(given: bought), "antes de comprar")
        XCTAssertNotNil(trade(holding, .buy, "0", at: "11", on: day(2026, 6, 1)).issue)
        XCTAssertNotNil(trade(holding, .buy, "0.123456789", at: "11", on: day(2026, 6, 1)).issue)
    }

    func testPortfolioTotalsAndAllocation() {
        let world = fund(price: "20")
        let bonds = fund("Fondo de bonos", price: "5", kind: .bond)
        let coin = fund("Moneda digital", price: "100", kind: .crypto)
        var old = fund("Fondo antiguo", price: "1")
        old.archivedAt = Date()
        let trades = [
            trade(world, .buy, "30", at: "15", on: day(2026, 1, 1)),    // vale 600, costó 450
            trade(bonds, .buy, "60", at: "5", on: day(2026, 1, 1)),     // vale 300, costó 300
            trade(coin, .buy, "1", at: "100", on: day(2026, 1, 1)),
            trade(coin, .sell, "1", at: "120", on: day(2026, 2, 1)),    // ya no queda nada
            trade(old, .buy, "100", at: "1", on: day(2026, 1, 1)),
        ]
        let portfolio = Portfolio(holdings: [world, bonds, coin, old], trades: trades)
        XCTAssertEqual(portfolio.positions.map(\.holding.id), [world.id, bonds.id])
        XCTAssertEqual(portfolio.value, Money(minor: 90_000))
        XCTAssertEqual(portfolio.cost, Money(minor: 75_000))
        XCTAssertEqual(portfolio.gain, Money(minor: 15_000))
        XCTAssertEqual(portfolio.gainFraction ?? 0, 0.2, accuracy: 1e-9)
        XCTAssertEqual(portfolio.allocation.map(\.assetClass), [.equity, .fixedIncome])
        XCTAssertEqual(portfolio.allocation.map(\.fraction).reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertEqual(portfolio.allocation.first?.fraction ?? 0, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertTrue(Portfolio(holdings: [], trades: []).allocation.isEmpty)
    }

    func testEvolutionUsesKnownPrices() {
        var holding = fund(price: "14")
        holding.priceOn = day(2026, 11, 1)
        let trades = [trade(holding, .buy, "10", at: "10", on: day(2026, 10, 5))]
        let prices = [HoldingPrice(householdId: home, holdingId: holding.id, pricedOn: day(2026, 10, 20), price: dec("12"))]
        let points = PriceHistory.evolution(holdings: [holding], prices: prices, trades: trades,
                                            range: .month, today: day(2026, 11, 3))
        XCTAssertEqual(points.first?.day, day(2026, 10, 3))
        XCTAssertEqual(points.last?.day, day(2026, 11, 3))
        XCTAssertEqual(points.first?.value, .zero, "aún no se había comprado")
        XCTAssertEqual(points.first { $0.day == day(2026, 10, 10) }?.value, Money(minor: 10_000))
        XCTAssertEqual(points.first { $0.day == day(2026, 10, 25) }?.value, Money(minor: 12_000))
        XCTAssertEqual(points.last?.value, Money(minor: 14_000))

        let all = ChartRange.all.days(today: day(2026, 11, 3), earliest: day(2020, 1, 1))
        XCTAssertLessThanOrEqual(all.count, 61)
        XCTAssertEqual(all.first, day(2020, 1, 1))
        XCTAssertEqual(all.last, day(2026, 11, 3))

        let range = PriceHistory.range(for: holding, prices: prices, trades: trades,
                                       from: day(2025, 11, 3), through: day(2026, 11, 3))
        XCTAssertEqual(range, dec("10")...dec("14"))
    }

    func testBuyQuote() throws {
        // 500 € a 12,50 €, con una comisión del 0,2 %.
        let byAmount = try XCTUnwrap(BuyQuote.byAmount(Money(minor: 50_000), price: dec("12.5"), feeRate: dec("0.2")))
        XCTAssertEqual(byAmount.quantity, 40)
        XCTAssertEqual(byAmount.fee, Money(minor: 100))
        XCTAssertEqual(byAmount.total, Money(minor: 50_100))

        let odd = try XCTUnwrap(BuyQuote.byAmount(Money(minor: 10_000), price: dec("3"), feeRate: 0))
        XCTAssertEqual(odd.quantity, dec("33.33333333"), "hacia abajo, 8 decimales")

        let byQuantity = try XCTUnwrap(BuyQuote.byQuantity(dec("2.5"), price: dec("101.234"), feeRate: dec("0.15")))
        XCTAssertEqual(byQuantity.amount, Money(minor: 25_309))
        XCTAssertEqual(byQuantity.fee, Money(minor: 38))
        XCTAssertNil(BuyQuote.byAmount(Money(minor: 100), price: 0, feeRate: 0))
        XCTAssertNil(BuyQuote.byQuantity(0, price: 10, feeRate: 0))

        let holding = fund()
        let saved = byAmount.trade(for: holding, price: dec("12.5"), on: day(2026, 11, 3))
        XCTAssertEqual(saved.gross, Money(minor: 50_000))
        XCTAssertEqual(saved.cashImpact, Money(minor: -50_100))
    }

    func testPlansCalendarTotalsAndProjection() {
        let holding = fund()
        let monthly = InvestmentPlan(householdId: home, holdingId: holding.id, amount: Money(minor: 30_000),
                                     startsOn: day(2026, 1, 5))
        let biweekly = InvestmentPlan(householdId: home, holdingId: holding.id, amount: Money(minor: 6_000),
                                      recurrence: Recurrence(every: 2, unit: .week), startsOn: day(2026, 11, 2))
        var paused = InvestmentPlan(householdId: home, holdingId: holding.id, amount: Money(minor: 5_000),
                                    startsOn: day(2026, 1, 1))
        paused.pausedAt = Date()
        let plans = [monthly, biweekly, paused]

        let november = plans.charges(in: MonthKey(year: 2026, month: 11))
        XCTAssertEqual(november.map(\.due), [day(2026, 11, 2), day(2026, 11, 5), day(2026, 11, 16), day(2026, 11, 30)])
        // 300 € al mes + 60 € cada 2 semanas (26 al año → 130 € al mes).
        XCTAssertEqual(plans.monthlyTotal(on: day(2026, 11, 3)), Money(minor: 43_000))
        XCTAssertEqual(plans.counts(on: day(2026, 11, 3)).active, 2)
        XCTAssertEqual(plans.counts(on: day(2026, 11, 3)).paused, 1)
        XCTAssertNil(paused.nextDue(onOrAfter: day(2026, 11, 3)))
        XCTAssertEqual(monthly.nextDue(onOrAfter: day(2026, 11, 6)), day(2026, 12, 5))

        let trades = [trade(holding, .buy, "10", at: "30", on: day(2026, 2, 5), fee: 60),
                      trade(holding, .buy, "1", at: "30", on: day(2025, 12, 1))]
        XCTAssertEqual(monthly.invested(trades: trades, through: day(2026, 11, 3)), Money(minor: 30_060))

        var flat = monthly
        flat.expectedAnnualReturn = 0
        XCTAssertEqual(flat.projectedValue(months: 12), Money(minor: 360_000))
        XCTAssertGreaterThan(monthly.projectedValue(months: 12).minor, 360_000)
        XCTAssertLessThan(monthly.projectedValue(months: 12).minor, 380_000)

        var bad = monthly
        bad.expectedAnnualReturn = 60
        XCTAssertNotNil(bad.issue)
        bad = monthly
        bad.endsOn = day(2025, 1, 1)
        XCTAssertNotNil(bad.issue)
    }

    func testHoldingDetails() {
        XCTAssertEqual(fund("Fondo indexado mundial").initials, "FI")
        var withSymbol = fund()
        withSymbol.symbol = " vwce "
        XCTAssertEqual(withSymbol.trimmedSymbol, "VWCE")
        XCTAssertEqual(withSymbol.initials, "VW")
        XCTAssertEqual(fund("Oro").initials, "OR")
        XCTAssertEqual(InvestmentKind.bond.defaultAssetClass, .fixedIncome)
        XCTAssertNotNil(fund(" ").issue)
        XCTAssertNotNil(fund(fee: "11").issue)
    }

    func testCodingUsesServerColumns() throws {
        let json = """
        {"id":"7B0B4C53-5A1E-4D5B-9C1E-6B1E1A0F0011","household_id":"7B0B4C53-5A1E-4D5B-9C1E-6B1E1A0F0012",
         "name":"Fondo de prueba","symbol":null,"kind":"etf","asset_class":"fixed_income","currency":"EUR",
         "account_id":null,"owner_id":null,"price":101.123456,"price_on":"2026-11-01","fee_rate":"0.150",
         "note":null,"archived_at":null}
        """
        let holding = try JSONDecoder().decode(Holding.self, from: Data(json.utf8))
        XCTAssertEqual(holding.assetClass, .fixedIncome)
        XCTAssertEqual(holding.price.rounded(scale: 6), dec("101.123456"))
        XCTAssertEqual(holding.feeRate, dec("0.15"))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(holding)) as! [String: Any]
        XCTAssertEqual(encoded["asset_class"] as? String, "fixed_income")
        XCTAssertNil(encoded["id"])
        XCTAssertNil(encoded["household_id"])

        let tradeJSON = """
        {"id":"7B0B4C53-5A1E-4D5B-9C1E-6B1E1A0F0013","household_id":"7B0B4C53-5A1E-4D5B-9C1E-6B1E1A0F0012",
         "holding_id":"7B0B4C53-5A1E-4D5B-9C1E-6B1E1A0F0011","traded_on":"2026-11-02","side":"sell",
         "quantity":0.5,"price":"100","fee_minor":25,"note":null}
        """
        let trade = try JSONDecoder().decode(InvestmentTrade.self, from: Data(tradeJSON.utf8))
        XCTAssertEqual(trade.side, .sell)
        XCTAssertEqual(trade.cashImpact, Money(minor: 4_975))

        let planJSON = """
        {"id":"7B0B4C53-5A1E-4D5B-9C1E-6B1E1A0F0014","household_id":"7B0B4C53-5A1E-4D5B-9C1E-6B1E1A0F0012",
         "holding_id":"7B0B4C53-5A1E-4D5B-9C1E-6B1E1A0F0011","account_id":null,"amount_minor":15000,"every":1,
         "unit":"month","starts_on":"2026-11-05","ends_on":null,"expected_annual_return":5.00,
         "remind_days_before":1,"paused_at":"2026-11-02T10:00:00+00:00","archived_at":null}
        """
        let plan = try JSONDecoder().decode(InvestmentPlan.self, from: Data(planJSON.utf8))
        XCTAssertTrue(plan.isPaused)
        let planEncoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as! [String: Any]
        XCTAssertNil(planEncoded["holding_id"], "el activo de un plan no se cambia")
        XCTAssertEqual(planEncoded["amount_minor"] as? Int, 15_000)
    }

    func testInMemoryRulesAndHouseholdsApart() async throws {
        let backend = InMemoryBackend()
        let ana = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        let house = try await backend.createHousehold(name: "Casa")
        let holding = try await backend.createHolding(Holding(householdId: house.id, name: " Fondo global ",
                                                              symbol: "fg", ownerId: ana, price: 10))
        XCTAssertEqual(holding.name, "Fondo global")
        XCTAssertEqual(holding.symbol, "FG")

        _ = try await backend.addTrade(InvestmentTrade(householdId: house.id, holdingId: holding.id,
                                                       tradedOn: day(2026, 10, 1), quantity: 5, price: 10))
        do {
            _ = try await backend.addTrade(InvestmentTrade(householdId: house.id, holdingId: holding.id,
                                                           tradedOn: day(2026, 10, 2), side: .sell, quantity: 6, price: 10))
            XCTFail("no se vende más de lo que hay")
        } catch {}

        var updated = try await backend.recordPrice(12, on: day(2026, 11, 1), for: holding.id)
        XCTAssertEqual(updated.price, 12)
        updated = try await backend.recordPrice(13, on: day(2026, 11, 1), for: holding.id)
        updated = try await backend.recordPrice(9, on: day(2026, 10, 15), for: holding.id)
        XCTAssertEqual(updated.price, 13, "un precio antiguo no cambia el actual")
        XCTAssertEqual(updated.priceOn, day(2026, 11, 1))
        let prices = try await backend.holdingPrices(in: house.id)
        XCTAssertEqual(prices.map(\.price), [9, 13])

        let plan = try await backend.createPlan(InvestmentPlan(householdId: house.id, holdingId: holding.id,
                                                               amount: Money(minor: 10_000), startsOn: day(2026, 11, 5)))
        try await backend.signOut()

        let carla = try await backend.signUp(username: Username("carla"), password: "contrasena-de-prueba", displayName: nil)
        let other = try await backend.createHousehold(name: "Otro")
        do {
            _ = try await backend.holdings(in: house.id)
            XCTFail("Carla no debe ver inversiones ajenas")
        } catch {}
        do {
            _ = try await backend.addTrade(InvestmentTrade(householdId: other.id, holdingId: holding.id,
                                                           tradedOn: day(2026, 11, 1), quantity: 1, price: 1))
            XCTFail("no se opera con un activo de otro hogar")
        } catch {}
        do {
            _ = try await backend.createHolding(Holding(householdId: other.id, name: "Mío", ownerId: ana))
            XCTFail("el dueño tiene que ser del hogar")
        } catch {}
        _ = try await backend.createHolding(Holding(householdId: other.id, name: "Mío", ownerId: carla))
        do {
            try await backend.deletePlan(plan.id)
            XCTFail("no se borra un plan de otro hogar")
        } catch {}
        try await backend.signOut()

        _ = try await backend.signIn(username: Username("ana"), password: "contrasena-de-prueba")
        let plans = try await backend.investmentPlans(in: house.id)
        XCTAssertEqual(plans.count, 1)
        try await backend.resetHousehold(house.id)
        let afterReset = try await backend.holdings(in: house.id)
        let tradesAfter = try await backend.trades(in: house.id)
        XCTAssertTrue(afterReset.isEmpty)
        XCTAssertTrue(tradesAfter.isEmpty)
    }

    func testParsingTypedNumbers() {
        XCTAssertEqual(Decimal(parsing: "12,5"), dec("12.5"))
        XCTAssertEqual(Decimal(parsing: " 12.5 € "), dec("12.5"))
        XCTAssertEqual(Decimal(parsing: "1.234,56"), dec("1234.56"))
        XCTAssertEqual(Decimal(parsing: "1,234.56"), dec("1234.56"))
        XCTAssertEqual(Decimal(parsing: "0,2 %"), dec("0.2"))
        XCTAssertNil(Decimal(parsing: ""))
        XCTAssertNil(Decimal(parsing: "-3"))
        XCTAssertNil(Decimal(parsing: "1,2,3"))
        XCTAssertNil(Decimal(parsing: "doce"))
    }

    func testPlanReminders() {
        let holding = fund("Fondo global")
        let plan = InvestmentPlan(householdId: home, holdingId: holding.id, amount: Money(minor: 15_000),
                                  startsOn: day(2026, 11, 5), remindDaysBefore: 1)
        var paused = plan
        paused = InvestmentPlan(householdId: home, holdingId: holding.id, amount: Money(minor: 1_000),
                                startsOn: day(2026, 11, 4), pausedAt: Date())
        let reminders = ReminderPlanner.plan([plan, paused], holdings: [holding], today: day(2026, 11, 3))
        XCTAssertEqual(reminders.map(\.fireOn), [day(2026, 11, 4), day(2026, 12, 4)])
        XCTAssertEqual(reminders.first?.title, "Mañana: aportación a Fondo global")
        XCTAssertTrue(reminders.allSatisfy { $0.id.hasPrefix(ReminderPlanner.investmentPrefix) })
        XCTAssertTrue(reminders.first?.body.contains("5 de noviembre") ?? false)
    }
}
