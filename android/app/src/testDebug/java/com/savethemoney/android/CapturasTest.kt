package com.savethemoney.android

import com.savethemoney.android.ui.Route
import com.savethemoney.android.ui.Session
import com.savethemoney.android.ui.screens.SCREEN_COUNT
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CapturasTest {
    @Test
    fun withoutTheHookTheExtraIsIgnored() {
        assertNull(capturaPedida(false, 14))
        assertNull(capturaPedida(false, 33))
    }

    @Test
    fun withTheHookOnlyRealScreensOpen() {
        assertEquals(14, capturaPedida(true, 14))
        assertNull(capturaPedida(true, 0))
        assertNull(capturaPedida(true, SCREEN_COUNT + 1))
    }

    /** En release tiene que ir apagado; testReleaseUnitTest lo comprueba (pide la firma de release, como assembleRelease). */
    @Test
    fun theHookIsNeverCompiledOutsideDebug() {
        assertTrue(BuildConfig.DEBUG || !BuildConfig.CAPTURAS)
    }

    /** Cada pantalla del diseño abre con datos de los modelos: lo que antes inventaba la pantalla sale de la muestra. */
    @Test
    fun laMuestraDaLosDatosDeCadaPantalla() = runBlocking {
        for (pantalla in 1..SCREEN_COUNT) {
            val session = sesionDeMuestra()
            seedSample(session)
            session.start()
            assertTrue(session.state is Session.State.Ready)
            val finance = session.finance!!
            val ruta = prepararPantalla(finance, pantalla)
            assertEquals(pantalla, ruta.screen)
            when (ruta) {
                Route.Movimientos -> assertEquals("Café", finance.lastDeleted?.description)
                is Route.Cuenta -> assertEquals("Cuenta principal", finance.account(ruta.accountId)?.name)
                is Route.AccionesMovimiento -> assertNotNull(finance.movement(ruta.movementId))
                is Route.DetalleMovimiento -> assertNotNull(finance.movement(ruta.movementId))
                Route.Tarjetas -> assertNotNull(finance.cards.card(null)?.let(finance.cards::summary))
                is Route.Tarjeta -> assertNotNull(finance.cards.card(ruta.cardId)?.let(finance.cards::summary))
                is Route.AplazarCompra -> {
                    val compra = finance.cards.movements(finance.cards.card(ruta.cardId)!!).first { it.id == ruta.movementId }
                    assertNotNull(finance.cards.installment(compra))
                }
                Route.Score -> {
                    finance.tracking.loadScores()
                    assertEquals(742, finance.tracking.latestScore?.score)
                }
                is Route.FormPagoFijo -> assertEquals("Streaming", finance.planning.series.firstOrNull { it.id == ruta.seriesId }?.name)
                is Route.Meta -> assertNotNull(finance.planning.goal(ruta.goalId))
                is Route.FormMeta -> assertEquals("Viaje a Lisboa", finance.planning.goal(ruta.goalId!!)?.name)
                Route.Cartera, Route.InversionesRecurrentes -> assertEquals(2, finance.investments.plans.size)
                is Route.Activo -> assertEquals("Fondo indexado mundial", finance.investments.holding(ruta.holdingId)?.name)
                else -> Unit
            }
        }
    }
}
