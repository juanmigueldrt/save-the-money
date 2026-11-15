package com.savethemoney.android.data

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate
import java.time.YearMonth

/** Los mismos casos que InvestmentTests.swift, para que Android e iOS calculen igual. Datos inventados. */
class InvestmentTest {
    private val home = "home"
    private var n = 0

    private fun day(y: Int, m: Int, d: Int) = LocalDate.of(y, m, d)
    private fun dec(text: String) = BigDecimal(text)
    private fun assertSame(expected: String, actual: BigDecimal?) = assertEquals(0, dec(expected).compareTo(actual))

    private fun fund(name: String = "Fondo indexado mundial", price: String = "10", kind: InvestmentKind = InvestmentKind.Fund, fee: String = "0", archived: Boolean = false) =
        Holding("h${n++}", home, name, kind = kind, price = dec(price), priceOn = "2026-11-01", feeRate = dec(fee), archivedAt = if (archived) "2026-01-01T00:00:00Z" else null)

    private fun trade(h: Holding, side: TradeSide, quantity: String, price: String, on: LocalDate, fee: Long = 0) =
        InvestmentTrade("t${n++}", home, h.id, on.toString(), side, dec(quantity), dec(price), fee)

    private fun plan(h: Holding, minor: Long, start: LocalDate, every: Int = 1, unit: RecurrenceUnit = RecurrenceUnit.Month, paused: Boolean = false) =
        InvestmentPlan("p${n++}", home, h.id, amountMinor = minor, every = every, unit = unit, startsOn = start.toString(), pausedAt = if (paused) "2026-11-01T00:00:00Z" else null)

    @Test fun moneyFromDecimalRoundsToCents() {
        assertEquals(1235, dec("12.345").toMinor())
        assertEquals(1234, dec("12.344").toMinor())
        assertEquals(-301, dec("-3.005").toMinor())
    }

    @Test fun positionWithAveragePrice() {
        val h = fund(price = "12")
        val trades = listOf(
            trade(h, TradeSide.Buy, "10", "10", day(2026, 1, 10), 100),
            trade(h, TradeSide.Buy, "10", "11", day(2026, 2, 10), 100),
            trade(h, TradeSide.Sell, "5", "12", day(2026, 3, 10), 50),
        )
        val p = Position(h, trades)
        assertSame("15", p.quantity)
        assertEquals(21_200, p.invested)
        assertEquals(15_900, p.cost)
        assertSame("10.6", p.averagePrice)
        assertEquals(6_000L - 50 - 5_300, p.realized)
        assertEquals(18_000, p.value)
        assertEquals(2_100, p.gain)
        assertEquals(2_100.0 / 15_900.0, p.gainFraction!!, 1e-9)
        assertSame("10", Position(h, trades, day(2026, 1, 31)).quantity)
    }

    @Test fun sellCannotExceedHolding() {
        val h = fund()
        val bought = listOf(trade(h, TradeSide.Buy, "2.5", "10", day(2026, 5, 1)))
        assertNull(trade(h, TradeSide.Sell, "2.5", "11", day(2026, 6, 1)).issue(bought))
        assertNotNull(trade(h, TradeSide.Sell, "3", "11", day(2026, 6, 1)).issue(bought))
        assertNotNull(trade(h, TradeSide.Sell, "1", "11", day(2026, 4, 1)).issue(bought))
        assertNotNull(trade(h, TradeSide.Buy, "0", "11", day(2026, 6, 1)).issue)
        assertNotNull(trade(h, TradeSide.Buy, "0.123456789", "11", day(2026, 6, 1)).issue)
    }

    @Test fun portfolioTotalsAndAllocation() {
        val world = fund(price = "20")
        val bonds = fund("Fondo de bonos", "5", InvestmentKind.Bond)
        val coin = fund("Moneda digital", "100", InvestmentKind.Crypto)
        val old = fund("Fondo antiguo", "1", archived = true)
        val trades = listOf(
            trade(world, TradeSide.Buy, "30", "15", day(2026, 1, 1)),
            trade(bonds, TradeSide.Buy, "60", "5", day(2026, 1, 1)),
            trade(coin, TradeSide.Buy, "1", "100", day(2026, 1, 1)),
            trade(coin, TradeSide.Sell, "1", "120", day(2026, 2, 1)),
            trade(old, TradeSide.Buy, "100", "1", day(2026, 1, 1)),
        )
        val p = Portfolio(listOf(world, bonds, coin, old), trades)
        assertEquals(listOf(world.id, bonds.id), p.positions.map { it.holding.id })
        assertEquals(90_000, p.value)
        assertEquals(75_000, p.cost)
        assertEquals(15_000, p.gain)
        assertEquals(0.2, p.gainFraction!!, 1e-9)
        assertEquals(listOf(AssetClass.Equity, AssetClass.FixedIncome), p.allocation.map { it.assetClass })
        assertEquals(1.0, p.allocation.sumOf { it.fraction }, 1e-9)
        assertEquals(2.0 / 3.0, p.allocation.first().fraction, 1e-9)
        assertTrue(Portfolio(emptyList(), emptyList()).allocation.isEmpty())
    }

