package com.savethemoney.android.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal

/**
 * ORC-71: importes de monedas distintas no se suman sin convertir (MoneyCurrencyTests.swift).
 * Los casos compartidos con iOS están en `testdata/vectors/money_currencies.json`.
 */
class MoneyCurrencyTest {
    private fun holding(id: String, currency: String) =
        Holding(id, "home", "Fondo $id", kind = InvestmentKind.Fund, currency = currency, price = BigDecimal("20"), priceOn = "2026-11-01")

    private fun buy(h: Holding, quantity: String, price: String) =
        InvestmentTrade("t-${h.id}", "home", h.id, "2026-01-01", TradeSide.Buy, BigDecimal(quantity), BigDecimal(price), 0)

    @Test
    fun conConversionExplicitaSiSeSuman() {
        val euros = Money.Amount(1_000)
        val dollars = Money.Amount(500, "USD")
        assertNull(Money.total(listOf(euros, dollars)))
        // 5,00 $ a 0,92 € por dólar son 4,60 €.
        val converted = Money.Amount(Money.convert(dollars.minor, BigDecimal("0.92")), "EUR")
        assertEquals(Money.Amount(1_460), Money.total(listOf(euros, converted)))
    }

    @Test
    fun carteraSoloEnDolares() {
        val fund = holding("usd", "USD")
        val p = Portfolio(listOf(fund), listOf(buy(fund, "10", "15")))
        assertFalse(p.mixedCurrencies)
        assertEquals(20_000, p.value)
        assertEquals(15_000, p.cost)
        assertEquals(5_000, p.gain)
    }

    @Test
    fun carteraConDosMonedasNoDaTotal() {
        val american = holding("usd", "USD")
        val european = holding("eur", "EUR")
        val p = Portfolio(listOf(american, european), listOf(buy(american, "10", "15"), buy(european, "5", "20")))
        assertEquals(2, p.positions.size)
        assertTrue(p.mixedCurrencies)
        // Sin total: ni valor, ni ganancia, ni reparto que enseñar por error.
        assertEquals(0, p.value)
        assertEquals(0, p.cost)
        assertNull(p.gainFraction)
        assertTrue(p.allocation.isEmpty())
    }
}
