package com.savethemoney.android.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.ChronoUnit
import kotlin.math.roundToLong

// Recurring.swift, Goals.swift, Reminders.swift y la parte flexible de Tracking.swift de STMCore.

@Serializable
enum class RecurringKind(val title: String) {
    @SerialName("subscription") Subscription("Suscripción"),
    @SerialName("essential") Essential("Esencial"),
    @SerialName("income") Income("Ingreso"),
}

@Serializable
enum class RecurrenceUnit { @SerialName("week") Week, @SerialName("month") Month, @SerialName("year") Year }

data class Recurrence(val every: Int = 1, val unit: RecurrenceUnit = RecurrenceUnit.Month) {
    val title: String get() = when {
        unit == RecurrenceUnit.Week && every == 1 -> "Cada semana"
        unit == RecurrenceUnit.Week -> "Cada $every semanas"
        unit == RecurrenceUnit.Month && every == 1 -> "Cada mes"
        unit == RecurrenceUnit.Month && every == 3 -> "Cada trimestre"
        unit == RecurrenceUnit.Month && every == 6 -> "Cada semestre"
        unit == RecurrenceUnit.Month -> "Cada $every meses"
        every == 1 -> "Cada año"
        else -> "Cada $every años"
    }

    /** El cargo número [n] (0 es el primero): los mensuales se cuentan desde el primero para que un 31 no se quede en 28. */
    fun occurrence(n: Int, start: LocalDate): LocalDate = when (unit) {
        RecurrenceUnit.Week -> start.plusDays(7L * every * n)
        RecurrenceUnit.Month -> start.plusMonths(every.toLong() * n)
        RecurrenceUnit.Year -> start.plusMonths(12L * every * n)
    }

    val perYear: Double get() = when (unit) {
        RecurrenceUnit.Week -> 52.0 / every
        RecurrenceUnit.Month -> 12.0 / every
        RecurrenceUnit.Year -> 1.0 / every
    }

    companion object {
        val Monthly = Recurrence()
        val Common = listOf(
            Recurrence(1, RecurrenceUnit.Week), Recurrence(2, RecurrenceUnit.Week), Monthly, Recurrence(2), Recurrence(3), Recurrence(6),
            Recurrence(1, RecurrenceUnit.Year),
        )
    }
}

