package com.savethemoney.android.data

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

class PaymentCalendarTest {
    private val day = LocalDate.of(2026, 11, 14)
    private val netflix = RecurringSeries("n", "h", "Netflix", RecurringKind.Subscription, 1299, startsOn = "2026-01-14")
    private val rent = RecurringSeries("r", "h", "Alquiler", RecurringKind.Essential, 80000, startsOn = "2026-01-01")
    private val salary = RecurringSeries("s", "h", "Nómina", RecurringKind.Income, 215000, startsOn = "2026-01-28")
    private val old = RecurringSeries("o", "h", "Gimnasio", RecurringKind.Essential, 3000, startsOn = "2026-01-14", archivedAt = "2026-06-01T00:00:00Z")
    private val plan = InvestmentPlan("p", "h", "f", amountMinor = 5000, startsOn = "2026-03-14")
    private val paused = InvestmentPlan("q", "h", "f", amountMinor = 9000, startsOn = "2026-03-14", pausedAt = "2026-05-01T00:00:00Z")
    private val calendar = PaymentCalendar(listOf(netflix, rent, salary, old), emptyList(), listOf(plan, paused)) { if (it == "f") "Fondo" else "?" }

    @Test fun monthHasEveryActivePaymentWithSign() {
        val nov = calendar.month(YearMonth.of(2026, 11))
        assertEquals(
            listOf(
                Triple(1, "Alquiler", -80000L), Triple(14, "Fondo", -5000L), Triple(14, "Netflix", -1299L), Triple(28, "Nómina", 215000L),
            ),
            nov.map { Triple(it.day.dayOfMonth, it.name, it.amount) },
        )
        assertEquals(listOf("Esencial", "Inversión", "Suscripción", "Ingreso"), nov.map { it.source })
    }

    @Test fun upcomingStartsTheDayAfterAndStopsAtTen() {
        val next = calendar.upcoming(day)
        assertEquals(10, next.size)
        assertEquals(LocalDate.of(2026, 11, 28), next.first().day)
        assertEquals(next.sortedBy { it.day }, next)
    }
}
