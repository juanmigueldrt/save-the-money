package com.savethemoney.android.data

import java.time.Instant
import java.time.LocalDate

// MovementControl.swift de STMCore: etiquetas, beneficiario, edición masiva, parecidos, informes y CSV recordado.

/** Etiquetas de un movimiento: palabras sueltas en minúsculas, sin «#» (p. ej. "viaje", "boda-ana"). */
object MovementTags {
    const val MAX_COUNT = 10
    const val MAX_LENGTH = 30

    private fun allowed(ch: Char) = ch.isLetterOrDigit() || ch == '-' || ch == '_'

    /** Lo que el usuario escribe ("#Viaje, cumple  boda") en etiquetas limpias y sin repetir. */
    fun normalize(text: String): List<String> =
        text.split(',', ';', ' ', '\t', '\n').map(::clean).filter { it.isNotEmpty() }.distinct()

    /** Una etiqueta escrita a mano, limpia: sin «#», en minúsculas, sólo letras, números, "-" y "_". */
    fun clean(text: String): String = text.trim().trim('#').lowercase().filter(::allowed)

    /** Texto para el campo de edición: "viaje, cumple". */
    fun text(tags: List<String>): String = tags.joinToString(", ")

    /** Problema con las etiquetas, o nulo si valen (las mismas reglas que la base de datos). */
    fun issue(tags: List<String>): String? {
        if (tags.size > MAX_COUNT) return "Como mucho $MAX_COUNT etiquetas por movimiento."
        for (tag in tags) {
            if (tag.isEmpty() || tag.length > MAX_LENGTH) return "Cada etiqueta debe tener entre 1 y $MAX_LENGTH caracteres."
            if (tag != tag.lowercase() || !tag.all(::allowed)) return "Las etiquetas sólo pueden tener letras, números, «-» y «_»."
        }
        return null
    }

    /** Todas las etiquetas usadas, de la más usada a la menos. */
    fun all(movements: List<Movement>): List<String> =
        movements.flatMap { it.tags }.groupingBy { it }.eachCount().entries
            .sortedWith(compareBy({ -it.value }, { it.key })).map { it.key }
}

object Payee {
    /** Beneficiario limpio para guardar: sin espacios de más, nulo si queda vacío. */
    fun clean(text: String?): String? {
        val collapsed = text?.split(Regex("\\s+"))?.filter { it.isNotEmpty() }?.joinToString(" ") ?: return null
        return collapsed.ifEmpty { null }?.take(80)
    }

    /** Beneficiarios usados, del más usado al menos (para sugerir al escribir). */
    fun all(movements: List<Movement>): List<String> {
        val counts = linkedMapOf<String, Pair<String, Int>>()
        for (m in movements) {
            val payee = clean(m.payee) ?: continue
            val key = CsvMapping.normalize(payee)
            val (name, count) = counts[key] ?: (payee to 0)
            counts[key] = name to count + 1
        }
        return counts.values.sortedWith(compareBy({ -it.second }, { it.first })).map { it.first }
    }
}

/** Un cambio opcional: [Keep] no toca el campo; [Set] lo cambia (también a nulo). */
sealed interface Change<out T> {
    data object Keep : Change<Nothing>
    data class Set<T>(val value: T) : Change<T>
}

