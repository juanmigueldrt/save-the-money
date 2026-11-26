package com.savethemoney.android.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Regla y estado del bloqueo, sin el diálogo del sistema (AppLockTests en iOS). */
class BloqueoTest {
    private val salida = 1_000_000L

    @Test
    fun desactivadoNuncaBloquea() {
        assertFalse(Bloqueo.debeBloquear(false, 0L, salida))
    }

    @Test
    fun sinSalirDeLaAppNoBloquea() {
        assertFalse(Bloqueo.debeBloquear(true, null, salida))
    }

    @Test
    fun dentroDelMargenNoBloqueaYAlCumplirseSi() {
        assertEquals(60_000L, Bloqueo.GRACIA_MS)
        assertFalse(Bloqueo.debeBloquear(true, salida, salida + 59_999))
        assertTrue(Bloqueo.debeBloquear(true, salida, salida + 60_000))
    }

    @Test
    fun tiempoHaciaAtrasBloquea() {
        assertTrue(Bloqueo.debeBloquear(true, salida, salida - 1))
    }

    @Test
    fun activadoArrancaBloqueadaAntesDeLaPrimeraVuelta() {
        val bloqueo = Bloqueo().apply { arranca(activo = true, seguro = true) }
        assertTrue(bloqueo.bloqueada)
    }

    @Test
    fun desactivadoOSinCodigoArrancaAbierta() {
        assertFalse(Bloqueo().apply { arranca(activo = false, seguro = true) }.bloqueada)
        assertFalse(Bloqueo().apply { arranca(activo = true, seguro = false) }.bloqueada)
    }

    @Test
    fun recrearLaActividadNoVuelveABloquear() {
        val bloqueo = Bloqueo().apply { arranca(activo = true, seguro = true) }
        bloqueo.alVolver(salida, seguro = true)
        bloqueo.empiezaAutenticar(seguro = true)
        bloqueo.terminaAutenticar(true)
        bloqueo.arranca(activo = true, seguro = true)
        assertFalse(bloqueo.bloqueada)
    }

    @Test
    fun enlaceConLaAppBloqueadaEsperaAlDesbloqueo() {
        val bloqueo = Bloqueo().apply { arranca(activo = true, seguro = true) }
        var abierto = 0
        bloqueo.cuandoAbierta(salida, seguro = true) { abierto++ }
        assertEquals(0, abierto)
        bloqueo.alVolver(salida, seguro = true)
        bloqueo.empiezaAutenticar(seguro = true)
        bloqueo.terminaAutenticar(true)
        assertEquals(1, abierto)
        bloqueo.cuandoAbierta(salida, seguro = true) { abierto++ }
        assertEquals("Desbloqueada, el enlace se abre ya", 2, abierto)
    }

    @Test
    fun enlaceAlVolverTrasElMargenEsperaAunqueNoSeHayaBloqueadoTodavia() {
        val bloqueo = Bloqueo().apply { arranca(activo = true, seguro = true) }
        bloqueo.alVolver(salida, seguro = true)
        bloqueo.empiezaAutenticar(seguro = true)
        bloqueo.terminaAutenticar(true)
        bloqueo.alSalir(salida)
        var abierto = false
        // onNewIntent llega antes que onStart.
        bloqueo.cuandoAbierta(salida + 120_000, seguro = true) { abierto = true }
        assertFalse(abierto)
        assertTrue(bloqueo.alVolver(salida + 120_000, seguro = true))
        bloqueo.empiezaAutenticar(seguro = true)
        bloqueo.terminaAutenticar(true)
        assertTrue(abierto)
    }

    @Test
    fun enlaceConElBloqueoDesactivadoSeAbreYa() {
        var abierto = false
        Bloqueo().cuandoAbierta(salida, seguro = true) { abierto = true }
        assertTrue(abierto)
    }

    @Test
    fun desactivadoNoPideAlArrancar() {
        val bloqueo = Bloqueo()
        assertFalse(bloqueo.alVolver(salida, seguro = true))
        assertFalse(bloqueo.bloqueada)
    }

    @Test
    fun alArrancarPideYSeAbreAlAutenticarse() {
        val bloqueo = Bloqueo().apply { activar(true) }
        assertTrue(bloqueo.alVolver(salida, seguro = true))
        assertTrue(bloqueo.bloqueada)
        assertTrue(bloqueo.empiezaAutenticar(seguro = true))
        assertFalse("No se lanzan dos diálogos a la vez", bloqueo.empiezaAutenticar(seguro = true))
        bloqueo.terminaAutenticar(true)
        assertFalse(bloqueo.bloqueada)
    }

    @Test
    fun siSeCancelaSigueBloqueadaYElDialogoNoCuentaComoSalir() {
        val bloqueo = Bloqueo().apply { activar(true) }
        bloqueo.alVolver(salida, seguro = true)
        bloqueo.empiezaAutenticar(seguro = true)
        // Android 9: la pantalla del código para la actividad.
        bloqueo.alSalir(salida)
        bloqueo.terminaAutenticar(false)
        assertFalse(bloqueo.alVolver(salida + 120_000, seguro = true))
        assertTrue(bloqueo.bloqueada)
    }

    @Test
    fun volverTrasElMargenVuelveAPedir() {
        val bloqueo = Bloqueo().apply { activar(true) }
        bloqueo.alVolver(salida, seguro = true)
        bloqueo.empiezaAutenticar(seguro = true)
        bloqueo.terminaAutenticar(true)
        bloqueo.alSalir(salida)
        assertFalse(bloqueo.alVolver(salida + 30_000, seguro = true))
        bloqueo.alSalir(salida + 30_000)
        assertTrue(bloqueo.alVolver(salida + 90_000, seguro = true))
        assertTrue(bloqueo.bloqueada)
    }

    @Test
    fun sinCodigoEnElDispositivoNuncaDejaFuera() {
        val bloqueo = Bloqueo().apply { activar(true) }
        bloqueo.alVolver(salida, seguro = true)
        assertTrue(bloqueo.bloqueada)
        assertFalse(bloqueo.empiezaAutenticar(seguro = false))
        assertFalse(bloqueo.bloqueada)
        assertFalse(bloqueo.alVolver(salida, seguro = false))
    }
}