/** Pago o ingreso que se repite; se comparte con todo el hogar. `amountMinor` siempre en positivo. */
@Serializable
data class RecurringSeries(
    val id: String,
    @SerialName("household_id") val householdId: String,
    val name: String,
    val kind: RecurringKind = RecurringKind.Subscription,
    @SerialName("amount_minor") val amountMinor: Long,
    @SerialName("account_id") val accountId: String? = null,
    @SerialName("category_id") val categoryId: String? = null,
    val every: Int = 1,
    val unit: RecurrenceUnit = RecurrenceUnit.Month,
    @SerialName("starts_on") val startsOn: String,
    @SerialName("ends_on") val endsOn: String? = null,
    @SerialName("remind_days_before") val remindDaysBefore: Int? = 1,
    @SerialName("archived_at") val archivedAt: String? = null,
    @SerialName("intro_amount_minor") val introMinor: Long? = null,
    @SerialName("intro_charges") val introCharges: Int? = null,
) {
    val isArchived: Boolean get() = archivedAt != null
    val hasIntro: Boolean get() = introMinor != null && (introCharges ?: 0) > 0
    val trimmedName: String get() = name.trim()
    val recurrence: Recurrence get() = Recurrence(every, unit)
    val startDay: LocalDate get() = LocalDate.parse(startsOn.take(10))
    val endDay: LocalDate? get() = endsOn?.let { LocalDate.parse(it.take(10)) }

    /** Lo que se cobra un día de cargo concreto: la oferta o el precio normal. */
    fun amountOn(due: LocalDate): Long {
        if (!hasIntro) return amountMinor
        val n = maxOf(0, occurrences(startDay, due).size - 1)
        return if (n < (introCharges ?: 0)) introMinor ?: amountMinor else amountMinor
    }

    val introEndsOn: LocalDate? get() = if (hasIntro) recurrence.occurrence((introCharges ?: 1) - 1, startDay) else null

    fun isIntro(due: LocalDate): Boolean = introEndsOn?.let { !due.isAfter(it) } ?: false

    /** Lo que supone al mes en promedio (una cuota anual de 120 € son 10 € al mes). */
    val monthlyAmount: Long get() = (amountMinor * recurrence.perYear / 12).roundToLong()

    /** Lo que supone al mes desde ese día: con la oferta si el próximo cargo aún va a precio de oferta. */
    fun monthlyAmount(day: LocalDate): Long {
        val next = nextDue(day)
        val intro = introMinor
        if (!hasIntro || next == null || !isIntro(next) || intro == null) return monthlyAmount
        return (intro * recurrence.perYear / 12).roundToLong()
    }

    val issue: String? get() {
        val end = endDay
        val days = remindDaysBefore
        val intro = introMinor
        val charges = introCharges
        return when {
            trimmedName.isEmpty() -> "Ponle un nombre."
            trimmedName.length > 60 -> "El nombre es demasiado largo."
            amountMinor <= 0 -> "El importe tiene que ser mayor que cero."
            every !in 1..52 -> "La frecuencia no es válida."
            end != null && end.isBefore(startDay) -> "No puede terminar antes de empezar."
            days != null && days !in 0..14 -> "El aviso puede ser de 0 a 14 días antes."
            (intro == null) != (charges == null) -> "Indica el precio de oferta y cuántos cargos dura."
            intro != null && intro <= 0 -> "El precio de oferta tiene que ser mayor que cero."
            charges != null && charges !in 1..36 -> "La oferta puede durar de 1 a 36 cargos."
            else -> null
        }
    }

    /** Días de cargo entre dos fechas, ambas incluidas. */
    fun occurrences(from: LocalDate, through: LocalDate): List<LocalDate> {
        val last = endDay?.let { minOf(it, through) } ?: through
        if (from.isAfter(last)) return emptyList()
        var n = firstIndex(from)
        val result = mutableListOf<LocalDate>()
        while (true) {
            val day = recurrence.occurrence(n, startDay)
            if (day.isAfter(last)) break
            if (!day.isBefore(from)) result += day
            n++
        }
        return result
    }

    /** El próximo cargo desde ese día (incluido), si la serie no ha terminado. */
    fun nextDue(day: LocalDate): LocalDate? {
        val n = firstIndex(day)
        for (i in n..n + 2) {
            val due = recurrence.occurrence(i, startDay)
            if (!due.isBefore(day)) return if (endDay?.let { due.isAfter(it) } == true) null else due
        }
        return null
    }

    /** Estimación por debajo del índice del primer cargo en o después de [day], para no recorrer años uno a uno. */
    private fun firstIndex(day: LocalDate): Int {
        if (!day.isAfter(startDay)) return 0
        val estimate = when (unit) {
            RecurrenceUnit.Week -> ChronoUnit.DAYS.between(startDay, day).toInt() / (7 * every)
            else -> {
                val months = (day.year - startDay.year) * 12 + (day.monthValue - startDay.monthValue)
                months / if (unit == RecurrenceUnit.Month) every else 12 * every
            }
        }
        return maxOf(0, estimate - 1)
    }
}

/** Un cargo concreto que está por venir. */
data class UpcomingCharge(val series: RecurringSeries, val due: LocalDate) {
    val amount: Long get() = series.amountOn(due)
}

/** Cargos de las series activas entre hoy y dentro de [days] días, por fecha. */
fun List<RecurringSeries>.upcoming(today: LocalDate, days: Long = 30): List<UpcomingCharge> =
    filter { !it.isArchived }
        .flatMap { s -> s.occurrences(today, today.plusDays(days)).map { UpcomingCharge(s, it) } }
        .sortedWith(compareBy({ it.due }, { it.series.name }))

/** Lo que suman al mes las series activas de ese tipo. */
fun List<RecurringSeries>.monthlyTotal(kind: RecurringKind, day: LocalDate): Long =
    filter { !it.isArchived && it.kind == kind && it.endDay?.isBefore(day) != true }.sumOf { it.monthlyAmount(day) }

@Serializable
enum class GoalKind { @SerialName("savings") Savings, @SerialName("debt") Debt }

/** Meta del hogar: juntar una cantidad o terminar de pagar una deuda; las dos se llevan igual. */
@Serializable
data class Goal(
    val id: String,
    @SerialName("household_id") val householdId: String,
    val name: String,
    val kind: GoalKind = GoalKind.Savings,
    @SerialName("target_minor") val targetMinor: Long,
    @SerialName("starting_minor") val startingMinor: Long = 0,
    @SerialName("monthly_plan_minor") val monthlyPlanMinor: Long? = null,
    @SerialName("target_on") val targetOn: String? = null,
    @SerialName("account_id") val accountId: String? = null,
    val icon: String? = null,
    @SerialName("completed_at") val completedAt: String? = null,
    @SerialName("archived_at") val archivedAt: String? = null,
) {
    val isArchived: Boolean get() = archivedAt != null
    val trimmedName: String get() = name.trim()
    val targetDay: LocalDate? get() = targetOn?.let { LocalDate.parse(it.take(10)) }

    val issue: String? get() = when {
        trimmedName.isEmpty() -> "Ponle un nombre a la meta."
        trimmedName.length > 60 -> "El nombre es demasiado largo."
        targetMinor <= 0 -> if (kind == GoalKind.Debt) "Indica cuánto se debe." else "Indica cuánto quieres juntar."
        startingMinor < 0 -> "Lo que ya tienes no puede ser negativo."
        monthlyPlanMinor != null && monthlyPlanMinor < 0 -> "La aportación mensual no puede ser negativa."
        else -> null
    }
}

