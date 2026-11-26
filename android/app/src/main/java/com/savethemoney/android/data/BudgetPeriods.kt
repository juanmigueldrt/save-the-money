package com.savethemoney.android.data

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.ChronoUnit
import kotlin.math.ceil
import kotlin.math.roundToLong

// BudgetPeriods.swift de STMCore: día de cobro, periodos, «puedes gastar hoy», arrastre,
// presupuesto inteligente y presupuestos extra.

/** Cada cuánto cobra una persona. [raw] es el valor de la base de datos. */
enum class PayFrequency(val raw: String, val title: String) {
    Weekly("weekly", "Cada semana"),
    Biweekly("biweekly", "Cada dos semanas"),
    TwiceMonthly("twice_monthly", "Dos días al mes"),
    Monthly("monthly", "Cada mes"),
    Yearly("yearly", "Cada año");

    /** Si usa una fecha de cobro de referencia en vez de días del mes. */
    val usesAnchor: Boolean get() = this == Weekly || this == Biweekly || this == Yearly

    companion object {
        fun of(raw: String): PayFrequency? = entries.firstOrNull { it.raw == raw }
    }
}

/** Cuándo cobra una persona; de ahí salen sus periodos de presupuesto. Es privado de cada uno. */
data class PaySchedule(
    val frequency: PayFrequency = PayFrequency.Monthly,
    /** Día del mes (1–31; en meses más cortos, el último día). */
    val day1: Int = 1,
    /** Segundo día del mes, sólo con [PayFrequency.TwiceMonthly]. */
    val day2: Int? = null,
    /** Un día en que se cobró, para semanal, quincenal y anual. */
    val anchor: LocalDate? = null,
) {
    val issue: String? get() {
        if (day1 !in 1..31) return "El día de cobro tiene que estar entre 1 y 31."
        return when (frequency) {
            PayFrequency.TwiceMonthly ->
                if (day2 == null || day2 !in 1..31 || day2 <= day1) "El segundo día de cobro tiene que ir después del primero." else null
            PayFrequency.Weekly, PayFrequency.Biweekly, PayFrequency.Yearly -> if (anchor == null) "Elige un día en que hayas cobrado." else null
            PayFrequency.Monthly -> null
        }
    }

    /** Texto corto: "Cada mes, el día 25", "Los días 1 y 15", "Cada semana (lunes)". */
    val summary: String get() = when (frequency) {
        PayFrequency.Monthly -> if (day1 == 1) "Cada mes, desde el día 1" else "Cada mes, el día $day1"
        PayFrequency.TwiceMonthly -> "Los días $day1 y ${day2 ?: 15}"
        PayFrequency.Weekly -> "Cada semana" + (anchor?.let { " (${weekdayName(it)})" } ?: "")
        PayFrequency.Biweekly -> "Cada dos semanas" + (anchor?.let { " (${weekdayName(it)})" } ?: "")
        PayFrequency.Yearly -> "Cada año" + (anchor?.let { ", el ${it.dayOfMonth}/${it.monthValue}" } ?: "")
    }

    /** El periodo (de un cobro al día antes del siguiente) que contiene ese día. */
    fun period(day: LocalDate): BudgetPeriod {
        val start = lastPayday(day)
        return BudgetPeriod(start, nextPayday(start).minusDays(1))
    }

    fun periodAfter(p: BudgetPeriod): BudgetPeriod = period(p.end.plusDays(1))
    fun periodBefore(p: BudgetPeriod): BudgetPeriod = period(p.start.minusDays(1))

    /** El próximo cobro estrictamente después de ese día. */
    fun nextPayday(after: LocalDate): LocalDate = when (frequency) {
        PayFrequency.Weekly, PayFrequency.Biweekly -> {
            val step = if (frequency == PayFrequency.Weekly) 7L else 14L
            val base = anchor ?: after
            base.plusDays((Math.floorDiv(ChronoUnit.DAYS.between(base, after), step) + 1) * step)
        }
        PayFrequency.Yearly -> {
            val base = anchor ?: after
            val candidate = clamped(after.year, base.monthValue, base.dayOfMonth)
            if (candidate <= after) clamped(after.year + 1, base.monthValue, base.dayOfMonth) else candidate
        }
        PayFrequency.Monthly, PayFrequency.TwiceMonthly -> (0L..2L).firstNotNullOfOrNull { offset ->
            val key = YearMonth.from(after).plusMonths(offset)
            days.map { clamped(key.year, key.monthValue, it) }.firstOrNull { it > after }
        } ?: after.plusDays(1)
    }

    /** El último cobro ese día o antes. */
    fun lastPayday(onOrBefore: LocalDate): LocalDate = when (frequency) {
        PayFrequency.Weekly, PayFrequency.Biweekly -> {
            val step = if (frequency == PayFrequency.Weekly) 7L else 14L
            val base = anchor ?: onOrBefore
            base.plusDays(Math.floorDiv(ChronoUnit.DAYS.between(base, onOrBefore), step) * step)
        }
        PayFrequency.Yearly -> {
            val base = anchor ?: onOrBefore
            val candidate = clamped(onOrBefore.year, base.monthValue, base.dayOfMonth)
            if (candidate <= onOrBefore) candidate else clamped(onOrBefore.year - 1, base.monthValue, base.dayOfMonth)
        }
        PayFrequency.Monthly, PayFrequency.TwiceMonthly -> (0L..2L).firstNotNullOfOrNull { offset ->
            val key = YearMonth.from(onOrBefore).minusMonths(offset)
            days.reversed().map { clamped(key.year, key.monthValue, it) }.firstOrNull { it <= onOrBefore }
        } ?: onOrBefore
    }

    private val days: List<Int> get() = if (frequency == PayFrequency.TwiceMonthly) listOf(day1, day2 ?: 15).sorted() else listOf(day1)

    companion object {
        /** Mensual desde el día de inicio de mes del hogar (lo de antes de la fase C). */
        fun monthly(startDay: Int) = PaySchedule(PayFrequency.Monthly, startDay)

        /** Ese día del mes, o el último si el mes es más corto (31 de febrero → 28 o 29). */
        internal fun clamped(year: Int, month: Int, day: Int): LocalDate {
            val ym = YearMonth.of(year, month)
            return ym.atDay(minOf(day, ym.lengthOfMonth()))
        }

        private val WEEKDAYS = listOf("lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo")

        fun weekdayName(day: LocalDate): String = WEEKDAYS[day.dayOfWeek.value - DayOfWeek.MONDAY.value]
    }
}

