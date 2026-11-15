package com.savethemoney.android.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.roundToLong

// PendingCharges.swift y WeeklySummary.swift de STMCore.
// Pagos fijos que se apuntan solos: al llegar el día de un cargo se crea un «pendiente»
// que no cuenta en saldos ni presupuesto hasta que lo confirmas. Si el cargo llega antes
// por CSV (o lo apuntas a mano), se empareja con ese movimiento y no se duplica.

@Serializable
enum class ChargeStatus { @SerialName("pending") Pending, @SerialName("confirmed") Confirmed, @SerialName("skipped") Skipped }

/** Un cargo concreto de un pago fijo. [amountMinor] con signo, como los movimientos: negativo es un gasto. */
@Serializable
data class RecurringCharge(
    val id: String = "",
    @SerialName("household_id") val householdId: String,
    @SerialName("series_id") val seriesId: String,
    @SerialName("due_on") val dueOn: String,
    @SerialName("amount_minor") val amountMinor: Long,
    val status: ChargeStatus = ChargeStatus.Pending,
    /** El movimiento que lo confirma. */
    @SerialName("transaction_id") val transactionId: String? = null,
) {
    val due: LocalDate get() = LocalDate.parse(dueOn.take(10))
    val isPending: Boolean get() = status == ChargeStatus.Pending
}

/** Un pendiente listo para enseñar: el cargo con su pago fijo. */
data class PendingCharge(val charge: RecurringCharge, val series: RecurringSeries) {
    val id: String get() = charge.id
}

object PendingCharges {
    /** Cuántos días hacia atrás se miran como mucho, para no llenar la lista de cargos viejos. */
    const val LOOKBACK_DAYS = 62L

    /** Margen de días entre el cargo previsto y el movimiento real para emparejarlos. */
    const val MATCH_WINDOW_DAYS = 5L

    /** Los cargos que han llegado (hasta hoy) y aún no están apuntados. */
    fun missing(series: List<RecurringSeries>, existing: List<RecurringCharge>, today: LocalDate): List<RecurringCharge> {
        val known = existing.map { "${it.seriesId}|${it.due}" }.toSet()
        val floor = today.minusDays(LOOKBACK_DAYS)
        val result = mutableListOf<RecurringCharge>()
        for (item in series) {
            if (item.isArchived || !item.createsPending) continue
            val from = maxOf(item.startDay, item.pendingDay ?: today, floor)
            for (due in item.occurrences(from, today)) {
                if ("${item.id}|$due" in known) continue
                val amount = item.amountOn(due)
                result += RecurringCharge(
                    householdId = item.householdId, seriesId = item.id, dueOn = due.toString(),
                    amountMinor = if (item.kind == RecurringKind.Income) amount else -amount,
                )
            }
        }
        return result.sortedWith(compareBy({ it.due }, { it.seriesId }))
    }

    /** Pendientes con su serie, del más antiguo al más nuevo. */
    fun pending(charges: List<RecurringCharge>, series: List<RecurringSeries>): List<PendingCharge> {
        val byId = series.associateBy { it.id }
        return charges.filter { it.isPending }
            .mapNotNull { charge -> byId[charge.seriesId]?.let { PendingCharge(charge, it) } }
            .sortedWith(compareBy({ it.charge.due }, { it.series.trimmedName }))
    }

