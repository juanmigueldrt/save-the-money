package com.savethemoney.android.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

/** Fase C, como PhaseCTests de iOS: periodos, «puedes gastar hoy», arrastre, presupuesto inteligente, avisos y extras. */
class PhaseCTest {
    private val home = "h"
    private val account = "a"
    private var n = 0
    private fun day(y: Int, m: Int, d: Int) = LocalDate.of(y, m, d)

    private fun spend(minor: Long, on: LocalDate, category: String? = null, excluded: Boolean = false, accountId: String = account) =
        Movement("m${n++}", home, accountId, category, on.toString(), -minor, "GASTO", excluded = excluded)

    private val food = BudgetCategory("food", home, "Comida", CategoryKind.Expense, BudgetGroup.Needs)
    private val fun_ = BudgetCategory("fun", home, "Ocio", CategoryKind.Expense, BudgetGroup.Wants)

    // Periodos

    @Test
    fun monthlyPeriodsFromPayday() {
        val schedule = PaySchedule(PayFrequency.Monthly, 25)
        val period = schedule.period(day(2026, 11, 15))
        assertEquals(day(2026, 10, 25), period.start)
        assertEquals(day(2026, 11, 24), period.end)
        assertEquals(YearMonth.of(2026, 11), period.month)
        assertEquals(day(2026, 11, 25), schedule.periodAfter(period).start)
        assertEquals(day(2026, 10, 24), schedule.periodBefore(period).end)
        // Día 31: en meses cortos cobra el último día.
        val end = PaySchedule(PayFrequency.Monthly, 31)
        assertEquals(day(2027, 1, 31), end.period(day(2027, 2, 10)).start)
        assertEquals(day(2027, 2, 27), end.period(day(2027, 2, 10)).end)
        assertEquals(day(2027, 2, 28), end.nextPayday(day(2027, 2, 10)))
        // Día 1 = mes natural, con su nombre.
        val natural = PaySchedule.monthly(1).period(day(2026, 11, 15))
        assertEquals(BudgetPeriod(YearMonth.of(2026, 11)), natural)
        assertEquals("Noviembre de 2026", natural.title)
        assertEquals("25 oct – 24 nov", period.title)
    }

    @Test
    fun twiceMonthlyWeeklyBiweeklyAndYearly() {
        val twice = PaySchedule(PayFrequency.TwiceMonthly, 1, 15)
        assertEquals(BudgetPeriod(day(2026, 11, 15), day(2026, 11, 30)), twice.period(day(2026, 11, 20)))
        assertEquals(BudgetPeriod(day(2026, 11, 1), day(2026, 11, 14)), twice.period(day(2026, 11, 3)))

        // 2026-11-06 es viernes.
        val weekly = PaySchedule(PayFrequency.Weekly, anchor = day(2026, 11, 6))
        assertEquals("viernes", PaySchedule.weekdayName(day(2026, 11, 6)))
        assertEquals(BudgetPeriod(day(2026, 11, 13), day(2026, 11, 19)), weekly.period(day(2026, 11, 15)))
        assertEquals("también hacia atrás", day(2026, 9, 25), weekly.period(day(2026, 10, 1)).start)

        val biweekly = PaySchedule(PayFrequency.Biweekly, anchor = day(2026, 11, 6))
        assertEquals(BudgetPeriod(day(2026, 11, 6), day(2026, 11, 19)), biweekly.period(day(2026, 11, 15)))
        assertEquals(day(2026, 11, 20), biweekly.nextPayday(day(2026, 11, 15)))

        val yearly = PaySchedule(PayFrequency.Yearly, anchor = day(2025, 3, 1))
        assertEquals(BudgetPeriod(day(2026, 3, 1), day(2027, 2, 28)), yearly.period(day(2026, 11, 15)))
    }

