package com.savethemoney.android.data

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.text.Normalizer
import java.time.DateTimeException
import java.time.LocalDate
import kotlin.math.abs

// CSVImport.swift de STMCore. La huella debe salir igual que en iOS para no duplicar filas entre móviles.

private fun Char.isSpace() = this == ' ' || this == '\t' || Character.getType(this) == Character.SPACE_SEPARATOR.toInt()

/** Propiedad White_Space de Unicode, la de iOS: `isWhitespace` de Kotlin añade U+001C–001F y no tiene U+0085. */
private fun Char.isWhiteSpace() = (isWhitespace() && this !in '\u001C'..'\u001F') || this == '\u0085'
private fun String.trimSpaces() = trim { it.isSpace() }

/** Tabla leída de un CSV: comillas, saltos dentro de comillas, BOM, CRLF y separadores ";", "," y tabulador. */
data class CsvTable(val rows: List<List<String>>, val delimiter: Char) {
    companion object {
        /** UTF-8 si lo es; si no, Windows-1252, que es lo que exportan muchos bancos españoles. */
        fun decode(data: ByteArray): String {
            val hasBom = data.size >= 3 && data[0] == 0xEF.toByte() && data[1] == 0xBB.toByte() && data[2] == 0xBF.toByte()
            val bytes = if (hasBom) data.copyOfRange(3, data.size) else data
            return try {
                Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
            } catch (_: CharacterCodingException) {
                String(bytes, Charset.forName("windows-1252"))
            }
        }

        fun parse(raw: String, delimiter: Char? = null): CsvTable {
            val text = raw.removePrefix("﻿")
            val sep = delimiter ?: guessDelimiter(text)
            val rows = mutableListOf<List<String>>()
            var row = mutableListOf<String>()
            val field = StringBuilder()
            var inQuotes = false

            fun endField() { row += field.toString().trimSpaces(); field.clear() }
            fun endRow() {
                endField()
                if (!(row.size == 1 && row[0].isEmpty())) rows += row
                row = mutableListOf()
            }

            var i = 0
            while (i < text.length) {
                val ch = text[i++]
                when {
                    inQuotes -> when {
                        ch != '"' -> field.append(ch)
                        i < text.length && text[i] == '"' -> { field.append('"'); i++ }
                        else -> inQuotes = false
                    }
                    ch == '"' && field.toString().trimSpaces().isEmpty() -> { field.clear(); inQuotes = true }
                    ch == sep -> endField()
                    ch == '\n' || ch == '\r' -> {
                        if (ch == '\r' && i < text.length && text[i] == '\n') i++
                        endRow()
                    }
                    else -> field.append(ch)
                }
            }
            if (field.isNotEmpty() || row.isNotEmpty()) endRow()
            return CsvTable(rows, sep)
        }

        /**
         * Separadores que se prueban; en caso de empate gana el primero. La coma va la última
         * porque también aparece en conceptos e importes ("PAGO BIZUM, CENA", "-12,50").
         */
        val delimiters = listOf(';', '\t', ',')

        /**
         * El separador que da el mismo número de columnas (dos o más) en más líneas de las 20 primeras.
         * Contar cuántas veces aparece no vale: "28/10/2026;PAGO BIZUM, CENA, JUAN;-12,50" tiene más comas.
         */
        fun guessDelimiter(text: String): Char {
            var end = text.length
            var inQuotes = false
            var lines = 0
            for ((i, ch) in text.withIndex()) {
                if (ch == '"') {
                    inQuotes = !inQuotes
                } else if (!inQuotes && ch == '\n' && ++lines >= 20) {
                    end = i + 1
                    break
                }
            }
            val sample = text.substring(0, end)
            fun score(candidate: Char): Int =
                parse(sample, candidate).rows.filter { it.size >= 2 }.groupingBy { it.size }.eachCount().values.maxOrNull() ?: 0
            return delimiters.maxBy(::score)
        }
    }
}

/** Orden de día, mes y año en las fechas del archivo. */
enum class DateOrder {
    DayMonthYear, YearMonthDay, MonthDayYear;

    /** Lee "28/10/2026", "28-10-26", "2026-10-28" o "28.10.2026"; ignora la hora si la hay. */
    fun parse(text: String): LocalDate? {
        val datePart = text.trimSpaces().split(' ').firstOrNull { it.isNotEmpty() } ?: return null
        val parts = datePart.split('/', '-', '.').filter { it.isNotEmpty() }
        if (parts.size != 3 || !parts.all { p -> p.all { it.isDigit() } }) return null
        val n = parts.map { it.toIntOrNull() ?: return null }
        // Un primer bloque de 4 cifras siempre es el año.
        val order = if (parts[0].length == 4) YearMonthDay else this
        val (y0, m, d) = when (order) {
            DayMonthYear -> Triple(n[2], n[1], n[0])
            YearMonthDay -> Triple(n[0], n[1], n[2])
            MonthDayYear -> Triple(n[2], n[0], n[1])
        }
        val y = if (y0 < 100) y0 + 2000 else y0
        if (y !in 1900..2999) return null
        return try { LocalDate.of(y, m, d) } catch (_: DateTimeException) { null }
    }
}

