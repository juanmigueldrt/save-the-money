package com.savethemoney.android.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

/** Los mismos casos que TrackingTests.swift, para que Android e iOS calculen igual. Datos inventados. */
class TrackingTest {
    private val home = "home"
    private var n = 0

    private fun day(y: Int, m: Int, d: Int) = LocalDate.of(y, m, d)
    private fun account(id: String, opening: Long = 0, kind: AccountKind = AccountKind.Checking, archived: Boolean = false) =
        Account(id, home, id, kind, openingMinor = opening, archivedAt = if (archived) "2026-01-01T00:00:00Z" else null)
    private fun category(id: String, kind: CategoryKind = CategoryKind.Expense) = BudgetCategory(id, home, id, kind)
    private fun move(a: Account, minor: Long, on: LocalDate, c: BudgetCategory? = null) =
        Movement("m${n++}", home, a.id, c?.id, on.toString(), minor, "Movimiento")
    private fun score(value: Int, max: Int = 850, provider: String? = null) = CreditScore("s", value, max, provider, "2026-11-01")

    @Test fun netWorthNowAndHistory() {
        val checking = account("común", 100_000)
        val card = account("tarjeta", kind = AccountKind.CreditCard)
        val old = account("antigua", 9_999, archived = true)
        val accounts = listOf(checking, card, old)
        val movements = listOf(
            move(checking, 50_000, day(2026, 9, 28)),
            move(checking, -20_000, day(2026, 10, 15)),
            move(card, -30_000, day(2026, 11, 1)),
        )
        val now = NetWorth.current(accounts, mapOf(checking.id to 130_000L, card.id to -30_000L), day(2026, 11, 2))
        assertEquals(130_000, now.assets)
        assertEquals(30_000, now.liabilities)
        assertEquals(100_000, now.net)

        val history = NetWorth.history(accounts, movements, 3, YearMonth.of(2026, 11))
        assertEquals(listOf(YearMonth.of(2026, 9), YearMonth.of(2026, 10), YearMonth.of(2026, 11)), history.map { it.month })
        assertEquals(listOf(150_000L, 130_000L, 100_000L), history.map { it.net })
        assertEquals(30_000, history.last().liabilities)
    }

    @Test fun creditScoreRatingAndValidation() {
        assertEquals(CreditScore.Rating.Excellent, score(760).rating)
        assertEquals(CreditScore.Rating.Good, score(700).rating)
        assertEquals(CreditScore.Rating.Fair, score(600).rating)
        assertEquals(CreditScore.Rating.Poor, score(500).rating)
        assertEquals(CreditScore.Rating.Excellent, score(900, 1000).rating)
        assertNotNull(score(900).issue)
        assertNotNull(score(50, 50).issue)
        assertNull(score(720, provider = "  ").issue)
        assertNull(score(720, provider = "  ").trimmedProvider)
    }

    @Test fun invalidScoreIsRejectedByService() {
        assertThrows(Exception::class.java) { runBlocking { InMemoryFinance().addCreditScore(score(900)) } }
    }

    @Test fun spendingReport() {
        val a = account("común")
        val food = category("Supermercado")
        val fun_ = category("Ocio")
        val salary = category("Nómina", CategoryKind.Income)
        val transfer = category("Transferencia", CategoryKind.Transfer)
        val categories = listOf(food, fun_, salary, transfer)
        val movements = listOf(
            move(a, -6_000, day(2026, 9, 3), food),
            move(a, -3_000, day(2026, 10, 3), food),
            move(a, 500, day(2026, 10, 4), food),
            move(a, -1_500, day(2026, 10, 9), fun_),
            move(a, -1_000, day(2026, 10, 9)),
            move(a, 200_000, day(2026, 10, 28), salary),
            move(a, -50_000, day(2026, 10, 29), transfer),
            move(a, -9_999, day(2026, 8, 31), food),
        )
        val range = day(2026, 9, 1)..day(2026, 10, 31)
        val report = SpendingReport(movements, categories, range)
        assertEquals(11_000, report.total)
        assertEquals(listOf("Supermercado", "Ocio", "Sin categoría"), report.byCategory.map { it.title })
        assertEquals(8_500, report.byCategory.first().amount)
        assertEquals(3, report.byCategory.first().count)
        assertEquals(listOf(6_000L, 5_000L), report.byMonth.map { it.amount })
        assertEquals(5_500, report.averagePerMonth)
        assertEquals(1_500, SpendingReport(movements, categories, range, categoryIds = setOf(fun_.id)).total)
        assertEquals(200_000, SpendingReport(movements, categories, range, ReportKind.Income).total)

        assertEquals(day(2026, 2, 1)..day(2026, 2, 28), ReportPeriod.LastMonth.range(day(2026, 3, 15)))
        assertEquals(day(2026, 1, 1), ReportPeriod.ThisYear.range(day(2026, 3, 15)).start)
    }

    @Test fun biggestRiseComparesWithPreviousMonth() {
        val a = account("común")
        val food = category("Supermercado")
        val fun_ = category("Ocio")
        val movements = listOf(
            move(a, -10_000, day(2026, 10, 3), food),
            move(a, -15_000, day(2026, 11, 3), food),
            move(a, -1_000, day(2026, 11, 4), fun_),
        )
        assertEquals(BiggestRise("Supermercado", 50, YearMonth.of(2026, 10)), biggestRise(movements, listOf(food, fun_), YearMonth.of(2026, 11)))
        assertEquals(BiggestRise("Ocio", null, YearMonth.of(2026, 10)), biggestRise(movements.drop(2), listOf(food, fun_), YearMonth.of(2026, 11)))
        assertNull(biggestRise(movements.take(1), listOf(food, fun_), YearMonth.of(2026, 11)))
    }
}