    @Test
    fun scheduleValidation() {
        assertNull(PaySchedule(PayFrequency.Monthly, 25).issue)
        assertNotNull(PaySchedule(PayFrequency.Monthly, 0).issue)
        assertNotNull(PaySchedule(PayFrequency.TwiceMonthly, 15, 1).issue)
        assertNotNull(PaySchedule(PayFrequency.Weekly).issue)
        assertEquals("Los días 1 y 15", PaySchedule(PayFrequency.TwiceMonthly, 1, 15).summary)
        assertEquals(PayFrequency.TwiceMonthly, PayFrequency.of("twice_monthly"))
    }

    // Puedes gastar hoy, proyección y queda por presupuestar

    @Test
    fun periodInsights() {
        val period = BudgetPeriod(day(2026, 11, 1), day(2026, 11, 30))
        val budget = Budget(home, period, 200_000, limits = mapOf(food.id to 40_000, fun_.id to 20_000))
        val movements = listOf(
            spend(30_000, day(2026, 11, 3), food.id),
            spend(10_000, day(2026, 11, 9), fun_.id),
            spend(50_000, day(2026, 11, 9), fun_.id, excluded = true),
        )
        val report = BudgetReport(budget, period.range, listOf(food, fun_), movements)
        val insights = PeriodInsights(report, budget, day(2026, 11, 10))
        // 50 % + 30 % de 2.000 € = 1.600 € para gastar; llevas 400 €.
        assertEquals(160_000L, insights.spendable)
        assertEquals(120_000L, insights.left)
        assertEquals("del 10 al 30 son 21 días", 120_000L / 21, insights.perDay)
        assertEquals(21, insights.daysToPayday)
        assertEquals("400 € en 10 días son 1.200 € en 30", 120_000L, insights.projectedSpent)
        assertEquals(140_000L, insights.unbudgeted)
        // Pasado el periodo ya no queda nada por día.
        assertEquals(0L, PeriodInsights(report, budget, day(2026, 12, 2)).perDay)
    }

    // Arrastre

    @Test
    fun carryOver() {
        val october = BudgetPeriod(YearMonth.of(2026, 10))
        val november = BudgetPeriod(YearMonth.of(2026, 11))
        var budget = Budget(home, october, limits = mapOf(food.id to 40_000, fun_.id to 10_000), carryOver = true)
        val movements = listOf(
            spend(30_000, day(2026, 10, 5), food.id),
            spend(15_000, day(2026, 10, 6), fun_.id),
            spend(5_000, day(2026, 11, 2), food.id),
        )
        val previous = BudgetReport(budget, october.range, listOf(food, fun_), movements)
        val carried = BudgetCarryOver.amounts(previous)
        assertEquals("sobraron 100 €", 10_000L, carried[food.id])
        assertEquals("te pasaste 50 €", -5_000L, carried[fun_.id])

        budget = budget.copy(period = november)
        val report = BudgetReport(budget, november.range, listOf(food, fun_), movements, carried)
        assertEquals(50_000L, report.lines.first { it.category.id == food.id }.available)
        assertEquals(5_000L, report.lines.first { it.category.id == fun_.id }.available)
        // Sin arrastre activado no se suma nada.
        budget = budget.copy(carryOver = false)
        val plain = BudgetReport(budget, november.range, listOf(food, fun_), movements, carried)
        assertEquals(40_000L, plain.lines.first { it.category.id == food.id }.available)
        assertTrue(plain.carried.isEmpty())
    }

    // Presupuesto inteligente y vaciar límites

