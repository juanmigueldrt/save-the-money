package com.savethemoney.android.data

import java.time.LocalDate
import java.time.YearMonth

/** Un pago o ingreso previsto. `amount` con signo: negativo si sale dinero. */
data class CalendarPayment(val day: LocalDate, val name: String, val amount: Long, val source: String)

/** Calendario de pagos: pagos fijos y suscripciones, cargos de tarjeta y aportaciones de los planes de inversión. */
class PaymentCalendar(
    private val series: List<RecurringSeries>,
    /** Nombre de la tarjeta y su resumen, con los próximos cargos ya calculados. */
    private val cards: List<Pair<String, CreditCardSummary>>,
    private val plans: List<InvestmentPlan>,
    private val holdingName: (String) -> String,
) {
    /** Lo previsto entre dos fechas, ambas incluidas, por día y de mayor a menor gasto. */
    fun between(from: LocalDate, through: LocalDate): List<CalendarPayment> {
        val fixed = series.filter { !it.isArchived }.flatMap { s ->
            s.occurrences(from, through).map { day ->
                val amount = s.amountOn(day)
                CalendarPayment(day, s.trimmedName, if (s.kind == RecurringKind.Income) amount else -amount, s.kind.title)
            }
        }
        val card = cards.flatMap { (name, summary) ->
            summary.payments.filter { it.amount > 0 && !it.due.isBefore(from) && !it.due.isAfter(through) }
                .map { CalendarPayment(it.due, name, -it.amount, "Tarjeta de crédito") }
        }
        val invest = plans.filter { !it.isPaused && !it.isArchived }.flatMap { p ->
            p.occurrences(from, through).map { CalendarPayment(it, holdingName(p.holdingId), -p.amountMinor, "Inversión") }
        }
        return (fixed + card + invest).sortedWith(compareBy({ it.day }, { it.amount }, { it.name }))
    }

    fun month(month: YearMonth): List<CalendarPayment> = between(month.atDay(1), month.atEndOfMonth())

    /** Los [count] siguientes después de [day], sin contar los de ese día. */
    fun upcoming(day: LocalDate, count: Int = 10): List<CalendarPayment> = between(day.plusDays(1), day.plusYears(1)).take(count)
}