    /**
     * Empareja cada pendiente con un movimiento que ya está apuntado: misma cuenta (si la serie
     * tiene cuenta), mismo signo, como mucho a [MATCH_WINDOW_DAYS] días y el mismo importe, o un
     * importe parecido (±25 %) si el concepto lleva el nombre del pago. Cada movimiento sirve
     * para un solo cargo, y los que ya confirman otro cargo no cuentan. Devuelve (cargo, movimiento).
     */
    fun matches(charges: List<RecurringCharge>, series: List<RecurringSeries>, movements: List<Movement>): List<Pair<String, String>> {
        val byId = series.associateBy { it.id }
        val used = charges.mapNotNull { it.transactionId }.toMutableSet()
        val result = mutableListOf<Pair<String, String>>()
        for (charge in charges.filter { it.isPending }.sortedBy { it.due }) {
            val item = byId[charge.seriesId] ?: continue
            val words = significantWords(item.trimmedName)
            fun distance(m: Movement) = abs(ChronoUnit.DAYS.between(charge.due, m.day))
            val candidates = movements.filter { m ->
                if (m.id in used || (m.amountMinor < 0) != (charge.amountMinor < 0) || distance(m) > MATCH_WINDOW_DAYS) return@filter false
                if (item.accountId != null && m.accountId != item.accountId) return@filter false
                if (m.amountMinor == charge.amountMinor) return@filter true
                val expected = abs(charge.amountMinor).toDouble()
                val actual = abs(m.amountMinor).toDouble()
                if (expected <= 0 || abs(actual - expected) / expected > 0.25 || words.isEmpty()) return@filter false
                val text = CsvMapping.normalize(m.description + " " + (m.payee ?: ""))
                words.any { text.contains(it) }
            }
            // Primero el mismo importe, después el día más cercano.
            val best = candidates.minWithOrNull(compareBy({ it.amountMinor != charge.amountMinor }, { distance(it) })) ?: continue
            used += best.id
            result += charge.id to best.id
        }
        return result
    }

    /** Palabras del nombre que sirven para reconocerlo (de 3 letras o más). */
    internal fun significantWords(name: String): List<String> =
        CsvMapping.normalize(name).split(Regex("[^\\p{L}\\p{N}]+")).filter { it.length >= 3 }
}

// MARK: - Resumen semanal: la última semana completa (de lunes a domingo) frente a la anterior,
// los gastos más grandes, las categorías que más suman y un mapa de calor por día de las
// últimas semanas. Cuenta como los informes: sin traspasos ni movimientos excluidos.

/** 0 = lunes … 6 = domingo. */
val LocalDate.weekdayIndex: Int get() = dayOfWeek.value - 1

/** El lunes de la semana de ese día. */
val LocalDate.startOfWeek: LocalDate get() = minusDays(weekdayIndex.toLong())

class WeeklySummary(
    movements: List<Movement>, categories: List<BudgetCategory>, today: LocalDate,
    includeCurrent: Boolean = false, heatmapWeeks: Int = 6,
) {
    data class Week(val start: LocalDate, val spent: Long, val income: Long) {
        val end: LocalDate get() = start.plusDays(6)
        val range: ClosedRange<LocalDate> get() = start..end
    }

    /** Un día del mapa de calor; [intensity] de 0 a 1 frente al día que más se gastó del mapa. */
    data class Day(val day: LocalDate, val spent: Long, val intensity: Double)

    val week: Week
    val previous: Week

    /** Hasta 5, de mayor a menor. */
    val biggest: List<Movement>

    /** Hasta 5 categorías de gasto de la semana. */
    val topCategories: List<SpendingReport.Row>

    /** Semanas del mapa (de la más antigua a la más reciente), cada una de lunes a domingo. */
    val heatmap: List<List<Day>>

    init {
        val start = if (includeCurrent) today.startOfWeek else today.startOfWeek.minusDays(7)
        fun makeWeek(monday: LocalDate): Week {
            val range = monday..monday.plusDays(6)
            return Week(
                monday, SpendingReport(movements, categories, range, ReportKind.Expense).total,
                SpendingReport(movements, categories, range, ReportKind.Income).total,
            )
        }
        week = makeWeek(start)
        previous = makeWeek(start.minusDays(7))

        val expenses = expenses(movements, categories)
        biggest = expenses.filter { it.day in week.range }
            .sortedWith(compareBy<Movement> { it.amountMinor }.thenByDescending { it.bookedOn }).take(5)
        topCategories = SpendingReport(movements, categories, week.range, ReportKind.Expense).byCategory.filter { it.amount > 0 }.take(5)

        val weeks = maxOf(1, heatmapWeeks)
        val firstMonday = start.minusDays(7L * (weeks - 1))
        val perDay = mutableMapOf<LocalDate, Long>()
        for (m in expenses) if (m.day in firstMonday..week.end) perDay[m.day] = (perDay[m.day] ?: 0L) - m.amountMinor
        val peak = maxOf(1L, perDay.values.maxOrNull() ?: 0L)
        heatmap = (0 until weeks).map { w ->
            (0 until 7).map { d ->
                val day = firstMonday.plusDays(7L * w + d)
                val spent = maxOf(0L, perDay[day] ?: 0L)
                Day(day, spent, spent.toDouble() / peak)
            }
        }
    }

    /** Diferencia de gasto con la semana anterior y su porcentaje (nulo si la anterior fue 0). */
    val change: Pair<Long, Long?> get() {
        val difference = week.spent - previous.spent
        if (previous.spent <= 0) return difference to null
        return difference to (difference.toDouble() / previous.spent * 100).roundToLong()
    }

    /** "10 nov – 16 nov". */
    val title: String get() = "${BudgetPeriod.dayMonth(week.start)} – ${BudgetPeriod.dayMonth(week.end)}"

    /** Frase de la comparación con la semana anterior. */
    val changeText: String get() {
        val percent = change.second ?: return if (previous.spent == 0L) "La semana anterior no hubo gastos." else ""
        return when {
            percent == 0L -> "Lo mismo que la semana anterior."
            percent > 0 -> "$percent % más que la semana anterior"
            else -> "${-percent} % menos que la semana anterior"
        }
    }

    /** Texto corto para el aviso del lunes. */
    val notificationBody: String get() {
        var text = "Gastaste ${Money.format(week.spent)}"
        val percent = change.second
        if (percent != null && percent != 0L) {
            text += if (percent > 0) ", un $percent % más que la semana anterior" else ", un ${-percent} % menos que la semana anterior"
        }
        topCategories.firstOrNull()?.let { text += ". Lo que más: ${it.title}" }
        return "$text."
    }

    companion object {
        /** Gastos de verdad: negativos, no excluidos, ni traspasos ni ingresos. */
        fun expenses(movements: List<Movement>, categories: List<BudgetCategory>): List<Movement> {
            val byId = categories.associateBy { it.id }
            return movements.filter { m ->
                if (m.excluded || m.amountMinor >= 0) return@filter false
                val category = m.categoryId?.let { byId[it] } ?: return@filter true
                category.kind == CategoryKind.Expense
            }
        }
    }
}

