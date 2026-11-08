package com.savethemoney.android.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

class PlanningTest {
    private fun d(s: String) = LocalDate.parse(s)
    private fun serie(start: String, amount: Long = 1_000, every: Int = 1, unit: RecurrenceUnit = RecurrenceUnit.Month, end: String? = null) =
        RecurringSeries("s", "h", "Pago", amountMinor = amount, every = every, unit = unit, startsOn = start, endsOn = end)

    @Test
    fun monthlySeriesKeepsDay31() {
        val s = serie("2026-01-31")
        assertEquals(listOf(d("2026-02-28"), d("2026-03-31")), s.occurrences(d("2026-02-01"), d("2026-03-31")))
        assertEquals(d("2026-04-30"), s.nextDue(d("2026-04-01")))
    }

    @Test
    fun seriesEndAndWeekly() {
        assertNull(serie("2026-01-10", end = "2026-03-10").nextDue(d("2026-03-11")))
        val semanal = serie("2026-11-02", every = 2, unit = RecurrenceUnit.Week)
        assertEquals(d("2026-11-30"), semanal.nextDue(d("2026-11-17")))
        assertEquals(217L, semanal.copy(amountMinor = 100).monthlyAmount)
    }

    @Test
    fun introPriceAppliesToFirstCharges() {
        val s = serie("2026-12-08", 1_299).copy(introMinor = 599, introCharges = 3)
        assertEquals(599, s.amountOn(d("2026-12-08")))
        assertEquals(599, s.amountOn(d("2027-02-08")))
        assertEquals(1_299, s.amountOn(d("2027-03-08")))
        assertEquals(d("2027-02-08"), s.introEndsOn)
        assertEquals(599, s.monthlyAmount(d("2026-12-01")))
        assertEquals(1_299, s.monthlyAmount(d("2027-02-09")))
    }

    @Test
    fun issuesMatchServerChecks() {
        assertEquals("Ponle un nombre.", serie("2026-01-01").copy(name = " ").issue)
        assertEquals("Indica el precio de oferta y cuántos cargos dura.", serie("2026-01-01").copy(introMinor = 5).issue)
        assertEquals("El aviso puede ser de 0 a 14 días antes.", serie("2026-01-01").copy(remindDaysBefore = 15).issue)
        assertEquals("No puede terminar antes de empezar.", serie("2026-02-01", end = "2026-01-01").issue)
        assertNull(serie("2026-01-01").issue)
    }

    @Test
    fun remindersSkipPastAndArchived() {
        val hoy = d("2026-11-08")
        val plan = ReminderPlanner.plan(listOf(serie("2026-11-09").copy(remindDaysBefore = 2), serie("2026-11-20").copy(id = "a", archivedAt = "x")), hoy)
        // El del 9 tendría que haber avisado el 7: ya pasó. Quedan diciembre.
        assertEquals("2026-12-07", plan.first().fireOn)
        assertEquals("En 2 días: Pago", plan.first().title)
        assertEquals("Se cobran 10,00 € el 9 de diciembre.", plan.first().body)
        assertEquals("stm.recurring.s.2026-12-09", plan.first().id)
        assertTrue(plan.none { it.id.contains(".a.") })
    }

    @Test
    fun goalProjection() {
        val hoy = d("2026-11-08")
        val meta = Goal("g", "h", "Fondo", targetMinor = 600_000, startingMinor = 300_000, monthlyPlanMinor = 30_000)
        val aporte = GoalContribution("c", "h", "g", 60_000, "2026-11-01")
        val p = GoalProgress(meta, listOf(aporte), hoy)
        assertEquals(360_000, p.saved)
        assertEquals(240_000, p.remaining)
        assertEquals(8, p.monthsLeft)
        assertEquals(YearMonth.of(2027, 7), p.projectedMonth)
        assertEquals(0.6f, p.fraction, 0.001f)
        assertFalse(p.isReached)
    }

    @Test
    fun goalPaceFromLastThreeMonthsAndNeeded() {
        val hoy = d("2026-11-08")
        val meta = Goal("g", "h", "Viaje", targetMinor = 100_000, targetOn = "2027-01-15")
        val aportes = listOf(GoalContribution("a", "h", "g", 10_000, "2026-10-01"), GoalContribution("b", "h", "g", 2_000, "2026-11-02"))
        val p = GoalProgress(meta, aportes, hoy)
        assertEquals(3_334L, p.monthlyPace)
        assertEquals(44_000L, p.neededMonthly)
        assertEquals(false, p.isOnTrack)
    }

    @Test
    fun flexAndAlerts() {
        val nov = YearMonth.of(2026, 11)
        val comida = BudgetCategory("c", "h", "Comida", CategoryKind.Expense, BudgetGroup.Needs)
        val ocio = BudgetCategory("o", "h", "Ocio", CategoryKind.Expense, BudgetGroup.Wants)
        val movs = listOf(
            Movement("1", "h", "a", "c", "2026-11-02", -8_000, "x"),
            Movement("2", "h", "a", "o", "2026-11-02", -12_000, "x"),
        )
        val budget = Budget("h", nov, 100_000, limits = mapOf("c" to 10_000, "o" to 10_000))
        val r = BudgetReport(budget, nov.period(), listOf(comida, ocio), movs)
        val fijo = serie("2026-01-05", 30_000).copy(categoryId = "c")
        val flex = FlexBudget(r, listOf(fijo), d("2026-11-21"))
        assertEquals(30_000, flex.fixed)
        assertEquals(20_000, flex.savings)
        assertEquals(50_000, flex.flexible)
        assertEquals(12_000, flex.flexibleSpent)
        assertEquals(8_000, flex.fixedSpent)
        assertEquals(10, flex.daysLeft)
        assertEquals(3_800L, flex.perDay)

        val avisos = BudgetAlertPlanner.alerts(r, nov)
        assertEquals(listOf("stm.budget.2026-11.c.80", "stm.budget.2026-11.o.100"), avisos.map { it.id })
        assertEquals("Te has pasado en Ocio", avisos[1].title)
    }
}
