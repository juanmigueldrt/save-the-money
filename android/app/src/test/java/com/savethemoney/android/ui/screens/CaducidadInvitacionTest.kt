package com.savethemoney.android.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

class CaducidadInvitacionTest {
    @Test
    fun horasHastaLaCaducidadConFormatoDelServidor() {
        val ahora = Instant.parse("2026-11-26T08:00:00Z")
        assertEquals(2L, horasHasta("2026-11-26T10:00:00.123456+00:00", ahora))
        assertEquals(2L, horasHasta("2026-11-26T11:00:00.123456+01:00", ahora))
        assertEquals(2L, horasHasta("2026-11-26T10:00:00Z", ahora))
    }

    @Test
    fun sinHorasSiLaFechaNoSeEntiende() {
        val ahora = Instant.parse("2026-11-26T08:00:00Z")
        assertEquals(1L, horasHasta("2026-11-26T08:30:00Z", ahora))
        assertNull(horasHasta("", ahora))
        assertNull(horasHasta("mañana a las diez", ahora))
        assertNull(horasHasta("2026-11-26T10:00:00.123456", ahora))
    }
}