sealed interface AmountColumns {
    /** Una columna con signo: negativo gasto, positivo ingreso. */
    data class Signed(val column: Int) : AmountColumns
    /** Dos columnas: cargos (gastos) y abonos (ingresos). */
    data class Split(val debit: Int, val credit: Int) : AmountColumns
}

/** Qué columna es cada cosa (desde 0). `headerRow` nulo si el archivo no tiene cabecera. */
data class CsvMapping(
    val headerRow: Int?,
    val date: Int,
    val description: Int,
    val amount: AmountColumns,
    val dateOrder: DateOrder = DateOrder.DayMonthYear,
) {
    val firstDataRow: Int get() = (headerRow ?: -1) + 1

    companion object {
        /** Busca la cabecera en las primeras filas y reconoce los nombres de columna habituales. */
        fun detect(table: CsvTable): CsvMapping? {
            for ((index, row) in table.rows.take(30).withIndex()) {
                val names = row.map(::normalize)
                val date = bestColumn(
                    names,
                    listOf("fecha operacion", "fecha de operacion", "f. operacion", "fecha contable", "fecha", "date"),
                    listOf("valor"),
                ) ?: bestColumn(names, listOf("fecha", "date"), emptyList()) ?: continue
                val description = bestColumn(
                    names,
                    listOf("concepto", "descripcion", "movimiento", "detalle", "description", "comercio", "beneficiario"),
                    listOf("fecha"),
                ) ?: continue
                val excluded = listOf("saldo", "balance", "disponible", "divisa", "moneda")
                val order by lazy { guessDateOrder(table, date, index + 1) }
                bestColumn(names, listOf("importe", "cantidad", "amount", "monto"), excluded)?.let {
                    return CsvMapping(index, date, description, AmountColumns.Signed(it), order)
                }
                val debit = bestColumn(names, listOf("cargo", "debe", "gasto", "debit", "salida"), excluded)
                val credit = bestColumn(names, listOf("abono", "haber", "ingreso", "credit", "entrada"), excluded)
                if (debit != null && credit != null) return CsvMapping(index, date, description, AmountColumns.Split(debit, credit), order)
            }
            return detectWithoutHeader(table)
        }

        /** Sin cabecera: la columna con fechas, la de importes y la de texto más largo. */
        private fun detectWithoutHeader(table: CsvTable): CsvMapping? {
            val sample = table.rows.take(20)
            val width = sample.maxOfOrNull { it.size } ?: return null
            if (width < 3) return null
            fun share(column: Int, test: (String) -> Boolean): Double {
                val values = sample.mapNotNull { it.getOrNull(column) }.filter { it.isNotEmpty() }
                return if (values.isEmpty()) 0.0 else values.count(test).toDouble() / values.size
            }
            val columns = (0 until width).toList()
            val date = columns.firstOrNull { c -> share(c) { DateOrder.DayMonthYear.parse(it) != null } > 0.8 } ?: return null
            fun amountColumn(test: (String) -> Boolean) = columns.firstOrNull { c -> c != date && share(c, test) > 0.8 }
            // Solo si ninguna columna vale con la regla común se prueba el formato inglés ("1,234"),
            // para que un archivo que ya se detectaba siga eligiendo la misma columna.
            val amount = amountColumn { Money.parse(it) != null }
                ?: amountColumn { Money.parse(it) != null || Money.parse(CsvImporter.swapSeparators(it)) != null }
                ?: return null
            val description = columns.filter { it != date && it != amount }.maxByOrNull { averageLength(sample, it) } ?: return null
            return CsvMapping(null, date, description, AmountColumns.Signed(amount), guessDateOrder(table, date, 0))
        }

        /** Día/mes salvo que algún valor solo tenga sentido como mes/día (p. ej. "10/28/2026"). */
        private fun guessDateOrder(table: CsvTable, column: Int, start: Int): DateOrder {
            val values = table.rows.drop(start).take(200).mapNotNull { it.getOrNull(column) }
            val dmy = values.count { DateOrder.DayMonthYear.parse(it) != null }
            val mdy = values.count { DateOrder.MonthDayYear.parse(it) != null }
            return if (mdy > dmy) DateOrder.MonthDayYear else DateOrder.DayMonthYear
        }

        private fun averageLength(rows: List<List<String>>, column: Int): Double {
            val values = rows.mapNotNull { it.getOrNull(column) }
            return if (values.isEmpty()) 0.0 else values.sumOf { it.length }.toDouble() / values.size
        }

        /** La primera palabra clave de la lista que aparece en alguna columna gana. */
        private fun bestColumn(names: List<String>, keys: List<String>, excluding: List<String>): Int? {
            for (key in keys) {
                val i = names.indexOfFirst { name -> key in name && excluding.none { it in name } }
                if (i >= 0) return i
            }
            return null
        }

        /**
         * Texto plegado de la huella de importación, el mismo que `CSVMapping.normalize` de iOS:
         * NFD; fuera las marcas no espaciadas (Mn), salvo U+FE0F justo detrás de un emoji; minúsculas
         * carácter a carácter (sin sigma final), ς→σ y ß→ss; fuera los espacios Unicode de los extremos.
         * Sin NFC. Así "Ñandú" y "nandu" dan lo mismo.
         */
        fun normalize(text: String): String {
            val kept = StringBuilder()
            var previous = 0
            Normalizer.normalize(text, Normalizer.Form.NFD).codePoints().forEach { cp ->
                val drop = Character.getType(cp) == Character.NON_SPACING_MARK.toInt() && (cp != 0xFE0F || !isEmojiBase(previous))
                previous = cp
                if (!drop) kept.appendCodePoint(cp)
            }
            // lowercase() pone ς al final de palabra; con ς→σ queda carácter a carácter, como en iOS.
            return kept.toString().lowercase().replace('ς', 'σ').replace("ß", "ss").trim { it.isWhiteSpace() }
        }

        /** Emoji que se escriben con U+FE0F detrás («❤️»): ahí el selector se conserva, como en iOS. */
        private fun isEmojiBase(cp: Int): Boolean =
            cp in 0x2000..0x2BFF || cp in 0x1F000..0x1FAFF || cp == 0x3030 || cp == 0x303D || cp == 0x3297 || cp == 0x3299
    }
}