/** Del día de cobro al día antes del siguiente (o unas fechas propias). */
class BudgetPeriod(start: LocalDate, end: LocalDate) : Comparable<BudgetPeriod> {
    val start: LocalDate = minOf(start, end)
    val end: LocalDate = maxOf(start, end)

    /** El mes natural. */
    constructor(month: YearMonth) : this(month.atDay(1), month.atEndOfMonth())

    val range: ClosedRange<LocalDate> get() = start..end
    val dayCount: Int get() = ChronoUnit.DAYS.between(start, end).toInt() + 1

    operator fun contains(day: LocalDate) = day in range

    /** El mes al que se asocia: el del último día (del 25-oct al 24-nov es «noviembre»). */
    val month: YearMonth get() = YearMonth.from(end)

    /** "Noviembre de 2026" si es un mes natural; si no, "25 oct – 24 nov". */
    val title: String get() {
        val natural = YearMonth.from(start)
        if (start.dayOfMonth == 1 && end == natural.atEndOfMonth()) return "${MESES[natural.monthValue - 1].replaceFirstChar { it.uppercase() }} de ${natural.year}"
        return "${dayMonth(start)} – ${dayMonth(end)}"
    }

    /** Días que quedan contando hoy (0 si ya pasó; todos si aún no empezó). */
    fun daysLeft(today: LocalDate): Int = when {
        today > end -> 0
        today < start -> dayCount
        else -> ChronoUnit.DAYS.between(today, end).toInt() + 1
    }

    /** Días que ya han pasado contando hoy (0 si aún no empezó; todos si ya acabó). */
    fun daysElapsed(today: LocalDate): Int = when {
        today < start -> 0
        today > end -> dayCount
        else -> ChronoUnit.DAYS.between(start, today).toInt() + 1
    }

    override fun compareTo(other: BudgetPeriod) = start.compareTo(other.start)
    override fun equals(other: Any?) = other is BudgetPeriod && other.start == start && other.end == end
    override fun hashCode() = start.hashCode() * 31 + end.hashCode()
    override fun toString() = "BudgetPeriod($start..$end)"

    companion object {
        private val MESES = listOf("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre")
        private val CORTOS = listOf("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic")

        /** "25 oct", sin depender del idioma del sistema. */
        fun dayMonth(day: LocalDate) = "${day.dayOfMonth} ${CORTOS[day.monthValue - 1]}"
    }
}

/** Cuánto puedes gastar hoy, cuánto falta para cobrar, la proyección del periodo y lo que queda por presupuestar. */
class PeriodInsights(report: BudgetReport, budget: Budget?, today: LocalDate) {
    /** Lo que se puede gastar en el periodo: necesidades + caprichos del reparto, más el arrastre. */
    val spendable: Long
    val spent: Long

    /** Lo que queda de lo gastable (negativo = te has pasado). */
    val left: Long

    /** Lo que queda dividido entre los días que faltan (0 si no queda nada). */
    val perDay: Long

    /** Días hasta el próximo cobro (el día siguiente al final del periodo). */
    val daysToPayday: Int

    /** Gasto previsto al final del periodo, al ritmo de hoy. */
    val projectedSpent: Long

