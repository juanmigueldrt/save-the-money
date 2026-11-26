package com.savethemoney.android.data

import java.time.LocalDate
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

    /** Días incluidos; nulo = sin límite. [Custom] usa las fechas dadas. Los meses y el año siguen el mes del hogar. */
    fun range(today: LocalDate, custom: ClosedRange<LocalDate>? = null, monthStartDay: Int = 1): ClosedRange<LocalDate>? = when (this) {
        All -> null
        ThisMonth -> ReportPeriod.ThisMonth.range(today, monthStartDay)
        LastMonth -> ReportPeriod.LastMonth.range(today, monthStartDay)
        Last30Days -> today.minusDays(29)..today
        Last90Days -> today.minusDays(89)..today
        ThisYear -> ReportPeriod.ThisYear.range(today, monthStartDay)
        Custom -> custom
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

    fun dateRange(today: LocalDate, monthStartDay: Int = 1): ClosedRange<LocalDate>? {
        val from = customFrom
        val through = customThrough
        val custom: ClosedRange<LocalDate>? = if (from != null && through != null) minOf(from, through)..maxOf(from, through) else null
        return dates.range(today, custom, monthStartDay)
    }

    fun apply(movements: List<Movement>, categories: List<BudgetCategory>, today: LocalDate, monthStartDay: Int = 1): List<Movement> {
        val byId = categories.associateBy { it.id }
        val range = dateRange(today, monthStartDay)
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

/**
 * La búsqueda de la lista de movimientos, que se hace en el servidor (ORC-85) para encontrar también los que no están
 * cargados. Encuentra un movimiento si su concepto, sus notas o su beneficiario contienen el texto (sin distinguir
 * mayúsculas), si lleva justo esa etiqueta ("#viaje"), si su categoría es una cuyo nombre contiene el texto o si el
 * importe es ese ("12,50" en los dos sentidos; "-12,50" sólo gastos). Como MovementSearch de iOS.
 */
data class MovementSearch(
    /** El texto sin caracteres de control ni espacios a los lados, recortado a [MAX_LENGTH]. */
    val text: String,
    /** Las categorías cuyo nombre contiene el texto: los movimientos sólo guardan el id. */
    val categoryIds: List<String>,
    /** La etiqueta que se busca, si el texto (sin «#») vale como etiqueta. */
    val tag: String?,
    /** El importe escrito en céntimos, si el texto es un importe. */
    val amountMinor: Long?,
    /** El importe llevaba signo menos: sólo ese importe con su signo. */
    val signedAmount: Boolean,
) {
    /** La misma regla que aplica el servidor, para el servicio en memoria y las pruebas. */
    fun matches(m: Movement): Boolean {
        if (m.description.contains(text, ignoreCase = true)) return true
        if (m.notes?.contains(text, ignoreCase = true) == true) return true
        if (m.payee?.contains(text, ignoreCase = true) == true) return true
        if (tag != null && tag in m.tags) return true
        if (m.categoryId != null && m.categoryId in categoryIds) return true
        val amount = amountMinor ?: return false
        return if (signedAmount) m.amountMinor == amount else abs(m.amountMinor) == abs(amount)
    }

    companion object {
        /** Lo que se manda como mucho, en caracteres Unicode: el resto se ignora. */
        const val MAX_LENGTH = 100

        /** Nulo si no queda nada que buscar. */
        fun of(raw: String, categories: List<BudgetCategory>): MovementSearch? {
            val clean = buildString {
                raw.codePoints().filter {
                    val type = Character.getType(it)
                    type != Character.CONTROL.toInt() && type != Character.FORMAT.toInt()
                }.forEach { appendCodePoint(it) }
            }.trim()
            val text = if (clean.codePointCount(0, clean.length) > MAX_LENGTH) {
                clean.substring(0, clean.offsetByCodePoints(0, MAX_LENGTH)).trim()
            } else {
                clean
            }
            if (text.isEmpty()) return null
            val bare = text.removePrefix("#")
            val tag = MovementTags.clean(bare)
            return MovementSearch(
                text = text,
                categoryIds = categories.filter { it.name.contains(text, ignoreCase = true) }.map { it.id },
                // Sólo si el texto entero es una etiqueta válida: así lo que va al servidor no lleva nada que escapar.
                tag = tag.takeIf { it.isNotEmpty() && it == bare.lowercase() && it.length <= MovementTags.MAX_LENGTH },
                amountMinor = Money.parse(text),
                signedAmount = text.startsWith("-") || text.startsWith(Money.MINUS),
            )
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