    @Test fun evolutionUsesKnownPrices() {
        val h = fund(price = "14")
        val trades = listOf(trade(h, TradeSide.Buy, "10", "10", day(2026, 10, 5)))
        val prices = listOf(HoldingPrice("x", home, h.id, "2026-10-20", dec("12")))
        val points = PriceHistory.evolution(listOf(h), prices, trades, ChartRange.Month, day(2026, 11, 3))
        assertEquals(day(2026, 10, 3), points.first().day)
        assertEquals(day(2026, 11, 3), points.last().day)
        assertEquals(0, points.first().value)
        assertEquals(10_000, points.first { it.day == day(2026, 10, 10) }.value)
        assertEquals(12_000, points.first { it.day == day(2026, 10, 25) }.value)
        assertEquals(14_000, points.last().value)

        val all = ChartRange.All.days(day(2026, 11, 3), day(2020, 1, 1))
        assertTrue(all.size <= 61)
        assertEquals(day(2020, 1, 1), all.first())
        assertEquals(day(2026, 11, 3), all.last())

        val range = PriceHistory.range(h, prices, trades, day(2025, 11, 3), day(2026, 11, 3))!!
        assertSame("10", range.first)
        assertSame("14", range.second)
    }

    @Test fun buyQuote() {
        val byAmount = BuyQuote.byAmount(50_000, dec("12.5"), dec("0.2"))!!
        assertSame("40", byAmount.quantity)
        assertEquals(100, byAmount.fee)
        assertEquals(50_100, byAmount.total)
        assertSame("33.33333333", BuyQuote.byAmount(10_000, dec("3"), BigDecimal.ZERO)!!.quantity)

        val byQuantity = BuyQuote.byQuantity(dec("2.5"), dec("101.234"), dec("0.15"))!!
        assertEquals(25_309, byQuantity.amount)
        assertEquals(38, byQuantity.fee)
        assertNull(BuyQuote.byAmount(100, BigDecimal.ZERO, BigDecimal.ZERO))
        assertNull(BuyQuote.byQuantity(BigDecimal.ZERO, BigDecimal.TEN, BigDecimal.ZERO))

        val saved = byAmount.trade(fund(), dec("12.5"), day(2026, 11, 3))
        assertEquals(50_000, saved.gross)
        assertEquals(-50_100, saved.cashImpact)
    }

    @Test fun plansCalendarTotalsAndProjection() {
        val h = fund()
        val monthly = plan(h, 30_000, day(2026, 1, 5))
        val biweekly = plan(h, 6_000, day(2026, 11, 2), 2, RecurrenceUnit.Week)
        val paused = plan(h, 5_000, day(2026, 1, 1), paused = true)
        val plans = listOf(monthly, biweekly, paused)

        assertEquals(listOf(day(2026, 11, 2), day(2026, 11, 5), day(2026, 11, 16), day(2026, 11, 30)), plans.charges(YearMonth.of(2026, 11)).map { it.due })
        assertEquals(43_000, plans.monthlyTotal(day(2026, 11, 3)))
        assertEquals(2 to 1, plans.counts(day(2026, 11, 3)))
        assertNull(paused.nextDue(day(2026, 11, 3)))
        assertEquals(day(2026, 12, 5), monthly.nextDue(day(2026, 11, 6)))

        val trades = listOf(trade(h, TradeSide.Buy, "10", "30", day(2026, 2, 5), 60), trade(h, TradeSide.Buy, "1", "30", day(2025, 12, 1)))
        assertEquals(30_060, monthly.invested(trades, day(2026, 11, 3)))

        assertEquals(360_000, monthly.copy(expectedAnnualReturn = BigDecimal.ZERO).projectedValue(12))
        assertTrue(monthly.projectedValue(12) in 360_001 until 380_000)
        assertNotNull(monthly.copy(expectedAnnualReturn = BigDecimal(60)).issue)
        assertNotNull(monthly.copy(endsOn = "2025-01-01").issue)
    }

    @Test fun holdingDetails() {
        assertEquals("VWCE", fund().copy(symbol = " vwce ").trimmedSymbol)
        assertEquals(AssetClass.FixedIncome, InvestmentKind.Bond.defaultAssetClass)
        assertNotNull(fund(" ").issue)
        assertNotNull(fund(fee = "11").issue)
    }

