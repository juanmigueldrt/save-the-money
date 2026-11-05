package com.savethemoney.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.savethemoney.android.ui.components.Tab

/** Pila de pantallas. Los números son los de las pantallas del diseño (01–34). */
class Nav(start: Int) {
    var stack by mutableStateOf(listOf(start))
        private set

    val current: Int get() = stack.last()

    /** Abre una pantalla encima de la actual. */
    fun go(screen: Int) { stack = stack + screen }

    /** Cambia de pestaña: la pila empieza en la raíz de esa pestaña. */
    fun tab(tab: Tab) { stack = listOf(tab.screen) }

    /** Vacía la pila (p. ej. tras entrar o borrar datos). */
    fun reset(screen: Int) { stack = listOf(screen) }

    fun back() { if (stack.size > 1) stack = stack.dropLast(1) }

    val canGoBack: Boolean get() = stack.size > 1
}