/** Dinero que se mete en una meta (o se saca, si es negativo). */
@Serializable
data class GoalContribution(
    val id: String,
    @SerialName("household_id") val householdId: String,
    @SerialName("goal_id") val goalId: String,
    @SerialName("amount_minor") val amountMinor: Long,
    @SerialName("made_on") val madeOn: String,
    val note: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
) {
    val day: LocalDate get() = LocalDate.parse(madeOn.take(10))

    val issue: String? get() = when {
        amountMinor == 0L -> "El importe no puede ser cero."
        note != null && note.length > 200 -> "La nota es demasiado larga."
        else -> null
    }
}

/** Cómo va una meta hoy y cuándo se alcanzará a este ritmo. */
class GoalProgress(val goal: Goal, contributions: List<GoalContribution>, today: LocalDate) {
    val saved: Long
    val remaining: Long

    /** Lo que se aporta al mes: lo previsto o, si no hay, la media de los últimos 3 meses. */
    val monthlyPace: Long?
    val monthsLeft: Int?
    val projectedMonth: YearMonth?

    /** Lo que habría que aportar al mes para llegar a la fecha objetivo. */
    val neededMonthly: Long?

    val fraction: Float get() = if (goal.targetMinor > 0) (saved.toDouble() / goal.targetMinor).coerceIn(0.0, 1.0).toFloat() else 0f
    val isReached: Boolean get() = remaining == 0L
    val isOnTrack: Boolean? get() = if (neededMonthly != null && monthlyPace != null) monthlyPace >= neededMonthly else null

    init {
        val own = contributions.filter { it.goalId == goal.id }
        saved = goal.startingMinor + own.sumOf { it.amountMinor }
        remaining = maxOf(0, goal.targetMinor - saved)

        val thisMonth = YearMonth.from(today)
        val plan = goal.monthlyPlanMinor
        monthlyPace = if (plan != null && plan > 0) {
            plan
        } else {
            val from = thisMonth.minusMonths(3).atDay(1)
            val total = own.filter { !it.day.isBefore(from) && it.day.isBefore(thisMonth.atDay(1)) }.sumOf { it.amountMinor }
            if (total > 0) (total + 2) / 3 else null
        }

        when {
            remaining == 0L -> {
                monthsLeft = 0
                projectedMonth = thisMonth
            }
            monthlyPace != null && monthlyPace > 0 -> {
                val months = ((remaining + monthlyPace - 1) / monthlyPace).toInt()
                monthsLeft = months
                projectedMonth = thisMonth.plusMonths(months.toLong())
            }
            else -> {
                monthsLeft = null
                projectedMonth = null
            }
        }

        val target = goal.targetDay
        neededMonthly = if (target != null && remaining > 0) {
            val end = YearMonth.from(target)
            val months = maxOf(1, (end.year - thisMonth.year) * 12 + (end.monthValue - thisMonth.monthValue))
            (remaining + months - 1) / months
        } else {
            null
        }
    }
}

/** Presupuesto flexible: de lo que entra se apartan fijos y ahorro; lo que queda es un solo número. */
class FlexBudget(report: BudgetReport, series: List<RecurringSeries>, today: LocalDate) {
    val income: Long = report.base
    val savings: Long = report.groups.firstOrNull { it.group == BudgetGroup.Savings }?.allocated ?: 0
    val fixed: Long
    val fixedSpent: Long
    val flexibleSpent: Long
    val daysLeft: Int

    val flexible: Long get() = income - fixed - savings
    val remaining: Long get() = flexible - flexibleSpent
    val perDay: Long? get() = if (daysLeft > 0 && remaining > 0) remaining / daysLeft else null

