package com.savethemoney.android

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
            prepararPantalla(finance, pantalla)
            when (pantalla) {
                5 -> assertEquals("Café", finance.lastDeleted?.description)
                6 -> assertEquals("Cuenta principal", finance.selectedAccount?.name)
                8, 34 -> assertNotNull(finance.selectedMovement)
                10, 11 -> assertNotNull(finance.cards.selected?.let(finance.cards::summary))
                13 -> {
                    val compra = finance.cards.movements(finance.cards.selected!!).first { it.id == finance.cards.purchaseId }
                    assertNotNull(finance.cards.installment(compra))
                }
                19 -> {
                    finance.tracking.loadScores()
                    assertEquals(742, finance.tracking.latestScore?.score)
                }
                21 -> assertEquals("Streaming", finance.planning.seriesToEdit?.name)
                23 -> assertNotNull(finance.planning.selectedGoal)
                24 -> assertEquals("Viaje a Lisboa", finance.planning.goalToEdit?.name)
                25, 27 -> assertEquals(2, finance.investments.plans.size)
                26 -> assertEquals("Fondo indexado mundial", finance.investments.selected?.name)
            }
        }
    }
}
