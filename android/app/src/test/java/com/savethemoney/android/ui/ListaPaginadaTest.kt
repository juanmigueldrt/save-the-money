package com.savethemoney.android.ui

import com.savethemoney.android.data.AccountDraft
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.InMemoryFinance
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.MovementSearch
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/** ORC-85: la lista de movimientos se carga por páginas y busca en el servidor, sin pisar lo nuevo con lo viejo. Datos inventados. */
class ListaPaginadaTest {
    private val hoy = LocalDate.of(2026, 11, 5)
    private val pagina = FinanceModel.LIST_PAGE_SIZE

    /**
     * El servicio en memoria, pero la primera página de la lista que cumple [retener] se lee en su momento y se entrega cuando
     * la prueba abre la puerta. Con [falla] a true, las páginas fallan como sin red.
     */
    private class ListaConPuerta(
        private val base: InMemoryFinance,
        private val retener: (MovementSearch?, Movement?) -> Boolean = { _, _ -> false },
    ) : FinanceService by base {
        var falla = false
        private var usada = false
        val llegada = CompletableDeferred<Unit>()
        val abierta = CompletableDeferred<Unit>()

        override suspend fun movements(householdId: String, accountId: String?, search: MovementSearch?, after: Movement?, limit: Int): List<Movement> {
            if (falla) throw AppError.Network
            val page = base.movements(householdId, accountId, search, after, limit)
            if (!usada && retener(search, after)) {
                usada = true
                llegada.complete(Unit)
                abierta.await()
            }
            return page
        }
    }

    /** Un hogar con [count] gastos («Gasto n») y, si se pide, uno muy antiguo («Panadería antigua»). */
    private suspend fun hogar(count: Int, antiguo: Boolean = false): Pair<InMemoryFinance, String> {
        val base = InMemoryFinance()
        val cuenta = base.createAccount(AccountDraft("Corriente"), "h")
        val inicio = LocalDate.of(2026, 1, 1)
        val drafts = (0 until count).map {
            MovementDraft(cuenta.id, null, inicio.plusDays((it % 300).toLong()), -100L - it, "Gasto $it", importHash = "h$it")
        } + listOfNotNull(
            if (antiguo) MovementDraft(cuenta.id, null, LocalDate.of(2019, 5, 1), -350, "Panadería antigua", importHash = "viejo") else null,
        )
        base.importMovements(drafts, "h")
        return base to cuenta.id
    }

    @Test
    fun cargaMasAlLlegarAlFinal() = runBlocking {
        val (base, _) = hogar(pagina + 5)
        val model = FinanceModel(Household("h", "Casa"), base, { hoy })

        model.showList(null, "")
        assertEquals(pagina, model.list.rows.size)
        assertTrue(model.list.hasMore)

        model.loadMoreList()
        assertEquals(pagina + 5, model.list.rows.size)
        assertEquals("ninguna fila repetida", pagina + 5, model.list.rows.map { it.id }.toSet().size)
        assertFalse(model.list.hasMore)
        assertNull(model.listError)
    }

    @Test
    fun unaPaginaQueFallaAvisaYNoPareceElFinal() = runBlocking {
        val (base, _) = hogar(pagina + 5)
        val service = ListaConPuerta(base)
        val model = FinanceModel(Household("h", "Casa"), service, { hoy })
        model.showList(null, "")
        val cargadas = model.list.rows

        service.falla = true
        model.loadMoreList()
        assertEquals("lo cargado se queda", cargadas, model.list.rows)
        assertTrue("no parece el final de la lista", model.list.hasMore)
        assertNotNull(model.listError)

        service.falla = false
        model.retryList()
        assertEquals(pagina + 5, model.list.rows.size)
        assertNull(model.listError)
    }

    @Test
    fun laBusquedaEncuentraFueraDeLaPrimeraPagina() = runBlocking {
        val (base, _) = hogar(600, antiguo = true)
        val model = FinanceModel(Household("h", "Casa"), base, { hoy })
        model.load()
        assertFalse("no está entre los recientes", model.recent.any { it.description == "Panadería antigua" })

        model.showList(null, "  panadería ")
        assertEquals(listOf("Panadería antigua"), model.list.rows.map { it.description })
        assertFalse(model.list.hasMore)
    }

    @Test
    fun laListaDeUnaCuentaSoloTraeEsaCuenta() = runBlocking {
        val (base, _) = hogar(3)
        val otra = base.createAccount(AccountDraft("Ahorro"), "h")
        base.addMovement(MovementDraft(otra.id, null, hoy, 500, "Ingreso"), "h")
        val model = FinanceModel(Household("h", "Casa"), base, { hoy })

        model.showList(otra.id, "")
        assertEquals(listOf(otra.id), model.list.rows.map { it.accountId })
    }

    @Test
    fun unaBusquedaViejaNoPisaLaNueva() = runBlocking {
        val (base, _) = hogar(3, antiguo = true)
        val service = ListaConPuerta(base) { search, _ -> search?.text == "gasto" }
        val model = FinanceModel(Household("h", "Casa"), service, { hoy })

        val vieja = launch { model.showList(null, "gasto") }
        service.llegada.await()
        model.showList(null, "panadería")
        service.abierta.complete(Unit)
        vieja.join()

        assertEquals("panadería", model.list.search)
        assertEquals("la respuesta de «gasto» llegó tarde y no cuenta", listOf("Panadería antigua"), model.list.rows.map { it.description })
    }

    @Test
    fun unaPaginaViejaNoPisaLaListaRecargada() = runBlocking {
        val (base, cuenta) = hogar(pagina + 5)
        val service = ListaConPuerta(base) { _, after -> after != null }
        val model = FinanceModel(Household("h", "Casa"), service, { hoy })
        model.showList(null, "")

        val siguiente = launch { model.loadMoreList() }
        service.llegada.await()
        // Mientras tanto se apunta uno nuevo: la recarga trae la lista al día.
        model.add(MovementDraft(cuenta, null, LocalDate.of(2027, 1, 1), -1, "Nuevo"))
        val recargada = model.list
        assertEquals("Nuevo", recargada.rows.first().description)
        service.abierta.complete(Unit)
        siguiente.join()

        assertEquals("la página pedida antes de la recarga llegó tarde y no cuenta", recargada, model.list)
    }
}
