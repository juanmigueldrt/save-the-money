package com.savethemoney.android.ui

import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.savethemoney.android.data.Money

/**
 * Más opciones > Vista: cómo se enseñan los importes. Se guarda sólo en este dispositivo
 * (DisplayPreferences de iOS). Los PDF y CSV llevan siempre los importes completos.
 */
object Vista {
    private var prefs: SharedPreferences? = null

    /** Ingresos en verde en las listas de movimientos. */
    private var verde by mutableStateOf(true)
    val ingresosEnVerde: Boolean get() = verde

    val incognito: Boolean get() = Money.display.hidesAmounts
    val sinCentimos: Boolean get() = Money.display.roundsToUnits
    val signoMas: Boolean get() = Money.display.plusSign

    fun load(prefs: SharedPreferences) {
        this.prefs = prefs
        Money.display = Money.Display(
            hidesAmounts = prefs.getBoolean(INCOGNITO, false),
            roundsToUnits = prefs.getBoolean(ROUND, false),
            plusSign = prefs.getBoolean(PLUS, true),
        )
        verde = prefs.getBoolean(GREEN, true)
    }

    fun setIncognito(on: Boolean) = save(INCOGNITO, on) { Money.display = Money.display.copy(hidesAmounts = on) }
    fun setSinCentimos(on: Boolean) = save(ROUND, on) { Money.display = Money.display.copy(roundsToUnits = on) }
    fun setSignoMas(on: Boolean) = save(PLUS, on) { Money.display = Money.display.copy(plusSign = on) }
    fun setIngresosEnVerde(on: Boolean) = save(GREEN, on) { verde = on }

    private fun save(key: String, value: Boolean, apply: () -> Unit) {
        apply()
        prefs?.edit()?.putBoolean(key, value)?.apply()
    }

    private const val INCOGNITO = "vista.incognito"
    private const val ROUND = "vista.sinCentimos"
    private const val PLUS = "vista.signoMas"
    private const val GREEN = "vista.ingresosEnVerde"
}