/** Una fila del CSV ya interpretada; `line` empieza en 1. */
data class CsvImportRow(val line: Int, val draft: MovementDraft? = null, val issue: String? = null)

object CsvImporter {
    /**
     * Convierte las filas de datos en movimientos de la cuenta dada. Las filas vacías o de totales
     * sin fecha se saltan; las que tienen fecha pero algo mal vuelven con `issue`.
     */
    fun rows(table: CsvTable, mapping: CsvMapping, accountId: String): List<CsvImportRow> {
        val seen = mutableMapOf<String, Int>()
        val result = mutableListOf<CsvImportRow>()
        val decimalPoint = usesDecimalPoint(table, mapping)
        fun money(text: String) = Money.parse(if (decimalPoint) swapSeparators(text) else text)
        for (index in mapping.firstDataRow until table.rows.size) {
            val row = table.rows[index]
            fun cell(column: Int) = row.getOrElse(column) { "" }

            val rawDate = cell(mapping.date)
            if (rawDate.isEmpty() || row.all { it.isEmpty() }) continue
            val line = index + 1
            val day = mapping.dateOrder.parse(rawDate)
            if (day == null) {
                result += CsvImportRow(line, issue = "Fecha no reconocida: «${rawDate.take(20)}»")
                continue
            }

            val amount = when (val a = mapping.amount) {
                is AmountColumns.Signed -> money(cell(a.column))
                is AmountColumns.Split -> {
                    val out = money(cell(a.debit))?.let { -abs(it) }
                    val into = money(cell(a.credit))?.let { abs(it) }
                    // Con cargo y abono a la vez no se sabe cuál vale: se avisa en vez de quedarse con uno.
                    if (out != null && into != null && out != 0L && into != 0L) {
                        result += CsvImportRow(line, issue = "Tiene cargo y abono a la vez")
                        continue
                    }
                    listOfNotNull(out, into).firstOrNull { it != 0L } ?: out ?: into
                }
            }
            if (amount == null || amount == 0L) {
                result += CsvImportRow(line, issue = "Importe vacío o no válido")
                continue
            }

            val description = cell(mapping.description).split { it.isWhiteSpace() }.joinToString(" ")
            // 200 puntos de código, lo que cuenta `char_length` en la base de datos; nunca medio emoji.
            val text = when {
                description.isEmpty() -> "Sin concepto"
                description.codePointCount(0, description.length) <= 200 -> description
                else -> description.substring(0, description.offsetByCodePoints(0, 200))
            }
            val key = "$day|$amount|${CsvMapping.normalize(text)}"
            val occurrence = seen[key] ?: 0
            seen[key] = occurrence + 1
            result += CsvImportRow(line, MovementDraft(accountId, null, day, amount, text, importHash = sha256Hex("$key|$occurrence")))
        }
        return result
    }

