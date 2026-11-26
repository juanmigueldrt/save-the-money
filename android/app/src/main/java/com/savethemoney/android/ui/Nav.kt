package com.savethemoney.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.setValue
import com.savethemoney.android.ui.components.Tab

/** Pila de pantallas, cada una con sus argumentos ([Route]). */
class Nav(stack: List<Route>) {
    constructor(start: Route) : this(listOf(start))

    init { require(stack.isNotEmpty()) }

    var stack by mutableStateOf(stack)
        private set

    val current: Route get() = stack.last()

    /** Abre una pantalla encima de la actual. */
    fun go(route: Route) { stack = stack + route }

    /** Cambia de pestaña: la pila empieza en la raíz de esa pestaña. */
    fun tab(tab: Tab) { stack = listOf(tab.route) }

    /** Vacía la pila (p. ej. tras entrar o borrar datos). */
    fun reset(route: Route) { stack = listOf(route) }

    fun back() { if (stack.size > 1) stack = stack.dropLast(1) }

    val canGoBack: Boolean get() = stack.size > 1

    companion object {
        /**
         * Guarda la pila como texto para `rememberSaveable`: vuelve igual tras girar la pantalla o si Android cierra la app.
         * Lo que no se entienda al leerla se salta; si no queda nada, se empieza de cero.
         */
        val Saver: Saver<Nav, ArrayList<String>> = Saver(
            save = { nav -> ArrayList(nav.stack.map(Route::encode)) },
            restore = { saved -> saved.mapNotNull(Route::decode).takeIf { it.isNotEmpty() }?.let(::Nav) },
        )
    }
}
