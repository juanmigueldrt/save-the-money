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

        /** El separador que más se repite fuera de comillas en las primeras líneas. */
        fun guessDelimiter(text: String): Char {
            val candidates = listOf(';', ',', '\t')
            val counts = mutableMapOf<Char, Int>()
            var inQuotes = false
            var lines = 0
            for (ch in text) {
                if (ch == '"') inQuotes = !inQuotes
                else if (!inQuotes && ch in candidates) counts[ch] = (counts[ch] ?: 0) + 1
                else if (!inQuotes && ch == '\n' && ++lines >= 20) break
            }
            return candidates.maxBy { counts[it] ?: 0 }
        }
    }
}

/** Orden de día, mes y año en las fechas del archivo. */
enum class DateOrder(val title: String) {
    DayMonthYear("Día/mes/año"), YearMonthDay("Año-mes-día"), MonthDayYear("Mes/día/año");

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
            val amount = columns.firstOrNull { c -> c != date && share(c) { Money.parse(it) != null } > 0.8 } ?: return null
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

        /** Como `folding` de iOS con mayúsculas y acentos: "Ñandú" y "nandu" dan lo mismo. */
        fun normalize(text: String): String =
            Normalizer.normalize(text, Normalizer.Form.NFD).replace("\\p{Mn}".toRegex(), "")
                .replace("ß", "ss").lowercase().trim()
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
                is AmountColumns.Signed -> Money.parse(cell(a.column))
                is AmountColumns.Split -> {
                    val out = Money.parse(cell(a.debit))?.let { -abs(it) }
                    val into = Money.parse(cell(a.credit))?.let { abs(it) }
                    listOfNotNull(out, into).firstOrNull { it != 0L } ?: out ?: into
                }
            }
            if (amount == null || amount == 0L) {
                result += CsvImportRow(line, issue = "Importe vacío o no válido")
                continue
            }

            val description = cell(mapping.description).split { it.isWhitespace() }.joinToString(" ")
            val text = if (description.isEmpty()) "Sin concepto" else description.take(200)
            val key = "$day|$amount|${CsvMapping.normalize(text)}"
            val occurrence = seen[key] ?: 0
            seen[key] = occurrence + 1
            result += CsvImportRow(line, MovementDraft(accountId, null, day, amount, text, importHash = sha256Hex("$key|$occurrence")))
        }
        return result
    }

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
