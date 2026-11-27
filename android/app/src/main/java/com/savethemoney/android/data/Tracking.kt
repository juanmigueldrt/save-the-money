package com.savethemoney.android.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.YearMonth
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.max

// Tracking.swift de STMCore: patrimonio neto, score crediticio e informes.

/** Lo que se tiene (saldos positivos) y lo que se debe (saldos negativos, en positivo). */
data class NetWorthPoint(val month: YearMonth, val assets: Long, val liabilities: Long) {
    val net: Long get() = assets - liabilities

    companion object {
        fun of(month: YearMonth, balances: List<Long>) =
            NetWorthPoint(month, balances.filter { it > 0 }.sum(), -balances.filter { it < 0 }.sum())
    }
}

object NetWorth {
    /** Patrimonio de hoy con los saldos actuales, sin las cuentas archivadas ni las que no cuentan en el patrimonio. */
    fun current(accounts: List<Account>, balances: Map<String, Long>, today: LocalDate): NetWorthPoint =
        NetWorthPoint.of(YearMonth.from(today), accounts.filter { !it.isArchived && it.includeInNetWorth }.map { balances[it.id] ?: it.openingMinor })

    /**
     * Patrimonio al final de cada uno de los últimos [months] meses, rehecho con el saldo inicial y los movimientos.
     *
     * Reglas (las mismas que en iOS, con vectores en `testdata/vectors/net_worth.json`):
     * - El saldo inicial cuenta desde el día de alta de la cuenta (`createdAt`), o desde su primer
     *   movimiento si es anterior (movimientos importados): es el saldo de antes de todos sus movimientos.
     *   Antes de eso la cuenta no existía y suma 0. Sin `createdAt` cuenta desde siempre.
     * - Una cuenta archivada sigue en los meses que terminan antes del día en que se archivó.
     * - Las inversiones no suman: su valor no es el saldo de ninguna cuenta, no hay precio de cada fin
     *   de mes y el dinero de una cartera puede estar ya en una cuenta de inversión (se contaría dos veces).
     */
    fun history(accounts: List<Account>, movements: List<AccountAmount>, months: Int, through: YearMonth): List<NetWorthPoint> {
        val counted = accounts.filter { it.includeInNetWorth }
        val byAccount = movements.groupBy { it.accountId }
        return (months - 1 downTo 0).map { offset ->
            val month = through.minusMonths(offset.toLong())
            val last = month.atEndOfMonth()
            NetWorthPoint.of(
                month,
                counted.mapNotNull { a ->
                    if (a.archivedAt != null && !localDay(a.archivedAt).isAfter(last)) return@mapNotNull null
                    val done = byAccount[a.id].orEmpty().filter { !it.day.isAfter(last) }
                    val opened = a.createdAt == null || !localDay(a.createdAt).isAfter(last)
                    if (!opened && done.isEmpty()) null else a.openingMinor + done.sumOf { it.amountMinor }
                },
            )
        }
    }

    /** Día en la zona del usuario de una marca de tiempo del servidor ("2026-11-02T10:00:00+00:00"). */
    private fun localDay(timestamp: String): LocalDate = OffsetDateTime.parse(timestamp).atZoneSameInstant(ZoneId.systemDefault()).toLocalDate()
}

/** Predicción del patrimonio hasta final de año: sigue el cambio medio mensual de los últimos meses. */
class NetWorthProjection private constructor(
    /** Cambio medio al mes que se ha usado. */
    val monthlyChange: Long,
    /** Un punto por mes, desde el último real (incluido) hasta diciembre. */
    val points: List<Pair<YearMonth, Long>>,
) {
    val endOfYear: Long get() = points.lastOrNull()?.second ?: 0

    companion object {
        /**
         * [history]: patrimonio a final de cada mes, del más antiguo al actual (el último es el mes en curso).
         * Se usan como mucho los últimos [maxChanges] cambios. Hacen falta al menos 2 puntos, y no se predice en diciembre.
         */
        fun of(history: List<NetWorthPoint>, maxChanges: Int = 6): NetWorthProjection? {
            val last = history.lastOrNull() ?: return null
            if (history.size < 2 || last.month.monthValue == 12) return null
            val recent = history.takeLast(maxChanges + 1)
            val average = Math.round((recent.last().net - recent.first().net).toDouble() / (recent.size - 1))
            val points = generateSequence(last.month) { it.plusMonths(1) }.takeWhile { it.year == last.month.year }
                .mapIndexed { i, month -> month to last.net + average * i }.toList()
            return NetWorthProjection(average, points)
        }
    }
}