    /**
     * Formato numérico del archivo, decidido una vez con las celdas de importe (iOS: `CSVImporter.usesDecimalPoint`).
     *
     * Solo cuentan las celdas que dicen por sí solas cuál es su separador decimal: las que tienen
     * «,» y «.» (decimal el último) y las que tienen un solo separador seguido de una o dos cifras
     * ("12,50" dice coma; "12.5" dice punto). "1,234" o "1.250" no dicen nada.
     *
     * - Si todas las que dicen algo dicen punto, el archivo está en formato inglés y cada celda se
     *   lee con «,» y «.» intercambiados: "1,234" es 1234,00, "1.5" es 1,50 y "1.250" no vale
     *   (en inglés serían 3 decimales).
     * - Si dicen coma, si no coinciden o si ninguna dice nada, no se adivina: se aplica la regla
     *   común de [Money.parse] y una fila ambigua se lista como no importable, igual que antes.
     */
    internal fun usesDecimalPoint(table: CsvTable, mapping: CsvMapping): Boolean {
        val columns = when (val a = mapping.amount) {
            is AmountColumns.Signed -> listOf(a.column)
            is AmountColumns.Split -> listOf(a.debit, a.credit)
        }
        val votes = table.rows.drop(mapping.firstDataRow)
            .flatMap { row -> columns.mapNotNull { row.getOrNull(it)?.let(::decimalSeparatorVote) } }
            .toSet()
        return votes == setOf('.')
    }

    /** «,» o «.» si la celda deja claro cuál es su separador decimal; nulo si no lo deja claro. */
    internal fun decimalSeparatorVote(text: String): Char? {
        val separators = text.filter { it == ',' || it == '.' }
        if (',' in separators && '.' in separators) return separators.last()
        if (separators.length != 1) return null
        val digits = text.substring(text.indexOf(separators[0]) + 1).takeWhile { it in '0'..'9' }
        return if (digits.length in 1..2) separators[0] else null
    }

    /** Cambia «,» por «.» y al revés: "1,234.56" pasa a "1.234,56". */
    internal fun swapSeparators(text: String): String =
        text.map { if (it == ',') '.' else if (it == '.') ',' else it }.joinToString("")

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

    fun sha256Hex(text: String): String =
        MessageDigest.getInstance("SHA-256").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }
}

/** Lo que se puede marcar en una fila de la vista previa. Solo los gastos se marcan. */
enum class ImportMark { None, Recurring, Subscription, Card }

object ImportMarks {
    /** Los movimientos a guardar: las compras con tarjeta van a la cuenta de la tarjeta en vez de a la del CSV. */
    fun drafts(rows: List<CsvImportRow>, marks: Map<Int, ImportMark>, cardAccountId: String?): List<MovementDraft> =
        rows.mapNotNull { row ->
            row.draft?.let { d ->
                if (cardAccountId != null && d.amountMinor < 0 && marks[row.line] == ImportMark.Card) d.copy(accountId = cardAccountId) else d
            }
        }

    /**
     * Pagos recurrentes nuevos para las filas marcadas: cada mes desde la fecha del movimiento, con su cuenta, categoría
     * y aviso un día antes. No repite uno que ya esté activo con el mismo nombre (sin mayúsculas ni espacios).
     */
    fun series(rows: List<CsvImportRow>, marks: Map<Int, ImportMark>, existing: List<RecurringSeries>, householdId: String): List<RecurringSeries> {
        val taken = existing.filter { !it.isArchived }.map { key(it.name) }.toMutableSet()
        return rows.mapNotNull { row ->
            val d = row.draft ?: return@mapNotNull null
            val kind = when (marks[row.line]) {
                ImportMark.Recurring -> RecurringKind.Essential
                ImportMark.Subscription -> RecurringKind.Subscription
                else -> return@mapNotNull null
            }
            val name = d.description.trim().take(60).trim()
            if (d.amountMinor >= 0 || !taken.add(key(name))) return@mapNotNull null
            RecurringSeries(
                "", householdId, name, kind, -d.amountMinor, d.accountId, d.categoryId,
                startsOn = d.bookedOn.toString(), remindDaysBefore = 1,
            )
        }
    }

    /**
     * Las series de [series] con el id ya fijado para su nombre en [ids], o con uno nuevo que queda fijado. Se llama al
     * empezar cada intento: repetir una importación que falló a medias repite el alta en vez de duplicarla.
     */
    fun pinned(series: List<RecurringSeries>, ids: MutableMap<String, String>): List<RecurringSeries> =
        series.map { it.copy(id = ids.getOrPut(key(it.name)) { java.util.UUID.randomUUID().toString() }) }

    fun key(name: String): String = CsvMapping.normalize(name).filterNot { it.isWhitespace() }
}
