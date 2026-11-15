package com.savethemoney.android.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlin.math.abs

/**
 * Dinero en céntimos (Long). Nunca se usa Double para importes (Money de iOS).
 * Formato español con miles siempre agrupados, como en el diseño: "1.234,56 €", "−64,20 €".
 */
object Money {
    /** Signo menos tipográfico (U+2212), como pide el manual. */
    const val MINUS = '−'

    /**
     * Lee texto escrito por la persona o de un CSV ("1.234,56", "-12,5", "12.50 €", "(3,00)").
     * El último separador seguido de 1 o 2 cifras es el decimal; el resto son miles.
     */
    fun parse(text: String): Long? {
        var s = text.trim().replace("€", "").replace("EUR", "").replace(" ", "").replace(" ", "")
            .replace(MINUS, '-')
        if (s.isEmpty()) return null
        var negative = false
        if (s.startsWith("-")) { negative = true; s = s.drop(1) } else if (s.startsWith("+")) s = s.drop(1)
        if (s.startsWith("(") && s.endsWith(")")) { negative = true; s = s.drop(1).dropLast(1) }
        if (s.endsWith("-")) { negative = true; s = s.dropLast(1) }

        val lastComma = s.lastIndexOf(',')
        val lastDot = s.lastIndexOf('.')
        val sep: Char? = when {
            lastComma >= 0 && lastDot >= 0 -> if (lastComma > lastDot) ',' else '.'
            lastComma >= 0 -> if (s.length - lastComma - 1 <= 2) ',' else null
            lastDot >= 0 -> if (s.length - lastDot - 1 <= 2) '.' else null
            else -> null
        }
        var integer = s
        var fraction = ""
        if (sep != null) {
            val i = s.lastIndexOf(sep)
            integer = s.substring(0, i)
            fraction = s.substring(i + 1)
        }
        integer = integer.filter { it != '.' && it != ',' }
        if (integer.isEmpty() && fraction.isEmpty()) return null
        if (!integer.all { it in '0'..'9' } || !fraction.all { it in '0'..'9' } || fraction.length > 2) return null
        if (integer.length > 15) return null
        val total = (integer.ifEmpty { "0" }.toLong()) * 100 + fraction.padEnd(2, '0').toLong()
        return if (negative) -total else total
    }

    /**
     * Cómo se enseñan los importes en la app (Más opciones > Vista). Es estado de Compose:
     * al cambiarlo se vuelve a pintar todo lo que muestra importes.
     */
    data class Display(
        /** Modo incógnito: todos los importes salen como "•••• €". */
        val hidesAmounts: Boolean = false,
        /** Sin céntimos: "1.235 €" en vez de "1.234,56 €". */
        val roundsToUnits: Boolean = false,
        /** «+» delante de los ingresos donde la app enseña el signo. */
        val plusSign: Boolean = true,
    ) {
        companion object {
            /** Sin ocultar ni redondear, para PDF, CSV y pruebas. */
            val Standard = Display()
        }
    }

    var display by mutableStateOf(Display.Standard)

    const val HIDDEN = "••••"

    /**
     * "1.234,56 €". [decimals] false quita los céntimos ("48.230 €"); [signed] pone "+" a los positivos
     * (si la vista lo permite). Respeta [display] salvo que se pasen otras [options] (p. ej. [Display.Standard] en un PDF).
     */
    fun format(minor: Long, decimals: Boolean = true, signed: Boolean = false, symbol: Boolean = true, options: Display = display): String {
        if (options.hidesAmounts) return HIDDEN + if (symbol) " €" else ""
        if (options.roundsToUnits && decimals) return format((abs(minor) + 50) / 100 * 100 * (if (minor < 0) -1 else 1), false, signed, symbol, options.copy(roundsToUnits = false))
        val units = abs(minor) / 100
        val cents = abs(minor) % 100
        val grouped = units.toString().reversed().chunked(3).joinToString(".").reversed()
        val number = if (decimals) "$grouped,${cents.toString().padStart(2, '0')}" else grouped
        val sign = when {
            minor < 0 -> MINUS.toString()
            signed && minor > 0 && options.plusSign -> "+"
            else -> ""
        }
        return sign + number + if (symbol) " €" else ""
    }

    /** Lo que se escribe en un campo de importe: un número o una cuenta ("12,50+3×2"). */
    fun entered(text: String): Long? = parse(text) ?: AmountExpression.evaluate(text)

    /** Para un campo de texto: "1500,00" (sin miles ni símbolo, coma decimal). */
    fun input(minor: Long): String = format(minor, symbol = false, options = Display.Standard).replace(".", "").replace(MINUS, '-')

    /**
     * Reparte [minor] según porcentajes que suman 100 sin perder céntimos:
     * el resto del redondeo va a las primeras partes.
     */
    fun split(minor: Long, percentages: List<Int>): List<Long> {
        require(percentages.sum() == 100) { "Los porcentajes deben sumar 100" }
        val result = percentages.map { minor * it / 100 }.toMutableList()
        var remainder = minor - result.sum()
        val step = if (remainder >= 0) 1L else -1L
        var i = 0
        while (remainder != 0L) {
            result[i % result.size] += step
            remainder -= step
            i++
        }
        return result
    }
}
