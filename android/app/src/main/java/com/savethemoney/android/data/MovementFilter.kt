package com.savethemoney.android.data

import java.time.LocalDate
import java.time.YearMonth
import kotlin.math.abs

// MovementFilter.swift de STMCore.

/** Qué tipo de movimiento se quiere ver en la lista. */
enum class MovementKindFilter(val title: String) {
    All("Todos"), Expense("Gastos"), Income("Ingresos"), Transfer("Transferencias"),
}

/** Revisados, sin revisar o excluidos del presupuesto. */
enum class MovementStatusFilter(val title: String) {
    All("Todos"), Unreviewed("Sin revisar"), Reviewed("Revisados"), Excluded("Excluidos"),
}

/** Fechas rápidas del filtro de movimientos. */
enum class MovementDateFilter(val title: String) {
    All("Cualquier fecha"), ThisMonth("Este mes"), LastMonth("El mes pasado"), Last30Days("Últimos 30 días"),
    Last90Days("Últimos 90 días"), ThisYear("Este año"), Custom("Fechas a medida");

    /** Días incluidos; nulo = sin límite. [Custom] usa las fechas dadas. */
    fun range(today: LocalDate, custom: ClosedRange<LocalDate>? = null): ClosedRange<LocalDate>? {
        val month = YearMonth.from(today)
        return when (this) {
            All -> null
            ThisMonth -> month.atDay(1)..today
            LastMonth -> month.minusMonths(1).atDay(1)..month.minusMonths(1).atEndOfMonth()
            Last30Days -> today.minusDays(29)..today
            Last90Days -> today.minusDays(89)..today
            ThisYear -> LocalDate.of(today.year, 1, 1)..today
            Custom -> custom
        }
    }
}

/** Filtros de la lista de movimientos: cuenta, tipo, categoría, fechas y texto o importe. */
data class MovementFilter(
    val accountId: String? = null,
    val kind: MovementKindFilter = MovementKindFilter.All,
    val categoryId: String? = null,
    val dates: MovementDateFilter = MovementDateFilter.All,
    val customFrom: LocalDate? = null,
    val customThrough: LocalDate? = null,
    /** Busca en el concepto, las notas, el beneficiario, las etiquetas, el nombre de la categoría o el importe ("12,50", "12.5", "-12,50"). */
    val search: String = "",
    val status: MovementStatusFilter = MovementStatusFilter.All,
    /** Sólo los que llevan esta etiqueta. */
    val tag: String? = null,
) {
    /** Cuántos filtros (sin contar la búsqueda) hay puestos, para el icono del menú. */
    val activeCount: Int
        get() = listOf(accountId != null, kind != MovementKindFilter.All, categoryId != null, dates != MovementDateFilter.All,
            status != MovementStatusFilter.All, tag != null,
        ).count { it }

    fun dateRange(today: LocalDate): ClosedRange<LocalDate>? {
        val from = customFrom
        val through = customThrough
        val custom: ClosedRange<LocalDate>? = if (from != null && through != null) minOf(from, through)..maxOf(from, through) else null
        return dates.range(today, custom)
    }

    fun apply(movements: List<Movement>, categories: List<BudgetCategory>, today: LocalDate): List<Movement> {
        val byId = categories.associateBy { it.id }
        val range = dateRange(today)
        val query = search.trim()
        val amountQuery = if (query.isEmpty()) null else Money.parse(query)
        val signed = query.startsWith("-") || query.startsWith(Money.MINUS)
        return movements.filter { m ->
            if (accountId != null && m.accountId != accountId) return@filter false
            if (categoryId != null && m.categoryId != categoryId) return@filter false
            if (range != null && m.day !in range) return@filter false
            if (tag != null && tag !in m.tags) return@filter false
            val statusOk = when (status) {
                MovementStatusFilter.All -> true
                MovementStatusFilter.Unreviewed -> !m.isReviewed
                MovementStatusFilter.Reviewed -> m.isReviewed
                MovementStatusFilter.Excluded -> m.excluded
            }
            if (!statusOk) return@filter false
            val category = byId[m.categoryId]
            val isTransfer = category?.kind == CategoryKind.Transfer
            val kindOk = when (kind) {
                MovementKindFilter.All -> true
                MovementKindFilter.Transfer -> isTransfer
                MovementKindFilter.Expense -> !isTransfer && m.amountMinor < 0
                MovementKindFilter.Income -> !isTransfer && m.amountMinor >= 0
            }
            if (!kindOk) return@filter false
            if (query.isEmpty()) return@filter true
            if (m.description.contains(query, ignoreCase = true)) return@filter true
            if (m.notes?.contains(query, ignoreCase = true) == true) return@filter true
            if (m.payee?.contains(query, ignoreCase = true) == true) return@filter true
            val bareQuery = query.removePrefix("#")
            if (m.tags.any { it.contains(bareQuery, ignoreCase = true) }) return@filter true
            if (category?.name?.contains(query, ignoreCase = true) == true) return@filter true
            // Sin signo busca el importe en los dos sentidos; con "-" sólo gastos.
            amountQuery != null && if (signed) m.amountMinor == amountQuery else abs(m.amountMinor) == abs(amountQuery)
        }
    }
}

/** Movimientos de un mismo día con lo que suman (sin contar transferencias). */
data class MovementDay(val day: LocalDate, val movements: List<Movement>, val total: Long) {
    companion object {
        /** Agrupa por día, del más reciente al más antiguo; dentro de cada día se respeta el orden recibido. */
        fun group(movements: List<Movement>, categories: List<BudgetCategory>): List<MovementDay> {
            val transfers = categories.filter { it.kind == CategoryKind.Transfer }.map { it.id }.toSet()
            return movements.groupBy { it.day }.entries.sortedByDescending { it.key }.map { (day, items) ->
                MovementDay(day, items, items.filter { !it.excluded && it.categoryId !in transfers }.sumOf { it.amountMinor })
            }
        }
    }
}
