package com.savethemoney.android

import com.savethemoney.android.ui.screens.SCREEN_COUNT
import org.junit.Assert.assertEquals
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
}
