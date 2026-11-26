package com.savethemoney.android.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TasaTarjetaTest {
    @Test
    fun tasaSoloAceptaNumerosPositivosEnFormatoDeEspana() {
        assertEquals(21.5, leerTasa("21,5")!!, 0.0)
        assertEquals(14.0, leerTasa("14")!!, 0.0)
        assertNull(leerTasa("NaN"))
        assertNull(leerTasa("Infinity"))
        assertNull(leerTasa("1e2"))
        assertNull(leerTasa("-3"))
        assertNull(leerTasa(""))
    }
}