/** Score apuntado a mano. Es personal: sólo lo ve quien lo apunta. */
@Serializable
data class CreditScore(
    val id: String,
    val score: Int,
    @SerialName("max_score") val maxScore: Int = 850,
    val provider: String? = null,
    @SerialName("recorded_on") val recordedOn: String,
    val note: String? = null,
) {
    enum class Rating { Excellent, Good, Fair, Poor }

    val day: LocalDate get() = LocalDate.parse(recordedOn.take(10))
    val fraction: Double get() = if (maxScore > 0) (score.toDouble() / maxScore).coerceIn(0.0, 1.0) else 0.0

    /** Tramos orientativos sobre la escala del proveedor (en 850: 740, 670 y 580). */
    val rating: Rating get() = when {
        fraction >= 0.87 -> Rating.Excellent
        fraction >= 0.79 -> Rating.Good
        fraction >= 0.68 -> Rating.Fair
        else -> Rating.Poor
    }

    val trimmedProvider: String? get() = provider?.trim()?.ifEmpty { null }

    val issue: String? get() = when {
        maxScore !in 100..1000 -> "La escala tiene que estar entre 100 y 1000."
        score < 0 || score > maxScore -> "El score tiene que estar entre 0 y $maxScore."
        (trimmedProvider?.length ?: 0) > 60 -> "El nombre del proveedor es demasiado largo."
        (note?.length ?: 0) > 200 -> "La nota es demasiado larga."
        else -> null
    }
}

enum class ReportKind { Expense, Income }

enum class ReportPeriod {
    ThisMonth, LastMonth, Last3Months, Last6Months, ThisYear, Last12Months;

    /**
     * El mismo tramo justo antes, para comparar: este mes hasta hoy frente al mes pasado hasta el mismo día,
     * los últimos 3 meses frente a los 3 anteriores, este año hasta hoy frente al año pasado hasta el mismo día.
     */
    fun previousRange(today: LocalDate, monthStartDay: Int = 1): ClosedRange<LocalDate> {
        val current = range(today, monthStartDay)
        val shift = when (this) {
            ThisMonth, LastMonth -> 1L
            Last3Months -> 3L
            Last6Months -> 6L
            ThisYear, Last12Months -> 12L
        }
        // Mismo día dentro de su periodo, sin pasarse del final del periodo anterior.
        val start = shiftedDay(current.start, shift, monthStartDay)
        // Un mes completo se compara con el periodo anterior completo (31 de marzo → 28 de febrero, no 3 de marzo).
        val end = if (this == LastMonth) monthContaining(start, monthStartDay).period(monthStartDay).endInclusive
        else shiftedDay(current.endInclusive, shift, monthStartDay)
        return start..maxOf(start, end)
    }

    /** Mismo día del periodo del hogar, [months] periodos antes; acotado al último día de ese periodo. */
    private fun shiftedDay(day: LocalDate, months: Long, monthStartDay: Int): LocalDate {
        val key = monthContaining(day, monthStartDay)
        val offset = ChronoUnit.DAYS.between(key.period(monthStartDay).start, day)
        val target = key.minusMonths(months).period(monthStartDay)
        return minOf(target.endInclusive, target.start.plusDays(offset))
    }

    /** Periodos del hogar: empiezan el [monthStartDay] (como el presupuesto). "Este año" = los periodos del año del mes en curso. */
    fun range(today: LocalDate, monthStartDay: Int = 1): ClosedRange<LocalDate> {
        val month = monthContaining(today, monthStartDay)
        return when (this) {
            ThisMonth -> month.period(monthStartDay).start..today
            LastMonth -> month.minusMonths(1).period(monthStartDay)
            Last3Months -> month.minusMonths(2).period(monthStartDay).start..today
            Last6Months -> month.minusMonths(5).period(monthStartDay).start..today
            ThisYear -> YearMonth.of(month.year, 1).period(monthStartDay).start..today
            Last12Months -> month.minusMonths(11).period(monthStartDay).start..today
        }
    }
}

/**
 * Primer día que puede pintar la pantalla de informes: el más antiguo de todos los periodos y de sus anteriores,
 * con el mes del hogar y con el mes natural (los gastos por etiqueta y por comercio aún usan el natural).
 */
fun reportWindowStart(today: LocalDate, monthStartDay: Int): LocalDate =
    ReportPeriod.entries.minOf { p -> minOf(p.previousRange(today, monthStartDay).start, p.previousRange(today).start) }

