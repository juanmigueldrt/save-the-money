package com.savethemoney.android.data

import com.savethemoney.android.ui.FinanceModel
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.LocalDate

/** Una transferencia es una sola operación: sus dos patas se cambian y se borran juntas (ORC-75). Datos inventados. */
class TransferenciasEnlazadasTest {
    private val today = LocalDate.of(2026, 11, 4)

    private suspend fun casa(): Triple<FinanceModel, Account, Account> {
        val service = InMemoryFinance()
        val corriente = service.createAccount(AccountDraft("Corriente", openingMinor = 100_000), "h")
        val ahorro = service.createAccount(AccountDraft("Ahorro"), "h")
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()
        model.transfer(TransferDraft("t1", corriente.id, ahorro.id, null, today, 30_000, "Al ahorro", "Al ahorro"))
        return Triple(model, corriente, ahorro)
    }

    @Test
    fun cambiarImporteYDiaDeUnaPataCambiaLaOtra() = runBlocking {
        val (model, corriente, ahorro) = casa()
        assertEquals(listOf("t1", "t1"), model.recent.map { it.transferId })
        val entrada = model.recent.first { !it.isExpense }
        model.update(entrada.copy(amountMinor = 25_000, bookedOn = "2026-11-06", notes = "Solo en la entrada"))

        val salida = model.recent.first { it.isExpense }
        assertEquals(-25_000L, salida.amountMinor)
        assertEquals("2026-11-06", salida.bookedOn)
        assertNull("lo demás de la otra pata no se toca", salida.notes)
        assertEquals(75_000L, model.balances[corriente.id])
        assertEquals(25_000L, model.balances[ahorro.id])
    }

    @Test
    fun cambiarLasDosPatasALaVezNoFalla() = runBlocking {
        val (model, corriente, _) = casa()
        // Edición masiva de la fecha con las dos patas elegidas.
        model.update(MovementBulkEdit(bookedOn = today.plusDays(2)).changes(model.recent))
        assertEquals(setOf("2026-11-06"), model.recent.map { it.bookedOn }.toSet())
        assertEquals(70_000L, model.balances[corriente.id])
    }

    @Test
    fun unaPataNoCambiaDeSigno() = runBlocking {
        val (model, _, _) = casa()
        val salida = model.recent.first { it.isExpense }
        try {
            model.update(salida.copy(amountMinor = 30_000))
            fail("la salida no se vuelve positiva")
        } catch (e: AppError) {
            assertTrue(e is AppError.InvalidInput)
        }
        assertEquals(listOf(-30_000L, 30_000L), model.recent.map { it.amountMinor }.sorted())
    }

    @Test
    fun borrarUnaPataBorraLasDosSinDeshacer() = runBlocking {
        val (model, corriente, ahorro) = casa()
        model.delete(model.recent.first { !it.isExpense })
        assertTrue(model.recent.isEmpty())
        assertEquals(100_000L, model.balances[corriente.id])
        assertEquals(0L, model.balances[ahorro.id])
        assertNull("deshacer volvería a apuntar solo una pata", model.lastDeleted)
    }

    @Test
    fun borrarLasDosPatasElegidasNoFalla() = runBlocking {
        val (model, corriente, _) = casa()
        model.delete(model.recent)
        assertTrue(model.recent.isEmpty())
        assertEquals(100_000L, model.balances[corriente.id])
    }
}
