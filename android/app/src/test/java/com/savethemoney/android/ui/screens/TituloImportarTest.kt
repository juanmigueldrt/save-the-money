package com.savethemoney.android.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Test

class TituloImportarTest {
    @Test
    fun botonDeImportarUsaSingularYPlural() {
        assertEquals("Importar 1 movimiento", tituloImportar(1))
        assertEquals("Importar 2 movimientos", tituloImportar(2))
    }
}
