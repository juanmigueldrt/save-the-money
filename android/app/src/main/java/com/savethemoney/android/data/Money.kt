package com.savethemoney.android.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.math.BigDecimal
import java.math.RoundingMode
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
     * Nulo si no es un importe válido. La regla completa está en [parseNumber].
     */
    fun parse(text: String): Long? {
        val number = parseNumber(text, 2) ?: return null
        // Como mucho 15 cifras enteras: en céntimos cabe de sobra en un Long.
        val total = number.integer.ifEmpty { "0" }.toLong() * 100 + number.fraction.padEnd(2, '0').toLong()
        return if (number.negative) -total else total
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

    /** Un importe con su moneda, para sumar sin mezclar monedas ([total]). */
    data class Amount(val minor: Long, val currency: String = "EUR")

    /** Lo que se enseña en vez de un importe cuando se han mezclado monedas (`Money.mixedText` en iOS). */
    const val MIXED = "Varias monedas"

    /** El servidor no deja cambiar la moneda de un hogar que ya tiene importes (ORC-71): no se convierten. */
    const val BASE_CURRENCY_LOCKED = "No se puede cambiar la moneda del hogar mientras tenga cuentas, presupuestos u otros importes guardados."

    /**
     * Suma sin mezclar monedas, con la misma regla que `Money.+` en iOS: nulo si hay importes de
     * monedas distintas (en pantalla, [MIXED] en vez de una cifra falsa). Un cero no tiene moneda
     * que mezclar: 0 € + 5 $ son 5 $. Para sumar monedas distintas hay que convertir antes con [convert].
     */
    fun total(amounts: List<Amount>): Amount? = amounts.fold<Amount, Amount?>(Amount(0)) { sum, next ->
        when {
            sum == null -> null
            sum.currency == next.currency -> Amount(sum.minor + next.minor, sum.currency)
            next.minor == 0L -> sum
            sum.minor == 0L -> next
            else -> null
        }
    }

    /**
     * Conversión explícita: [minor] por el tipo de cambio (unidades de la moneda de destino por cada
     * unidad de la de origen), redondeado al céntimo más cercano (0,5 se aleja del cero).
     */
    fun convert(minor: Long, rate: BigDecimal): Long = BigDecimal(minor).multiply(rate).setScale(0, RoundingMode.HALF_UP).toLong()

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

/** Un número ya leído por [parseNumber]: solo cifras, sin signo ni separadores. */
internal class ParsedNumber(
    val negative: Boolean,
    /** Parte entera sin separadores de miles. Vacía en ",5". */
    val integer: String,
    /** Decimales tal como se escribieron. Vacía si no había separador decimal. */
    val fraction: String,
)

/**
 * El único lector de números escritos a mano o leídos de un CSV. Lo usan los importes
 * ([Money.parse], 2 decimales) y los precios, participaciones y tipos ([parseDecimal]).
 * iOS aplica la misma regla en `NumberParser` (STMCore); los casos compartidos están en
 * `testdata/vectors/money_parse.json` y `decimal_parse.json`.
 *
 * Principio: si el texto es ambiguo, se rechaza en vez de adivinar. Un importe rechazado
 * se ve en pantalla; uno mal leído, no.
 *
 * 1. Se quitan los espacios, tabuladores y saltos de línea de los extremos, y después «€»,
 *    «EUR», los espacios, U+00A0 y U+202F de cualquier sitio. No se quita nada más:
 *    cualquier otra letra o símbolo invalida el texto.
 * 2. Signo: un «-» o U+2212 delante, uno detrás, o unos paréntesis que lo envuelven todo
 *    significan negativo. Un «+» delante se ignora. Más de una marca de signo (el «+» cuenta)
 *    invalida el texto.
 * 3. Solo pueden quedar cifras, «,» y «.», con al menos una cifra.
 * 4. Con «,» y «.» a la vez: el que aparece el último es el separador decimal y solo puede
 *    estar una vez; el otro agrupa miles.
 * 5. Con un solo tipo, más de una vez: agrupa miles y no hay decimales.
 * 6. Con un solo tipo, una vez: la «,» es siempre el separador decimal (convención española).
 *    El «.» seguido de un número de cifras distinto de 3 es el separador decimal ("12.5", "12.50").
 *    El «.» seguido de exactamente 3 cifras depende del campo: si admite menos de 3 decimales
 *    (importes, tipos) agrupa miles ("1.250" es 1250); si admite 3 o más (participaciones,
 *    precios, comisión) el texto no vale, porque podría ser 1,234 o 1234: se escribe "1,234"
 *    o "1234".
 * 7. Los miles tienen que estar bien formados: el primer grupo tiene de 1 a 3 cifras y no
 *    empieza por «0», y cada grupo siguiente tiene exactamente 3 ("1,2,3", "0.125", "012.345"
 *    y "00.125" no valen).
 * 8. Detrás del separador decimal puede haber como mucho [maxFractionDigits] cifras. Con más
 *    el texto no vale; nunca se redondea ("0,125" no es un importe, y es 0,125 como
 *    participaciones). Un separador decimal al final, sin cifras detrás, se admite y no añade
 *    decimales ("12," es 12 y "5." es 5).
 * 9. La parte entera puede faltar si hay decimales (",5" es 0,5). Un separador solo («,» o «.»)
 *    no vale.
 * 10. Más de 15 cifras enteras no valen.
 */
internal fun parseNumber(text: String, maxFractionDigits: Int): ParsedNumber? {
    var s = text.trim { it in " \t\n\r  " }
    for (ignored in listOf("€", "EUR", " ", " ", " ")) s = s.replace(ignored, "")

    var signs = 0
    var negative = false
    if (s.length >= 2 && s.startsWith('(') && s.endsWith(')')) { signs++; negative = true; s = s.substring(1, s.length - 1) }
    val first = s.firstOrNull()
    if (first == '-' || first == Money.MINUS || first == '+') { signs++; negative = negative || first != '+'; s = s.drop(1) }
    val last = s.lastOrNull()
    if (last == '-' || last == Money.MINUS) { signs++; negative = true; s = s.dropLast(1) }
    if (signs > 1 || s.none { it in '0'..'9' } || !s.all { it in '0'..'9' || it == ',' || it == '.' }) return null

    // Reglas 4 a 6: cuál es el separador decimal, si lo hay.
    val commas = s.count { it == ',' }
    val dots = s.count { it == '.' }
    val decimal: Char? = when {
        commas > 0 && dots > 0 -> s.last { it == ',' || it == '.' }
        commas == 1 -> ','
        dots == 1 && s.length - s.indexOf('.') - 1 != 3 -> '.'
        else -> null
    }
    // Regla 4: el separador decimal solo puede estar una vez.
    val cut = decimal?.let { d -> s.lastIndexOf(d).takeIf { it == s.indexOf(d) } ?: return null }
    val fraction = if (cut == null) "" else s.substring(cut + 1)
    if (fraction.length > maxFractionDigits) return null

    val groups = (if (cut == null) s else s.substring(0, cut)).split(',', '.')
    // Regla 6: sin separador decimal y con dos grupos es un «.» solo con 3 cifras detrás,
    // ambiguo si el campo admite 3 decimales.
    if (cut == null && groups.size == 2 && maxFractionDigits >= 3) return null
    if (groups.size > 1 && (groups[0].length !in 1..3 || groups[0].startsWith('0') || groups.drop(1).any { it.length != 3 })) return null
    val integer = groups.joinToString("")
    return if (integer.length > 15) null else ParsedNumber(negative, integer, fraction)
}