/** Informe de gastos o ingresos de un periodo, por categoría y por mes. */
class SpendingReport(
    movements: List<Movement>, categories: List<BudgetCategory>, range: ClosedRange<LocalDate>,
    val kind: ReportKind = ReportKind.Expense, categoryIds: Set<String> = emptySet(), monthStartDay: Int = 1,
) {
    data class Row(val id: String, val category: BudgetCategory?, val title: String, val amount: Long, val count: Int, val share: Double)
    data class MonthTotal(val month: YearMonth, val amount: Long)

    val total: Long
    val byCategory: List<Row>
    val byMonth: List<MonthTotal>

    val range: ClosedRange<LocalDate> = range

    /** Días que abarca el informe (los dos extremos incluidos). */
    val dayCount: Int get() = (java.time.temporal.ChronoUnit.DAYS.between(range.start, range.endInclusive) + 1).toInt()

    /** Media por día del periodo, redondeada al céntimo. */
    val averagePerDay: Long get() = Math.round(total.toDouble() / maxOf(1, dayCount))

    /** Diferencia frente a otro informe (normalmente el del periodo anterior) y porcentaje; nulo si antes no había nada. */
    fun change(previous: SpendingReport): Pair<Long, Long?> {
        val difference = total - previous.total
        if (previous.total <= 0) return difference to null
        return difference to Math.round(difference.toDouble() / previous.total * 100)
    }

    val averagePerMonth: Long get() = if (byMonth.isEmpty()) 0 else (total + byMonth.size / 2) / byMonth.size

    init {
        val byId = categories.associateBy { it.id }
        val totals = linkedMapOf<String, Pair<Long, Int>>()
        val months = mutableMapOf<YearMonth, Long>()
        var sum = 0L
        val transfers = uncategorizedTransferIds(movements.filter { !it.excluded && it.day in range }, byId.keys)
        for (m in movements) {
            if (m.excluded || m.day !in range) continue
            val category = byId[m.categoryId]
            if (category?.kind == CategoryKind.Transfer || m.id in transfers) continue
            val matches = when (kind) {
                ReportKind.Expense -> category?.let { it.kind == CategoryKind.Expense } ?: (m.amountMinor < 0)
                ReportKind.Income -> category?.let { it.kind == CategoryKind.Income } ?: (m.amountMinor >= 0)
            }
            if (!matches) continue
            if (categoryIds.isNotEmpty() && (category == null || category.id !in categoryIds)) continue
            // Gastos en positivo; una devolución dentro de una categoría de gasto lo resta.
            val value = if (kind == ReportKind.Expense) -m.amountMinor else m.amountMinor
            val key = category?.id ?: NO_CATEGORY
            val (amount, count) = totals[key] ?: (0L to 0)
            totals[key] = amount + value to count + 1
            val month = monthContaining(m.day, monthStartDay)
            months[month] = (months[month] ?: 0) + value
            sum += value
        }
        total = sum
        byCategory = totals.map { (key, entry) ->
            Row(key, byId[key], byId[key]?.name ?: "Sin categoría", entry.first, entry.second, if (sum > 0) max(0.0, entry.first.toDouble() / sum) else 0.0)
        }.sortedWith(compareBy({ -it.amount }, { it.title }))
        val last = monthContaining(range.endInclusive, monthStartDay)
        byMonth = generateSequence(monthContaining(range.start, monthStartDay)) { it.plusMonths(1) }.takeWhile { it <= last }
            .map { MonthTotal(it, months[it] ?: 0) }.toList()
    }

    private companion object {
        const val NO_CATEGORY = "sin-categoria"
    }
}

/** La categoría de gasto que más sube de un mes al anterior; el porcentaje es nulo si antes no se gastaba nada. */
data class BiggestRise(val title: String, val percent: Long?, val previous: YearMonth)

/** [month] es el mes del hogar (con [monthContaining]); cada mes abarca su [period]. */
fun biggestRise(movements: List<Movement>, categories: List<BudgetCategory>, month: YearMonth, monthStartDay: Int = 1): BiggestRise? {
    fun report(m: YearMonth) = SpendingReport(movements, categories, m.period(monthStartDay)).byCategory.associateBy { it.id }
    val previous = month.minusMonths(1)
    val before = report(previous)
    val best = report(month).values.filter { it.amount > (before[it.id]?.amount ?: 0) }
        .maxByOrNull { it.amount - (before[it.id]?.amount ?: 0) } ?: return null
    val old = before[best.id]?.amount?.takeIf { it > 0 }
    return BiggestRise(best.title, old?.let { (best.amount - it) * 100 / it }, previous)
}
