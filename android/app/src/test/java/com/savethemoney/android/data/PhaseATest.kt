package com.savethemoney.android.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

/**
 * Fase A (PhaseATests.swift): calculadora, filtros, lista por días, vista de importes, ajuste de saldo,
 * total anual de pagos fijos, comparación de informes, predicción del patrimonio y renombrar hogar.
 */
class PhaseATest {
    private val home = "h"
    private fun day(y: Int, m: Int, d: Int) = LocalDate.of(y, m, d)

    // Calculadora

    @Test
    fun amountExpression() {
        assertEquals(1_850L, AmountExpression.evaluate("12,50+3×2"))
        assertEquals(1_850L, AmountExpression.evaluate("12.50 + 3*2"))
        assertEquals(3_000L, AmountExpression.evaluate("(10+5)×2"))
        assertEquals(3_333L, AmountExpression.evaluate("100/3"))
        assertEquals(250L, AmountExpression.evaluate("10÷4"))
        assertEquals(1_260L, AmountExpression.evaluate("20−7,40"))
        assertEquals(-300L, AmountExpression.evaluate("-5+2"))
        assertEquals(123_500L, AmountExpression.evaluate("1.234,56+0,44"))
        assertEquals(123_500L, AmountExpression.evaluate("1\u202F234,56+0,44"))
        assertNull(AmountExpression.evaluate("10/0"))
        assertNull(AmountExpression.evaluate("10+"))
        assertNull(AmountExpression.evaluate("(10+2"))
        assertNull(AmountExpression.evaluate("abc"))
        assertNull(AmountExpression.evaluate(""))
    }

    @Test
    fun enteredAmountAndOperationDetection() {
        assertEquals(1_250L, Money.entered("12,50"))
        assertEquals(3_240L, Money.entered("25+7,40"))
        assertEquals(-1_200L, Money.entered("-12"))
        assertNull(Money.entered("12,5x"))
        assertTrue(AmountExpression.hasOperation("25+7"))
        assertTrue(AmountExpression.hasOperation("(3)"))
        assertFalse(AmountExpression.hasOperation("-25"))
        assertFalse(AmountExpression.hasOperation("1.234,56"))
    }

    // Filtros y lista por días

    private val food = BudgetCategory("food", home, "Supermercado", CategoryKind.Expense)
    private val salary = BudgetCategory("salary", home, "Nómina", CategoryKind.Income)
    private val transfer = BudgetCategory("transfer", home, "Transferencia entre cuentas", CategoryKind.Transfer)
    private val categories = listOf(food, salary, transfer)
    private val movements = listOf(
        Movement("1", home, "a", food.id, "2026-11-14", -1_250, "MERCADONA"),
        Movement("2", home, "a", salary.id, "2026-11-01", 200_000, "NOMINA"),
        Movement("3", home, "a", transfer.id, "2026-11-14", -5_000, "A AHORRO"),
        Movement("4", home, "b", transfer.id, "2026-11-14", 5_000, "A AHORRO"),
        Movement("5", home, "b", null, "2026-10-20", -899, "CINE", notes = "con amigos"),
    )
    private val today = day(2026, 11, 15)

    private fun MovementFilter.run() = apply(movements, categories, today).map { it.description }

    @Test
    fun filterByAccountKindAndDates() {
        assertEquals(2, MovementFilter(accountId = "b").run().size)
        assertEquals(listOf("MERCADONA", "CINE"), MovementFilter(kind = MovementKindFilter.Expense).run())
        assertEquals(listOf("NOMINA"), MovementFilter(kind = MovementKindFilter.Income).run())
        assertEquals(2, MovementFilter(kind = MovementKindFilter.Transfer).run().size)
        assertEquals(4, MovementFilter(dates = MovementDateFilter.ThisMonth).run().size)
        assertEquals(listOf("CINE"), MovementFilter(dates = MovementDateFilter.LastMonth).run())
        val custom = MovementFilter(dates = MovementDateFilter.Custom, customFrom = day(2026, 11, 2), customThrough = day(2026, 10, 1))
        assertEquals(listOf("NOMINA", "CINE"), custom.run())
        assertEquals(3, MovementFilter(accountId = "a", kind = MovementKindFilter.Expense, dates = MovementDateFilter.ThisMonth).activeCount)
    }

    @Test
    fun searchByTextNotesCategoryAndAmount() {
        fun search(q: String) = MovementFilter(search = q).run()
        assertEquals(listOf("MERCADONA"), search("merca"))
        assertEquals(listOf("CINE"), search("amigos"))
        assertEquals(listOf("MERCADONA"), search("super"))
        assertEquals(listOf("MERCADONA"), search("12,50"))
        assertEquals(listOf("CINE"), search("8.99"))
        assertEquals(listOf("A AHORRO", "A AHORRO"), search("50"))
        assertEquals(listOf("A AHORRO"), search("-50"))
        assertEquals(listOf("NOMINA"), search("2000"))
    }

    @Test
    fun groupsByDayWithoutCountingTransfers() {
        val days = MovementDay.group(movements, categories)
        assertEquals(listOf(day(2026, 11, 14), day(2026, 11, 1), day(2026, 10, 20)), days.map { it.day })
        assertEquals(3, days[0].movements.size)
        assertEquals(-1_250L, days[0].total)
        assertEquals(200_000L, days[1].total)
    }

    // Vista de importes