    @Test
    fun smartBudgetAndClear() {
        val schedule = PaySchedule.monthly(1)
        val november = schedule.period(day(2026, 11, 10))
        val previous = generateSequence(schedule.periodBefore(november)) { schedule.periodBefore(it) }.take(3).toList()
        assertEquals(listOf(10, 9, 8), previous.map { it.month.monthValue })
        val movements = listOf(
            spend(30_000, day(2026, 10, 5), food.id),
            spend(20_000, day(2026, 9, 5), food.id),
            spend(10_050, day(2026, 8, 5), food.id),
            spend(99_000, day(2026, 7, 5), food.id),
            spend(99_000, day(2026, 10, 7), food.id, excluded = true),
        )
        val limits = SmartBudget.suggestedLimits(movements, listOf(food), previous)
        assertEquals("media 200,17 € redondeada al euro de arriba", 20_100L, limits[food.id])

        val budget = Budget(home, november, limits = limits)
        assertTrue(budget.cleared().limits.isEmpty())
        assertNotNull(Budget(home, november, warnPercent = 40).issue)
    }

    // Aviso configurable

    @Test
    fun configurableWarning() {
        val period = BudgetPeriod(day(2026, 11, 15), day(2026, 11, 30))
        val movements = listOf(spend(7_000, day(2026, 11, 16), food.id))
        var budget = Budget(home, period, limits = mapOf(food.id to 10_000), warnPercent = 90)
        var report = BudgetReport(budget, period.range, listOf(food), movements)
        assertTrue("al 70 % no avisa si el aviso está al 90 %", BudgetAlertPlanner.alerts(report).none { food.id in it.id })
        budget = budget.copy(warnPercent = 60)
        report = BudgetReport(budget, period.range, listOf(food), movements)
        val alert = BudgetAlertPlanner.alerts(report).first { food.id in it.id }
        assertEquals("${BudgetAlertPlanner.PREFIX}2026-11-15.${food.id}.60", alert.id)
    }

    // Presupuestos extra

    @Test
    fun extraBudgetSpent() {
        val travel = BudgetCategory("travel", home, "Viajes", CategoryKind.Expense, BudgetGroup.Wants)
        val card = "card"
        val extra = ExtraBudget(
            "x", home, " Vacaciones ", 80_000, day(2026, 12, 1), day(2026, 12, 15),
            categoryIds = listOf(travel.id, food.id), accountIds = listOf(card),
        )
        val movements = listOf(
            spend(30_000, day(2026, 12, 2), travel.id, accountId = card),
            spend(5_000, day(2026, 12, 3), food.id, accountId = card),
            spend(5_000, day(2026, 12, 3), food.id),
            spend(9_000, day(2026, 12, 20), travel.id, accountId = card),
            spend(9_000, day(2026, 12, 4), travel.id, excluded = true, accountId = card),
        )
        assertEquals(35_000L, extra.spent(movements, listOf(travel, food)))
        assertNull(extra.issue)
        assertEquals("Vacaciones", extra.trimmedName)
        assertNotNull(ExtraBudget("y", home, "X", 0, day(2026, 12, 1)).issue)
    }

    @Test
    fun inMemoryScheduleAndExtras() = runBlocking {
        val backend = InMemoryFinance()
        assertNull(backend.paySchedule())
        backend.savePaySchedule(PaySchedule(PayFrequency.TwiceMonthly, 1, 15))
        assertEquals(PayFrequency.TwiceMonthly, backend.paySchedule()?.frequency)

        val period = BudgetPeriod(day(2026, 11, 15), day(2026, 11, 30))
        backend.saveBudget(Budget(home, period, carryOver = true))
        assertEquals(true, backend.budget(home, day(2026, 11, 15))?.carryOver)
        assertEquals(period, backend.latestBudget(home, day(2026, 12, 1))?.period)

        backend.saveExtraBudget(ExtraBudget("a", home, "A", 100, day(2026, 11, 1), isFavorite = true))
        val b = backend.saveExtraBudget(ExtraBudget("b", home, "B", 100, day(2026, 11, 1), isFavorite = true))
        assertEquals(listOf(b.id), backend.extraBudgets(home).filter { it.isFavorite }.map { it.id })
        backend.deleteExtraBudget(b.id)
        assertEquals(listOf("A"), backend.extraBudgets(home).map { it.name })
    }
}
