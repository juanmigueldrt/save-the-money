package com.savethemoney.android.ui

import androidx.compose.runtime.saveable.SaverScope
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.ui.components.Tab
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class NavTest {
    @Test
    fun goAndBackKeepTheStack() {
        val nav = Nav(Route.Inicio)
        nav.go(Route.Movimientos)
        nav.go(Route.DetalleMovimiento("m1"))
        nav.back()
        assertEquals(listOf(Route.Inicio, Route.Movimientos), nav.stack)
        nav.back()
        nav.back() // la raíz no se quita
        assertEquals(Route.Inicio, nav.current)
        assertFalse(nav.canGoBack)
    }

    @Test
    fun tabAndResetStartANewStack() {
        val nav = Nav(Route.IniciarSesion)
        nav.go(Route.CrearCuenta)
        nav.tab(Tab.Metas)
        assertEquals(listOf<Route>(Route.Metas), nav.stack)
        nav.go(Route.Meta("g1"))
        nav.reset(Route.IniciarSesion)
        assertEquals(listOf<Route>(Route.IniciarSesion), nav.stack)
    }

    /** Lo que se guarda al girar la pantalla vuelve igual: las mismas pantallas, en el mismo orden y con sus argumentos. */
    @Test
    fun laPilaSobreviveAGuardarYRestaurar() {
        val nav = Nav(Route.Inicio)
        val rutas = listOf(
            Route.Cuenta("a1"),
            Route.FormMovimiento(accountId = "a1", transfer = true, toAccountId = "t1", cardPayment = true),
            Route.FormMovimiento(movementId = "m1"),
            Route.FormMovimiento(),
            Route.FormCuenta(kind = AccountKind.CreditCard),
            Route.FormCuenta("a1"),
            Route.Tarjeta(null),
            Route.AplazarCompra("t1", "m1"),
            Route.AplazarCompra("t1"),
            Route.FormExtra(),
            Route.ConfirmarCargo("c1"),
        )
        rutas.forEach(nav::go)

        val guardada = with(Nav.Saver) { SaverScope { true }.save(nav) }!!
        val vuelta = Nav.Saver.restore(guardada)!!

        assertEquals(listOf(Route.Inicio) + rutas, vuelta.stack)
    }

    /** Cada pantalla, con argumentos y sin ellos, se lee igual que se escribió. */
    @Test
    fun cadaRutaSeLeeComoSeEscribio() {
        for (n in 1..Route.LAST) {
            val ruta = Route.decode("$n") ?: Route.decode(conArgumentos(n))
            requireNotNull(ruta) { "la pantalla $n no se lee" }
            assertEquals(n, ruta.screen)
            assertEquals(ruta, Route.decode(ruta.encode()))
        }
    }

    /** Lo guardado por otra versión o roto no tumba la app: se salta, y sin nada que abrir se empieza de cero. */
    @Test
    fun loQueNoSeEntiendeSeSalta() {
        assertNull(Route.decode(""))
        assertNull(Route.decode("99"))
        assertNull(Route.decode("x"))
        assertNull("le falta el id", Route.decode("6"))
        assertNull("le sobra un argumento", Route.decode("4|a"))
        assertNull(Route.decode("9|a1|NoExiste"))
        assertNull(Route.decode("7||||"))

        val restaurada = Nav.Saver.restore(arrayListOf("4", "99", "6|a1"))!!
        assertEquals(listOf(Route.Inicio, Route.Cuenta("a1")), restaurada.stack)
        assertNull("nada que abrir: se empieza de cero", Nav.Saver.restore(arrayListOf("99")))
    }

    private fun conArgumentos(n: Int): String = when (n) {
        7 -> "7|m1|a1|false|t1|false"
        9 -> "9|a1|Savings"
        13 -> "13|t1|m1"
        else -> "$n|x1"
    }
}