    @Test
    fun displayOptions() {
        val money = 123_456L
        assertEquals("•••• €", Money.format(money, options = Money.Display(hidesAmounts = true)))
        assertEquals("1235", Money.format(money, options = Money.Display(roundsToUnits = true)).filter { it.isDigit() })
        assertEquals("123456", Money.format(money, options = Money.Display.Standard).filter { it.isDigit() })
        assertTrue(Money.format(money, signed = true, options = Money.Display.Standard).startsWith("+"))
        assertFalse(Money.format(money, signed = true, options = Money.Display(plusSign = false)).startsWith("+"))
        assertTrue(Money.format(-500, signed = true, options = Money.Display.Standard).startsWith(Money.MINUS.toString()))
        assertEquals("•••• €", Money.format(-500, signed = true, options = Money.Display(hidesAmounts = true)))

        val saved = Money.display
        try {
            Money.display = Money.Display(hidesAmounts = true, roundsToUnits = true)
            assertEquals("•••• €", Money.format(money))
            // El campo de texto nunca se oculta ni se redondea.
            assertEquals("1234,56", Money.input(money))
            Money.display = Money.Display.Standard
            assertNotEquals("•••• €", Money.format(money))
        } finally {
            Money.display = saved
        }
    }

    // Actualizar saldo

    @Test
    fun balanceAdjustment() {
        val account = Account("a", home, "Nómina")
        val draft = BalanceAdjustment.draft(account, 10_000, 9_250, today, categories)
        assertEquals(-750L, draft?.amountMinor)
        assertEquals(transfer.id, draft?.categoryId)
        assertEquals(BalanceAdjustment.DESCRIPTION, draft?.description)
        assertNull(draft?.issue)
        assertNull(BalanceAdjustment.draft(account, 10_000, 10_000, today, categories))
    }

    // Pagos fijos: total del año

    @Test
    fun yearlyTotalCountsIntroPriceAndEndDate() {
        val music = RecurringSeries("m", home, "Música", RecurringKind.Subscription, 1_199, startsOn = "2026-11-20", introMinor = 699, introCharges = 3)
        val gym = RecurringSeries("g", home, "Gimnasio", RecurringKind.Essential, 3_000, startsOn = "2026-01-05", endsOn = "2027-02-05")
        val pay = RecurringSeries("s", home, "Nómina", RecurringKind.Income, 200_000, startsOn = "2026-01-28")
        val total = listOf(music, gym, pay).yearlyTotal(setOf(RecurringKind.Subscription, RecurringKind.Essential), today)
        // Música: 3 × 6,99 + 9 × 11,99. Gimnasio: dic, ene, feb = 3 × 30.
        assertEquals(3 * 699L + 9 * 1_199L + 3 * 3_000L, total)
    }

    // Informes

    @Test
    fun previousRanges() {
        val t = day(2026, 3, 31)
        assertEquals(day(2026, 2, 1)..day(2026, 2, 28), ReportPeriod.ThisMonth.previousRange(t))
        assertEquals(day(2026, 1, 1)..day(2026, 1, 31), ReportPeriod.LastMonth.previousRange(t))
        assertEquals(day(2025, 10, 1)..day(2025, 12, 31), ReportPeriod.Last3Months.previousRange(t))
        assertEquals(day(2025, 1, 1)..day(2025, 3, 31), ReportPeriod.ThisYear.previousRange(t))
        assertEquals(day(2026, 2, 1)..day(2026, 2, 28), ReportPeriod.LastMonth.previousRange(day(2026, 4, 10)))
    }

    @Test
    fun averagePerDayAndChange() {
        val now = SpendingReport(movements, categories, day(2026, 11, 1)..day(2026, 11, 10))
        assertEquals(10, now.dayCount)
        val november = SpendingReport(movements, categories, day(2026, 11, 1)..day(2026, 11, 15))
        val october = SpendingReport(movements, categories, day(2026, 10, 1)..day(2026, 10, 15))
        assertEquals(1_250L, november.total)
        assertEquals(83L, november.averagePerDay)
        assertEquals(0L, october.total)
        assertNull(november.change(october).second)
        val late = SpendingReport(movements, categories, day(2026, 10, 1)..day(2026, 10, 31))
        val (difference, percent) = november.change(late)
        assertEquals(351L, difference)
        assertEquals(39L, percent)
    }

    // Patrimonio a final de año

    @Test
    fun netWorthProjection() {
        fun point(m: Int, net: Long) = NetWorthPoint(YearMonth.of(2026, m), net, 0)
        val projection = NetWorthProjection.of(listOf(point(8, 100_000), point(9, 110_000), point(10, 115_000), point(11, 130_000)))
        assertEquals(10_000L, projection?.monthlyChange)
        assertEquals(listOf(11, 12), projection?.points?.map { it.first.monthValue })
        assertEquals(140_000L, projection?.endOfYear)
        assertNull(NetWorthProjection.of(listOf(point(11, 1))))
        assertNull(NetWorthProjection.of(listOf(point(11, 1), point(12, 2))))
    }

    // Renombrar hogar

    @Test
    fun onlyOwnerRenamesHousehold() = runBlocking {
        val backend = InMemoryBackend()
        backend.signUp(Username.parse("ana").getOrThrow(), "contrasena-de-prueba", "Ana")
        val casa = backend.createHousehold("Casa")
        assertEquals("Piso nuevo", backend.renameHousehold(casa.id, "  Piso nuevo  ").name)
        assertEquals("Piso nuevo", backend.households().first().name)
        assertTrue(runCatching { backend.renameHousehold(casa.id, "   ") }.isFailure)

        val invite = backend.createInvite(casa.id)
        backend.signOut()
        backend.signUp(Username.parse("luis").getOrThrow(), "contrasena-de-prueba", "Luis")
        backend.acceptInvite(InviteCode.parse(invite.code)!!)
        assertTrue(runCatching { backend.renameHousehold(casa.id, "Mío") }.isFailure)
    }
}