/** Cambios que se aplican a todos los movimientos elegidos. Lo que es nulo o [Change.Keep] no se toca. */
data class MovementBulkEdit(
    val bookedOn: LocalDate? = null,
    /** `Set(null)` quita la categoría. */
    val categoryId: Change<String?> = Change.Keep,
    val accountId: String? = null,
    val excluded: Boolean? = null,
    val reviewed: Boolean? = null,
    val payee: Change<String?> = Change.Keep,
    val addTags: List<String> = emptyList(),
    val removeTags: List<String> = emptyList(),
) {
    val isEmpty: Boolean
        get() = bookedOn == null && categoryId == Change.Keep && accountId == null && excluded == null && reviewed == null &&
            payee == Change.Keep && addTags.isEmpty() && removeTags.isEmpty()

    /** El movimiento con los cambios puestos. [now] es la hora de "revisado". */
    fun applied(movement: Movement, now: Instant = Instant.now()): Movement {
        var copy = movement
        bookedOn?.let { copy = copy.copy(bookedOn = it.toString()) }
        (categoryId as? Change.Set)?.let { copy = copy.copy(categoryId = it.value) }
        accountId?.let { copy = copy.copy(accountId = it) }
        excluded?.let { copy = copy.copy(excluded = it) }
        reviewed?.let { copy = copy.copy(reviewedAt = if (it) movement.reviewedAt ?: now.toString() else null) }
        (payee as? Change.Set)?.let { copy = copy.copy(payee = Payee.clean(it.value)) }
        if (addTags.isNotEmpty() || removeTags.isNotEmpty()) {
            val tags = copy.tags.filter { it !in removeTags }.toMutableList()
            addTags.forEach { if (it !in tags) tags += it }
            copy = copy.copy(tags = tags.take(MovementTags.MAX_COUNT))
        }
        return copy
    }

    /** Sólo los movimientos que cambian de verdad, ya cambiados. */
    fun changes(movements: List<Movement>, now: Instant = Instant.now()): List<Movement> =
        movements.mapNotNull { m -> applied(m, now).takeIf { it != m } }
}

object SimilarMovements {
    /**
     * Clave para reconocer el mismo concepto: sin acentos, mayúsculas, números ni signos sueltos
     * ("COMPRA MERCADONA 1234 TARJ. 5678" y "Compra Mercadona 99" coinciden).
     */
    fun key(description: String): String =
        CsvMapping.normalize(description).split { !it.isLetter() }.filter { it.length > 1 }.joinToString(" ")

    private fun String.split(isSeparator: (Char) -> Boolean): List<String> {
        val parts = mutableListOf<String>()
        val current = StringBuilder()
        for (ch in this) {
            if (!isSeparator(ch)) current.append(ch)
            else if (current.isNotEmpty()) { parts += current.toString(); current.clear() }
        }
        if (current.isNotEmpty()) parts += current.toString()
        return parts
    }

    /** Otros movimientos con el mismo concepto que cambiarían si se les pone [categoryId] (los que ya la tienen no). */
    fun matches(movement: Movement, movements: List<Movement>, categoryId: String?): List<Movement> {
        val target = key(movement.description)
        if (target.isEmpty()) return emptyList()
        return movements.filter {
            it.id != movement.id && it.categoryId != categoryId && key(it.description) == target &&
                (it.amountMinor < 0) == (movement.amountMinor < 0)
        }
    }
}

/** Gasto e ingreso agrupados por etiqueta o por beneficiario. */
data class GroupedSpending(
    val title: String,
    /** Gastos en positivo (una devolución lo resta). */
    val spent: Long,
    val income: Long,
    val count: Int,
) {
    enum class Grouping(val title: String) { Tag("Por etiqueta"), Payee("Por beneficiario") }

    companion object {
        /** En el periodo, sin transferencias ni excluidos. Un movimiento con dos etiquetas cuenta en las dos. */
        fun report(grouping: Grouping, movements: List<Movement>, categories: List<BudgetCategory>, range: ClosedRange<LocalDate>): List<GroupedSpending> {
            val transfers = categories.filter { it.kind == CategoryKind.Transfer }.map { it.id }.toSet()
            val rows = mutableMapOf<String, GroupedSpending>()
            for (m in movements) {
                if (m.excluded || m.day !in range || m.categoryId in transfers) continue
                val keys = when (grouping) {
                    Grouping.Tag -> m.tags
                    Grouping.Payee -> listOfNotNull(com.savethemoney.android.data.Payee.clean(m.payee))
                }
                for (key in keys) {
                    val row = rows[key] ?: GroupedSpending(key, 0, 0, 0)
                    rows[key] = if (m.amountMinor < 0) row.copy(spent = row.spent - m.amountMinor, count = row.count + 1)
                    else row.copy(income = row.income + m.amountMinor, count = row.count + 1)
                }
            }
            return rows.values.sortedWith(compareBy({ -it.spent }, { it.title }))
        }
    }
}