    init {
        val start = report.period.start
        val active = series.filter { !it.isArchived && it.kind != RecurringKind.Income }
        fixed = active.monthlyTotal(RecurringKind.Subscription, start) + active.monthlyTotal(RecurringKind.Essential, start)
        val fixedCategories = active.mapNotNull { it.categoryId }.toSet()
        var fijo = 0L
        var flexibleTotal = report.uncategorized
        for (line in report.lines) {
            when {
                line.category.id in fixedCategories -> fijo += line.spent
                // El ahorro va aparte; las categorías sin grupo ya están en uncategorized.
                line.category.budgetGroup == BudgetGroup.Savings || line.category.budgetGroup == null -> Unit
                else -> flexibleTotal += line.spent
            }
        }
        fixedSpent = fijo
        flexibleSpent = flexibleTotal
        daysLeft = if (today in report.period) ChronoUnit.DAYS.between(today, report.period.endInclusive).toInt() + 1 else 0
    }
}

/** Aviso local de un pago; el mismo cargo da siempre el mismo id, así que reprogramar no duplica. */
@Serializable
data class PlannedReminder(val id: String, val fireOn: String, val hour: Int, val title: String, val body: String)

object ReminderPlanner {
    const val PREFIX = "stm.recurring."

    fun plan(series: List<RecurringSeries>, today: LocalDate, horizonDays: Long = 45, limit: Int = 50, hour: Int = 9): List<PlannedReminder> {
        val end = today.plusDays(horizonDays)
        val result = mutableListOf<PlannedReminder>()
        for (item in series) {
            if (item.isArchived) continue
            val before = item.remindDaysBefore ?: continue
            for (due in item.occurrences(today, end.plusDays(before.toLong()))) {
                val fire = due.minusDays(before.toLong())
                if (fire.isBefore(today) || fire.isAfter(end)) continue
                result += PlannedReminder("$PREFIX${item.id}.$due", fire.toString(), hour, title(item, before), body(item, due))
            }
        }
        return result.sortedWith(compareBy({ it.fireOn }, { it.id })).take(limit)
    }

    private fun title(series: RecurringSeries, daysBefore: Int): String {
        val time = when (daysBefore) {
            0 -> "Hoy"
            1 -> "Mañana"
            else -> "En $daysBefore días"
        }
        return "$time: ${series.trimmedName}"
    }

    private fun body(series: RecurringSeries, due: LocalDate): String {
        val verb = if (series.kind == RecurringKind.Income) "Se ingresan" else "Se cobran"
        val change = if (series.introEndsOn == due) " Es el último cargo con precio de oferta; después serán ${Money.format(series.amountMinor)}." else ""
        return "$verb ${Money.format(series.amountOn(due))} el ${due.dayOfMonth} de ${MESES[due.monthValue - 1]}.$change"
    }

    internal val MESES = listOf("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre")
}

/** Aviso de que una categoría o grupo llega al 80 % o se pasa; el id es estable por mes y umbral. */
data class BudgetAlert(val id: String, val title: String, val body: String)

object BudgetAlertPlanner {
    private const val PREFIX = "stm.budget."

    fun alerts(report: BudgetReport, month: YearMonth): List<BudgetAlert> {
        val porCategoria = report.lines.mapNotNull { line ->
            val limit = line.limit?.takeIf { it > 0 } ?: return@mapNotNull null
            alert("$PREFIX$month.${line.category.id}", line.category.name, line.spent, limit)
        }
        val porGrupo = report.groups.filter { it.allocated > 0 && it.group != BudgetGroup.Savings }.mapNotNull {
            alert("$PREFIX$month.${it.group.name.lowercase()}", it.group.title, it.spent, it.allocated)
        }
        return porCategoria + porGrupo
    }

    private fun alert(id: String, name: String, spent: Long, limit: Long): BudgetAlert? {
        val percent = spent * 100 / limit
        val s = Money.format(spent)
        val l = Money.format(limit)
        return when {
            percent >= 100 -> BudgetAlert("$id.100", "Te has pasado en $name", "Llevas $s de $l este mes.")
            percent >= 80 -> BudgetAlert("$id.80", "$name: ya llevas el $percent %", "Has gastado $s de $l. Quedan ${Money.format(limit - spent)}.")
            else -> null
        }
    }
}

/** Avisos del dispositivo. No pasan por ningún servidor. */
interface Notifier {
    /** Interruptor general de Más opciones. */
    var enabled: Boolean

    /** Sustituye los avisos pendientes cuyo id empieza por [prefix]; sin prefijo, todos. */
    fun replaceReminders(reminders: List<PlannedReminder>, prefix: String = "")
    fun budgetAlerts(alerts: List<BudgetAlert>)
}

object NoNotifier : Notifier {
    override var enabled = true
    override fun replaceReminders(reminders: List<PlannedReminder>, prefix: String) = Unit
    override fun budgetAlerts(alerts: List<BudgetAlert>) = Unit
}
