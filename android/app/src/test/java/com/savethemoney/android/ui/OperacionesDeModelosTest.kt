package com.savethemoney.android.ui

import com.savethemoney.android.data.Account
import com.savethemoney.android.data.AccountDraft
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.InMemoryBackend
import com.savethemoney.android.data.InMemoryFinance
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.Username
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

/**
 * Escrituras que terminan aunque se salga de la pantalla, respuestas que se cruzan (como OperacionesDeModelosTests de
 * iOS, ORC-87) y la recarga al volver a primer plano (ORC-122). Datos inventados.
 */
class OperacionesDeModelosTest {
    private val hoy = LocalDate.of(2026, 11, 5)

    /**
     * Retiene la primera llamada que pasa por aquí hasta que la prueba la suelta: así se decide qué respuesta llega antes.
     * Con [cortable] la espera se corta si se cancela quien llamó (una petición de red); sin él, la respuesta llega igual.
     */
    private class Puerta(private val cortable: Boolean = false) {
        private var usada = false
        val llegada = CompletableDeferred<Unit>()
        private val abierta = CompletableDeferred<Throwable?>()

        suspend fun pasar() {
            if (usada) return
            usada = true
            llegada.complete(Unit)
            val fallo = if (cortable) abierta.await() else withContext(NonCancellable) { abierta.await() }
            fallo?.let { throw it }
        }

        fun abrir(fallando: Throwable? = null) {
            abierta.complete(fallando)
        }
    }

    /** La primera lectura de los últimos movimientos se lee en su momento y se entrega cuando la prueba abre la puerta. */
    private class MovimientosConPuerta(private val base: InMemoryFinance) : FinanceService by base {
        val puerta = Puerta()

        override suspend fun movements(householdId: String, accountId: String?, limit: Int): List<Movement> {
            val list = base.movements(householdId, accountId, limit)
            puerta.pasar()
            return list
        }
    }

    /** El movimiento se guarda en el servidor y la respuesta tarda: la petición ya ha salido. */
    private class AltaConPuerta(private val base: InMemoryFinance) : FinanceService by base {
        val puerta = Puerta(cortable = true)

        override suspend fun addMovement(draft: MovementDraft, householdId: String): Movement {
            val saved = base.addMovement(draft, householdId)
            puerta.pasar()
            return saved
        }
    }

    private suspend fun cuenta(base: InMemoryFinance): Account = base.createAccount(AccountDraft("Corriente", openingMinor = 100_000), "h")

    private fun cafe(cuenta: Account, id: String = "m1") = MovementDraft(cuenta.id, null, hoy, -1_250, "Café de prueba", id = id)

    // Respuestas que se cruzan (ORC-87 en iOS)

    @Test
    fun cargaCanceladaQueFallaNoEscribeError() = runBlocking {
        val service = MovimientosConPuerta(InMemoryFinance())
        val model = FinanceModel(Household("h", "Casa"), service, { hoy })

        val carga = launch { model.load() }
        service.puerta.llegada.await()
        carga.cancel()
        service.puerta.abrir(fallando = AppError.Network)
        carga.join()

        assertNull("la tarea cancelada no deja su error en pantalla", model.error)
    }

    @Test
    fun cargaCanceladaQueAcabaBienNoEscribeDatos() = runBlocking {
        val base = InMemoryFinance()
        base.addMovement(cafe(cuenta(base)), "h")
        val service = MovimientosConPuerta(base)
        val model = FinanceModel(Household("h", "Casa"), service, { hoy })

        val carga = launch { model.load() }
        service.puerta.llegada.await()
        carga.cancel()
        service.puerta.abrir()
        carga.join()

        assertEquals("la tarea cancelada no guarda lo que ha traído", emptyList<Movement>(), model.recent)
    }

    @Test
    fun unaRespuestaAntiguaNoPisaUnaMasNueva() = runBlocking {
        val base = InMemoryFinance()
        val corriente = cuenta(base)
        val service = MovimientosConPuerta(base)
        val model = FinanceModel(Household("h", "Casa"), service, { hoy })

        // La primera carga lee sin movimientos y su respuesta se queda en camino.
        val antigua = launch { model.load() }
        service.puerta.llegada.await()

        // Mientras, otro dispositivo apunta un gasto y una carga nueva lo trae.
        base.addMovement(cafe(corriente), "h")
        model.load()
        assertEquals(listOf("m1"), model.recent.map { it.id })

        service.puerta.abrir()
        antigua.join()
        assertEquals("la respuesta antigua no pisa la nueva", listOf("m1"), model.recent.map { it.id })
    }

    @Test
    fun unaCargaAntiguaNoPisaLaRecargaDeUnaEscritura() = runBlocking {
        val base = InMemoryFinance()
        val corriente = cuenta(base)
        val service = MovimientosConPuerta(base)
        val model = FinanceModel(Household("h", "Casa"), service, { hoy })

        // Al volver a primer plano empieza una carga que tarda.
        val antigua = launch { model.load() }
        service.puerta.llegada.await()

        // Se guarda un gasto: la recarga de después ya lo trae.
        model.add(cafe(corriente))
        assertEquals(listOf("m1"), model.recent.map { it.id })
        assertEquals(98_750L, model.balances[corriente.id])

        service.puerta.abrir()
        antigua.join()
        assertEquals("el gasto guardado no desaparece de la lista", listOf("m1"), model.recent.map { it.id })
    }

