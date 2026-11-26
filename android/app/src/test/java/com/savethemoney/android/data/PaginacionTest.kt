package com.savethemoney.android.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

/** ORC-65: las listas se piden por páginas de 1000 y una página fallida hace fallar la carga entera. */
class PaginacionTest {
    private class FalloDePagina : Exception()

    /** Páginas falsas con los tamaños dados; anota los rangos pedidos. */
    private class Paginas(private val tamanos: List<Int>, private val fallaEn: Int? = null) {
        val pedidas = mutableListOf<LongRange>()

        fun pagina(desde: Long, hasta: Long): List<Long> {
            pedidas += desde..hasta
            if (pedidas.size == fallaEn) throw FalloDePagina()
            val tamano = tamanos.getOrElse(pedidas.size - 1) { 0 }
            return (desde until desde + tamano).toList()
        }
    }

    @Test
    fun juntaTodasLasPaginasHastaUnaIncompleta() = runBlocking {
        val paginas = Paginas(listOf(1000, 1000, 37))
        val filas = allPages { desde, hasta -> paginas.pagina(desde, hasta) }
        assertEquals((0L until 2037L).toList(), filas)
        assertEquals(listOf(0L..999L, 1000L..1999L, 2000L..2999L), paginas.pedidas)
    }

    @Test
    fun exactamenteMilFilasPideUnaPaginaMasVacia() = runBlocking {
        val paginas = Paginas(listOf(1000))
        val filas = allPages { desde, hasta -> paginas.pagina(desde, hasta) }
        assertEquals((0L until 1000L).toList(), filas)
        assertEquals(listOf(0L..999L, 1000L..1999L), paginas.pedidas)
    }

    @Test
    fun sinFilasDevuelveListaVacia() = runBlocking {
        val paginas = Paginas(emptyList())
        val filas = allPages { desde, hasta -> paginas.pagina(desde, hasta) }
        assertEquals(emptyList<Long>(), filas)
        assertEquals(listOf(0L..999L), paginas.pedidas)
    }

    @Test
    fun unFalloEnLaSegundaPaginaFallaLaCargaEntera() = runBlocking {
        val paginas = Paginas(listOf(1000, 1000, 37), fallaEn = 2)
        try {
            val filas = allPages { desde, hasta -> paginas.pagina(desde, hasta) }
            fail("Devolvió ${filas.size} filas en vez de fallar")
        } catch (e: FalloDePagina) {
            assertEquals(2, paginas.pedidas.size)
        }
    }
}