// MARK: - Avisos de hábito

/** Recordatorio para apuntar gastos y resumen semanal: se eligen en Más opciones y se guardan sólo en este dispositivo. */
data class HabitSettings(val logReminder: LogReminder = LogReminder.Off, val logHour: Int = 21, val weeklySummary: Boolean = true) {
    enum class LogReminder(val title: String) { Off("No"), Daily("Cada día"), Weekly("Los domingos") }

    fun plan(today: LocalDate): List<PlannedReminder> =
        (if (logReminder == LogReminder.Off) emptyList() else HabitReminderPlanner.logReminders(today, logHour, logReminder == LogReminder.Weekly)) +
            (if (weeklySummary) HabitReminderPlanner.weeklySummary(today) else emptyList())
}

object HabitReminderPlanner {
    /** Prefijo de los avisos de hábito (recordatorio para apuntar y resumen semanal). */
    const val PREFIX = "stm.habit."

    /** Recordatorio para apuntar gastos los próximos [days] días a esa hora (o sólo los domingos si [weekly]). */
    fun logReminders(today: LocalDate, hour: Int, weekly: Boolean, days: Int = 21): List<PlannedReminder> =
        (0 until days).mapNotNull { offset ->
            val day = today.plusDays(offset.toLong())
            if (weekly && day.weekdayIndex != 6) return@mapNotNull null
            PlannedReminder(
                "${PREFIX}log.$day", day.toString(), hour, "¿Has apuntado tus gastos?",
                if (weekly) "Tómate un minuto para repasar los gastos de la semana." else "Apunta lo que has gastado hoy; es un momento.",
            )
        }

    /** Aviso del resumen semanal los próximos lunes. */
    fun weeklySummary(today: LocalDate, hour: Int = 9, weeks: Int = 3): List<PlannedReminder> {
        val nextMonday = if (today.weekdayIndex == 0) today else today.startOfWeek.plusDays(7)
        return (0 until weeks).map { w ->
            val day = nextMonday.plusDays(7L * w)
            PlannedReminder("${PREFIX}weekly.$day", day.toString(), hour, "Tu resumen de la semana", "Mira en qué se fue el dinero la semana pasada.")
        }
    }
}
