package com.savethemoney.android.data

import java.time.LocalDate
import java.time.YearMonth
import kotlin.math.abs

// Export.swift de STMCore.

/** Movimientos en un CSV que Excel en español abre bien: ";", coma decimal, dd/mm/aaaa, CRLF y BOM UTF-8. */
object MovementsCsv {
    private val HEADER = listOf("Fecha", "Cuenta", "Categoría", "Descripción", "Importe", "Moneda", "Notas")

    fun text(movements: List<Movement>, accounts: List<Account>, categories: List<BudgetCategory>): String {
        val cuentas = accounts.associate { it.id to it.name }
        val nombres = categories.associate { it.id to it.name }
        val filas = movements.sortedWith(compareBy({ it.bookedOn }, { it.description })).map { m ->
            listOf(
                field(dayText(m.day)), field(cuentas[m.accountId] ?: ""), field(nombres[m.categoryId] ?: ""),
                field(m.description), amountText(m.amountMinor), "EUR", field(m.notes ?: ""),
            ).joinToString(";")
        }
        return (listOf(HEADER.joinToString(";", transform = ::field)) + filas).joinToString("\r\n") + "\r\n"
    }

    fun bytes(movements: List<Movement>, accounts: List<Account>, categories: List<BudgetCategory>): ByteArray =
        byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + text(movements, accounts, categories).toByteArray()

    fun fileName(day: LocalDate) = "movimientos-$day.csv"

    /** "1234,56" o "-12,05": sin miles, para que Excel lo tome como número. */
    fun amountText(minor: Long): String =
        (if (minor < 0) "-" else "") + "${abs(minor) / 100}," + (abs(minor) % 100).toString().padStart(2, '0')

    fun dayText(d: LocalDate) = "%02d/%02d/%04d".format(d.dayOfMonth, d.monthValue, d.year)

    /** Entrecomilla si hace falta y desactiva fórmulas: un texto que empieza por "=", "+", "-" o "@" Excel lo ejecutaría. */
    fun field(value: String): String {
        val text = if (value.firstOrNull()?.let { it in "=+-@\t\r" } == true) "'$value" else value
        if (text.none { it == ';' || it == '"' || it == '\n' || it == '\r' }) return text
        return "\"" + text.replace("\"", "\"\"") + "\""
    }
}

/** Lo que hay que pagar en un mes según los pagos fijos, para el PDF. */
class MonthlyBills(series: List<RecurringSeries>, val month: YearMonth, accounts: List<Account> = emptyList()) {
    data class Line(val name: String, val kind: RecurringKind, val due: LocalDate, val amount: Long, val accountName: String?)

    val lines: List<Line> = series.filter { !it.isArchived && it.kind != RecurringKind.Income }
        .flatMap { s ->
            val cuenta = accounts.firstOrNull { it.id == s.accountId }?.name
            s.occurrences(month.atDay(1), month.atEndOfMonth()).map { Line(s.trimmedName, s.kind, it, s.amountOn(it), cuenta) }
        }
        .sortedWith(compareBy({ it.due }, { it.name }))

    val total: Long get() = lines.sumOf { it.amount }
    fun total(kind: RecurringKind): Long = lines.filter { it.kind == kind }.sumOf { it.amount }
    fun pending(from: LocalDate): Long = lines.filter { !it.due.isBefore(from) }.sumOf { it.amount }
    val fileName: String get() = "pagos-$month.pdf"
}
