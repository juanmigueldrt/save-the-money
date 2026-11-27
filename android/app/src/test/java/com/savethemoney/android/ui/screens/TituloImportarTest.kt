package com.savethemoney.android.ui.screens

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class TituloImportarTest {
    // El título sale ahora de los recursos (ORC-110) y aquí no hay Android: se mira el plural en strings.xml.
    @Test
    fun botonDeImportarUsaSingularYPlural() {
        val plural = File("src/main/res/values/strings.xml").readText()
            .substringAfter("<plurals name=\"mas_importar_movimientos\">").substringBefore("</plurals>")
        assertTrue("<item quantity=\"one\">Importar %1\$d movimiento</item>" in plural)
        assertTrue("<item quantity=\"other\">Importar %1\$d movimientos</item>" in plural)
    }
}