    /** Ingresos previstos menos la suma de los límites (lo que aún no tiene destino). */
    val unbudgeted: Long

    init {
        val period = BudgetPeriod(report.period.start, report.period.endInclusive)
        val spending = report.groups.filter { it.group != BudgetGroup.Savings }
        val allocated = spending.sumOf { it.allocated }
        val carried = report.carried.values.sum()
        spent = spending.sumOf { it.spent } + report.uncategorized
        spendable = allocated + carried
        left = spendable - spent
        val remaining = period.daysLeft(today)
        perDay = if (remaining > 0 && left > 0) left / remaining else 0
        daysToPayday = maxOf(0, ChronoUnit.DAYS.between(today, period.end.plusDays(1)).toInt())
        val elapsed = maxOf(1, period.daysElapsed(today))
        projectedSpent = if (today > period.end) spent else (spent.toDouble() / elapsed * period.dayCount).roundToLong()
        unbudgeted = report.base - (budget?.limits?.values?.sum() ?: 0)
    }
}

object BudgetCarryOver {
    /**
     * Lo que pasa de un periodo al siguiente en cada categoría con límite: lo que sobró (positivo)
     * o lo que te pasaste (negativo), sumado a lo que ya venía arrastrado.
     */
    fun amounts(previous: BudgetReport): Map<String, Long> = previous.lines.mapNotNull { line ->
        val limit = line.limit ?: return@mapNotNull null
        val left = limit + (previous.carried[line.category.id] ?: 0) - line.spent
        if (left != 0L) line.category.id to left else null
    }.toMap()
}

object SmartBudget {
    /**
     * Límites propuestos: la media de lo gastado en cada categoría de gasto en los periodos dados
     * (normalmente los 3 anteriores), redondeada al euro de arriba. Las que no tuvieron gasto no salen.
     */
    fun suggestedLimits(movements: List<Movement>, categories: List<BudgetCategory>, periods: List<BudgetPeriod>): Map<String, Long> {
        if (periods.isEmpty()) return emptyMap()
        val expense = categories.filter { it.kind == CategoryKind.Expense }.map { it.id }.toSet()
        val totals = mutableMapOf<String, Long>()
        for (m in movements) {
            val id = m.categoryId ?: continue
            if (m.excluded || id !in expense || periods.none { m.day in it }) continue
            totals.merge(id, -m.amountMinor, Long::plus)
        }
        return totals.filterValues { it > 0 }.mapValues { (_, total) -> ceil(total.toDouble() / periods.size / 100).toLong() * 100 }
    }
}

/** Un presupuesto aparte del del periodo, con nombre, límite y fechas propias (p. ej. «Vacaciones»). */
data class ExtraBudget(
    val id: String,
    val householdId: String,
    val name: String = "",
    val limit: Long = 0,
    val startsOn: LocalDate,
    /** null = sin final. */
    val endsOn: LocalDate? = null,
    /** Vacías = todas las categorías de gasto / todas las cuentas. */
    val categoryIds: List<String> = emptyList(),
    val accountIds: List<String> = emptyList(),
    val isFavorite: Boolean = false,
    /**
     * Versión de la fila: el `updated_at` del servidor tal cual llegó (como [Movement.updatedAt]). Nulo en uno que aún no se
     * ha guardado: guardarlo es un alta.
     */
    val updatedAt: String? = null,
) {
    val trimmedName: String get() = name.trim()

    val issue: String? get() = when {
        trimmedName.isEmpty() -> "Ponle un nombre."
        trimmedName.length > 60 -> "El nombre es demasiado largo (máximo 60 caracteres)."
        limit <= 0 -> "El límite tiene que ser mayor que cero."
        endsOn != null && endsOn < startsOn -> "La fecha de fin no puede ser anterior a la de inicio."
        categoryIds.size > 50 || accountIds.size > 50 -> "Demasiadas categorías o cuentas."
        else -> null
    }

    /** Gasto que cuenta: dentro de las fechas, en sus categorías de gasto y cuentas, sin excluidos ni transferencias. */
    fun spent(movements: List<Movement>, categories: List<BudgetCategory>): Long {
        val kinds = categories.associate { it.id to it.kind }
        val categorySet = categoryIds.toSet()
        val accountSet = accountIds.toSet()
        var total = 0L
        for (m in movements) {
            if (m.excluded || m.day < startsOn || (endsOn != null && m.day > endsOn)) continue
            if (accountSet.isNotEmpty() && m.accountId !in accountSet) continue
            val kind = m.categoryId?.let(kinds::get)
            if (kind == CategoryKind.Transfer || kind == CategoryKind.Income) continue
            if (categorySet.isNotEmpty() && m.categoryId?.let { it in categorySet } != true) continue
            if (kind == null && m.amountMinor >= 0) continue
            total -= m.amountMinor
        }
        return total
    }
}
