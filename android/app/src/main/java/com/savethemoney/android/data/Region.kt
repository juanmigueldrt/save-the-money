package com.savethemoney.android.data

import java.util.Locale

/**
 * El único punto que decide la región y la moneda por defecto (ORC-110). Para llevar la app a otra región
 * se cambia aquí; cada hogar y cada cuenta guardan además su propia moneda.
 */
object Region {
    /** Formato de números y fechas, y reglas de orden, mayúsculas y acentos al comparar textos. */
    val locale: Locale = Locale.forLanguageTag("es-ES")

    /** Moneda de lo que aún no tiene una propia. */
    const val CURRENCY = "EUR"
}