/** La cuenta que sale elegida al apuntar un movimiento: la marcada, o la primera activa. */
fun List<Account>.defaultAccount(): Account? {
    val active = filter { !it.isArchived }
    return active.firstOrNull { it.isDefault } ?: active.firstOrNull()
}

/**
 * Formato de un CSV ya importado, para no tener que elegir columnas la próxima vez.
 * Se reconoce por la fila de cabecera (o por el número de columnas si no hay). Solo columnas y cuenta: nada de datos.
 */
@kotlinx.serialization.Serializable
data class CsvSavedFormat(
    val fingerprint: String,
    val headerRow: Int?,
    val date: Int,
    val description: Int,
    val signedAmount: Int? = null,
    val debit: Int? = null,
    val credit: Int? = null,
    val monthFirst: Boolean = false,
    /** Cuenta a la que se importó la última vez. */
    val accountId: String? = null,
) {
    val mapping: CsvMapping?
        get() {
            val amount = when {
                signedAmount != null -> AmountColumns.Signed(signedAmount)
                debit != null && credit != null -> AmountColumns.Split(debit, credit)
                else -> return null
            }
            return CsvMapping(headerRow, date, description, amount, if (monthFirst) DateOrder.MonthDayYear else DateOrder.DayMonthYear)
        }

    companion object {
        fun of(table: CsvTable, mapping: CsvMapping, accountId: String?): CsvSavedFormat {
            val signed = mapping.amount as? AmountColumns.Signed
            val split = mapping.amount as? AmountColumns.Split
            return CsvSavedFormat(
                fingerprint(table, mapping.headerRow), mapping.headerRow, mapping.date, mapping.description,
                signed?.column, split?.debit, split?.credit, mapping.dateOrder == DateOrder.MonthDayYear, accountId,
            )
        }

        /** Huella de la cabecera: sus nombres normalizados. Sin cabecera, el número de columnas. */
        fun fingerprint(table: CsvTable, headerRow: Int?): String {
            if (headerRow != null && headerRow in table.rows.indices) {
                return "h:" + table.rows[headerRow].joinToString("|") { CsvMapping.normalize(it) }
            }
            return "n:${table.rows.take(20).maxOfOrNull { it.size } ?: 0}"
        }

        /** El formato guardado que encaja con este archivo, si hay alguno. */
        fun match(table: CsvTable, saved: List<CsvSavedFormat>): CsvSavedFormat? =
            saved.firstOrNull { fingerprint(table, it.headerRow) == it.fingerprint }

        /** Añade o sustituye (por huella) y deja como mucho 20, el más reciente primero. */
        fun remember(format: CsvSavedFormat, saved: List<CsvSavedFormat>): List<CsvSavedFormat> =
            (listOf(format) + saved.filter { it.fingerprint != format.fingerprint }).take(20)
    }
}

/** Lo decidido para cada fila de un CSV antes de importarlo, por número de línea. */
data class CsvRowReview(
    /** Filas que no se importan. */
    val skipped: Set<Int> = emptySet(),
    /** Filas que se importan como excluidas del presupuesto. */
    val excluded: Set<Int> = emptySet(),
    /** Categoría elegida a mano (valor nulo = sin categoría). */
    val categories: Map<Int, String?> = emptyMap(),
) {
    /** El borrador de una fila con lo decidido. */
    fun apply(draft: MovementDraft, line: Int): MovementDraft {
        var copy = draft
        if (line in categories) copy = copy.copy(categoryId = categories[line])
        if (line in excluded) copy = copy.copy(excluded = true)
        return copy
    }

    /** Las filas que se van a importar, ya con sus cambios. Las de problema se dejan como están. */
    fun apply(rows: List<CsvImportRow>): List<CsvImportRow> = rows.mapNotNull { row ->
        val draft = row.draft ?: return@mapNotNull row
        if (row.line in skipped) null else row.copy(draft = apply(draft, row.line))
    }

    /** Olvida lo decidido para filas que ya no están (otro archivo u otras columnas). */
    fun keep(lines: Set<Int>) = CsvRowReview(skipped intersect lines, excluded intersect lines, categories.filterKeys { it in lines })
}
