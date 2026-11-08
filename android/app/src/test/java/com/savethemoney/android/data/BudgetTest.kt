package com.savethemoney.android.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

class BudgetTest {
    private val h = "h"
    private val nov = YearMonth.of(2026, 11)
    private val comida = BudgetCategory("c", h, "Comida", CategoryKind.Expense, BudgetGroup.Needs)
    private val ocio = BudgetCategory("o", h, "Ocio", CategoryKind.Expense, BudgetGroup.Wants)
    private val suelta = BudgetCategory("s", h, "Suelta", CategoryKind.Expense)
    private val nomina = BudgetCategory("n", h, "Nómina", CategoryKind.Income)
    private val traspaso = BudgetCategory("t", h, "Traspaso", CategoryKind.Transfer)
    private val categorias = listOf(comida, ocio, suelta, nomina, traspaso)

    private fun mov(day: String, amount: Long, category: String?) = Movement(day + amount, h, "a", category, day, amount, "x")

    private fun informe(budget: Budget?, vararg m: Movement) = BudgetReport(budget, nov.period(), categorias, m.toList())

    @Test
    fun periodRespectsStartDay() {
        assertEquals(LocalDate.of(2026, 11, 1)..LocalDate.of(2026, 11, 30), nov.period())
        assertEquals(LocalDate.of(2026, 10, 25)..LocalDate.of(2026, 11, 24), nov.period(25))
        assertEquals(nov, monthContaining(LocalDate.of(2026, 10, 25), 25))
        assertEquals(YearMonth.of(2026, 10), monthContaining(LocalDate.of(2026, 10, 24), 25))
        assertEquals(YearMonth.of(2027, 1).minusMonths(1), monthContaining(LocalDate.of(2026, 12, 31)))
    }

    @Test
    fun reportClassifiesMovements() {
        val r = informe(
            Budget(h, nov, 200_000, limits = mapOf("c" to 10_000)),
            mov("2026-11-02", 300_000, "n"),
            mov("2026-11-03", -15_000, "c"),
            mov("2026-11-03", -2_000, "o"),
            mov("2026-11-04", -700, "s"),
            mov("2026-11-04", -300, null),
            mov("2026-11-05", 50, null),
            mov("2026-11-05", -9_999, "t"),
            mov("2026-10-30", -1_000, "c"),
        )
        assertEquals(300_050, r.income)
        assertEquals(200_000, r.base)
        assertEquals(1_000, r.uncategorized)
        assertEquals(18_000, r.totalSpent)
        assertEquals(listOf(100_000L, 60_000L, 40_000L), r.groups.map { it.allocated })
        assertEquals(listOf("Nómina" to 300_000L, "Sin categoría" to 50L), r.incomeSources)
        val line = r.lines(BudgetGroup.Needs).single()
        assertTrue(line.isOver)
        assertEquals(1f, line.fraction)
        assertNull(r.lines(BudgetGroup.Wants).single().fraction)
    }

    @Test
    fun withoutBudgetBaseIsRealIncome() {
        assertEquals(1_000, informe(null, mov("2026-11-02", 1_000, "n")).base)
    }

    @Test
    fun cashFlowAddsUnspentOrFromBalanceAndBalances() {
        val sobra = CashFlow(informe(null, mov("2026-11-02", 1_000, "n"), mov("2026-11-03", -400, "c")))
        assertEquals(600.0, sobra.nodes.first { it.id == "sin-gastar" }.value, 0.001)

        val falta = CashFlow(informe(null, mov("2026-11-02", 300, "n"), mov("2026-11-03", -400, "c")))
        assertEquals(100.0, falta.nodes.first { it.id == "del-saldo" }.value, 0.001)
        assertTrue(falta.nodes.none { it.id == "sin-gastar" })
        assertTrue(CashFlow(informe(null)).isEmpty)
    }

    @Test
    fun sankeyBandsFitTheirNodes() {
        val flow = CashFlow(informe(null, mov("2026-11-02", 1_000, "n"), mov("2026-11-03", -400, "c"), mov("2026-11-03", -100, "o")))
        val layout = SankeyLayout(flow, 332.0, 300.0, gap = 10.0)
        for (node in flow.nodes.filter { it.column == 1 }) {
            val rect = layout.nodes.getValue(node.id)
            val entra = layout.bands.filter { it.to == node.id }.sumOf { it.thickness }
            assertEquals(rect.height, entra, 0.001)
            assertTrue(rect.y >= 0 && rect.y + rect.height <= 300.001)
        }
        assertEquals(161.0, layout.nodes.getValue("grupo:Needs").x, 0.001)
    }
}