    @Test fun decodesServerColumns() {
        val json = Json { ignoreUnknownKeys = true }
        val holding = json.decodeFromString<Holding>(
            """{"id":"a","household_id":"b","name":"Fondo","symbol":null,"kind":"etf","asset_class":"fixed_income","currency":"EUR",
            "account_id":null,"owner_id":null,"price":101.123456,"price_on":"2026-11-01","fee_rate":"0.150","note":null,"archived_at":null}""",
        )
        assertEquals(AssetClass.FixedIncome, holding.assetClass)
        assertSame("101.123456", holding.price)
        assertSame("0.15", holding.feeRate)
        val trade = json.decodeFromString<InvestmentTrade>(
            """{"id":"a","household_id":"b","holding_id":"c","traded_on":"2026-11-02","side":"sell","quantity":0.5,"price":"100","fee_minor":25,"note":null}""",
        )
        assertEquals(4_975, trade.cashImpact)
        val plan = json.decodeFromString<InvestmentPlan>(
            """{"id":"a","household_id":"b","holding_id":"c","account_id":null,"amount_minor":15000,"every":1,"unit":"month","starts_on":"2026-11-05",
            "ends_on":null,"expected_annual_return":5.00,"remind_days_before":1,"paused_at":"2026-11-02T10:00:00+00:00","archived_at":null}""",
        )
        assertTrue(plan.isPaused)
    }

    @Test fun inMemoryRules() = runBlocking {
        val service = InMemoryFinance()
        val holding = service.createHolding(Holding("", home, " Fondo global ", symbol = "fg", price = BigDecimal.TEN))
        assertEquals("Fondo global", holding.name)
        assertEquals("FG", holding.symbol)
        service.addTrade(InvestmentTrade("", home, holding.id, "2026-10-01", quantity = BigDecimal(5), price = BigDecimal.TEN))
        assertThrows(AppError::class.java) {
            runBlocking { service.addTrade(InvestmentTrade("", home, holding.id, "2026-10-02", TradeSide.Sell, BigDecimal(6), BigDecimal.TEN)) }
        }
        assertSame("12", service.recordPrice(BigDecimal(12), day(2026, 11, 1), holding.id).price)
        service.recordPrice(BigDecimal(13), day(2026, 11, 1), holding.id)
        val updated = service.recordPrice(BigDecimal(9), day(2026, 10, 15), holding.id)
        assertSame("13", updated.price)
        assertEquals(listOf(9, 13), service.holdingPrices(home).map { it.price.toInt() })
        service.resetHousehold(home)
        assertTrue(service.holdings(home).isEmpty())
        assertTrue(service.trades(home).isEmpty())
    }

    @Test fun parsingTypedNumbers() {
        assertSame("12.5", parseDecimal("12,5"))
        assertSame("12.5", parseDecimal(" 12.5 € "))
        assertSame("1234.56", parseDecimal("1.234,56"))
        assertSame("1234.56", parseDecimal("1,234.56"))
        assertSame("0.2", parseDecimal("0,2 %"))
        assertNull(parseDecimal(""))
        assertNull(parseDecimal("-3"))
        assertNull(parseDecimal("1,2,3"))
        assertNull(parseDecimal("doce"))
    }

    @Test fun planReminders() {
        val h = fund("Fondo global")
        val reminders = InvestmentReminders.plan(listOf(plan(h, 15_000, day(2026, 11, 5)), plan(h, 1_000, day(2026, 11, 4), paused = true)), listOf(h), day(2026, 11, 3))
        assertEquals(listOf("2026-11-04", "2026-12-04"), reminders.map { it.fireOn })
        assertEquals("Mañana: aportación a Fondo global", reminders.first().title)
        assertTrue(reminders.all { it.id.startsWith(InvestmentReminders.PREFIX) })
        assertTrue("5 de noviembre" in reminders.first().body)
    }

    @Test fun formats() {
        assertEquals("1.234,5034 €", InvestmentText.price(dec("1234.5034")))
        assertEquals("12,50 €", InvestmentText.price(dec("12.5").setScale(6, RoundingMode.HALF_UP)))
        assertEquals("112,4", InvestmentText.quantity(dec("112.40000000")))
        assertEquals("+12,3 %", InvestmentText.percent(0.1234))
        assertEquals("−4,0 %", InvestmentText.percent(-0.04))
        assertEquals("0,2 %", InvestmentText.rate(dec("0.200")))
        assertEquals("1234,5", InvestmentText.plain(dec("1234.5")))
    }
}
