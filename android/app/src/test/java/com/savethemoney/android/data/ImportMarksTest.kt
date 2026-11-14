package com.savethemoney.android.data

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate

class ImportMarksTest {
    private fun row(line: Int, amount: Long, text: String) = CsvImportRow(line, MovementDraft("banco", "cat", LocalDate.of(2026, 10, line), amount, text))
    private val rows = listOf(row(1, -1299, "NETFLIX  com"), row(2, -6420, "Supermercado"), row(3, 215000, "Nómina"), row(4, -1299, "netflix com"), row(5, -4000, "Luz"))
    private val marks = mapOf(1 to ImportMark.Subscription, 2 to ImportMark.Card, 3 to ImportMark.Recurring, 4 to ImportMark.Recurring, 5 to ImportMark.Recurring)

    @Test fun cardPurchasesMoveToTheCardAccount() {
        val drafts = ImportMarks.drafts(rows, marks, "visa")
        assertEquals(listOf("banco", "visa", "banco", "banco", "banco"), drafts.map { it.accountId })
        assertEquals(listOf("banco", "banco", "banco", "banco", "banco"), ImportMarks.drafts(rows, marks, null).map { it.accountId })
    }

    @Test fun marksCreateMonthlySeriesWithoutDuplicates() {
        val existing = listOf(RecurringSeries("x", "h", "Luz ", RecurringKind.Essential, 5000, startsOn = "2026-01-01"))
        val created = ImportMarks.series(rows, marks, existing, "h")
        // La nómina es un ingreso, la segunda Netflix repite nombre y la luz ya existía.
        assertEquals(1, created.size)
        val s = created.single()
        assertEquals(listOf("NETFLIX  com", "1299", "Subscription", "2026-10-01", "banco", "cat", "1", "Month"),
            listOf(s.name, "${s.amountMinor}", "${s.kind}", s.startsOn, s.accountId, s.categoryId, "${s.remindDaysBefore}", "${s.unit}"))
    }

    @Test fun recurringIsEssentialAndSubscriptionIsSubscription() {
        val created = ImportMarks.series(rows, marks, emptyList(), "h")
        assertEquals(listOf("NETFLIX  com" to RecurringKind.Subscription, "Luz" to RecurringKind.Essential), created.map { it.name to it.kind })
    }

    @Test fun archivedSeriesDoNotBlockANewOne() {
        val archived = listOf(RecurringSeries("x", "h", "Luz", RecurringKind.Essential, 5000, startsOn = "2026-01-01", archivedAt = "2026-02-01T00:00:00Z"))
        assertEquals(listOf("NETFLIX  com", "Luz"), ImportMarks.series(rows, marks, archived, "h").map { it.name })
    }
}