    @Test
    fun unFalloAntiguoNoPisaUnaCargaMasNuevaQueFueBien() = runBlocking {
        val service = MovimientosConPuerta(InMemoryFinance())
        val model = FinanceModel(Household("h", "Casa"), service, { hoy })

        val antigua = launch { model.load() }
        service.puerta.llegada.await()
        model.load()
        assertNull(model.error)

        service.puerta.abrir(fallando = AppError.Network)
        antigua.join()
        assertNull("lo que hay en pantalla es de la carga nueva, que fue bien", model.error)
    }

    // Escrituras que salen de la pantalla

    @Test
    fun unaEscrituraTerminaAunqueSeSalgaDeLaPantalla() = runBlocking {
        val base = InMemoryFinance()
        val corriente = cuenta(base)
        val service = AltaConPuerta(base)
        val model = FinanceModel(Household("h", "Casa"), service, { hoy })
        model.load()

        // La pantalla guarda y, cuando termina, se cerraría.
        var cerrada = false
        val pantalla = launch {
            model.add(cafe(corriente))
            cerrada = true
        }
        service.puerta.llegada.await()

        // Se pulsa Atrás con la petición ya enviada: la pantalla se va y su trabajo se cancela.
        pantalla.cancel()
        service.puerta.abrir()
        pantalla.join()
        escrituras.children.toList().joinAll()

        assertEquals("la lista se recarga con lo guardado", listOf("m1"), model.recent.map { it.id })
        assertEquals(98_750L, model.balances[corriente.id])
        assertFalse("lo que la pantalla hacía después ya no ocurre", cerrada)
    }

    @Test
    fun unaEscrituraQueFallaSinPantallaAvisaEnElModelo() = runBlocking {
        val base = InMemoryFinance()
        val corriente = cuenta(base)
        val service = AltaConPuerta(base)
        val model = FinanceModel(Household("h", "Casa"), service, { hoy })
        model.load()

        val pantalla = launch { model.add(cafe(corriente)) }
        service.puerta.llegada.await()
        pantalla.cancel()
        service.puerta.abrir(fallando = AppError.Network)
        pantalla.join()
        escrituras.children.toList().joinAll()

        assertEquals("el fallo no se pierde: sale en el error del modelo", AppError.Network.message, model.error)
    }

    @Test
    fun unaEscrituraQueFallaConPantallaLaEnsenaLaPantalla() = runBlocking {
        val base = InMemoryFinance()
        val corriente = cuenta(base)
        val service = AltaConPuerta(base)
        val model = FinanceModel(Household("h", "Casa"), service, { hoy })
        model.load()

        var visto: AppError? = null
        val pantalla = launch {
            try {
                model.add(cafe(corriente))
            } catch (e: AppError) {
                visto = e
            }
        }
        service.puerta.llegada.await()
        service.puerta.abrir(fallando = AppError.Network)
        pantalla.join()

        assertEquals(AppError.Network, visto)
        assertNull("con la pantalla delante el aviso no se duplica en el modelo", model.error)
    }

    // Recarga al volver a primer plano

    /** Cuenta las cargas completas (cada una lee las cuentas una vez) y puede retener la siguiente. */
    private class CargasContadas(private val base: InMemoryFinance) : FinanceService by base {
        var cargas = 0
        var puerta: Puerta? = null

        override suspend fun accounts(householdId: String): List<Account> {
            cargas++
            puerta?.pasar()
            return base.accounts(householdId)
        }
    }

    private suspend fun sesion(service: FinanceService): Session {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        memory.createHousehold("Casa de prueba")
        return Session(memory, service, isDemo = true).also { it.start() }
    }

    @Test
    fun volverAPrimerPlanoRecargaComoMuchoUnaVezPorIntervalo() = runBlocking {
        val service = CargasContadas(InMemoryFinance())
        val session = sesion(service)
        val alEntrar = service.cargas

        session.resume(now = 1_000)
        assertEquals(alEntrar + 1, service.cargas)
        session.resume(now = 1_000 + Session.RESUME_INTERVAL_MS - 1)
        assertEquals("dentro del intervalo no se vuelve a cargar", alEntrar + 1, service.cargas)
        session.resume(now = 1_000 + Session.RESUME_INTERVAL_MS)
        assertEquals(alEntrar + 2, service.cargas)
    }

    @Test
    fun volverAPrimerPlanoNoRecargaConUnaCargaEnMarcha() = runBlocking {
        val service = CargasContadas(InMemoryFinance())
        val session = sesion(service)
        val finance = session.finance!!
        val alEntrar = service.cargas

        // Cortable: si la prueba falla con la carga retenida, se cancela en vez de quedarse esperando.
        service.puerta = Puerta(cortable = true)
        val enMarcha = launch { finance.load() }
        service.puerta!!.llegada.await()
        session.resume(now = 1_000)
        assertEquals("con una carga en marcha no empieza otra", alEntrar + 1, service.cargas)

        service.puerta!!.abrir()
        enMarcha.join()
        session.resume(now = 2_000)
        assertEquals(alEntrar + 2, service.cargas)
    }
}
