package com.savethemoney.android.data

import com.savethemoney.android.ui.FinanceModel
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.LocalDate

/** Apuntar dos veces lo mismo no duplica y no se cambia sobre una versión antigua (ORC-69). Datos inventados. */
class IdempotentWritesTest {
    private val today = LocalDate.of(2026, 11, 5)

    private fun coffee(account: Account, id: String = "m1", amountMinor: Long = -1_250) =
        MovementDraft(account.id, null, today, amountMinor, "Café de prueba", id = id)

    private suspend fun rejected(expected: String, block: suspend () -> Unit) {
        try {
            block()
            fail("debería fallar: $expected")
        } catch (e: AppError) {
            assertEquals(expected, e.message)
        }
    }

    @Test
    fun repeatingTheSameInsertStoresOneRow() = runBlocking {
        val service = InMemoryFinance()
        val checking = service.createAccount(AccountDraft("Corriente", openingMinor = 100_000), "h")
        val savings = service.createAccount(AccountDraft("Ahorro"), "h")

        val first = service.addMovement(coffee(checking), "h")
        assertEquals("el movimiento lleva el identificador que eligió la app", "m1", first.id)
        assertEquals(first, service.addMovement(coffee(checking), "h"))
        assertEquals(1, service.movements("h", null, 50).size)
        assertEquals(98_750L, service.balances("h")[checking.id])

        // Con otro importe, otra cuenta u otro día no se da por guardado: avisa y deja lo que había.
        rejected(TransferDraft.STORED_WITH_OTHER_DATA) { service.addMovement(coffee(checking, amountMinor = -9_999), "h") }
        rejected(TransferDraft.STORED_WITH_OTHER_DATA) { service.addMovement(coffee(savings), "h") }
        rejected(TransferDraft.STORED_WITH_OTHER_DATA) { service.addMovement(coffee(checking).copy(bookedOn = today.plusDays(1)), "h") }
        assertEquals(listOf(-1_250L), service.movements("h", null, 50).map { it.amountMinor })
    }

    /** El movimiento se guarda pero la respuesta no llega (falla la recarga): «Guardar» otra vez lleva el mismo borrador. */
    @Test
    fun savingAgainAfterANetworkErrorDoesNotDuplicate() = runBlocking {
        val backend = InMemoryFinance()
        val checking = backend.createAccount(AccountDraft("Corriente", openingMinor = 100_000), "h")
        var offline = false
        val service = object : FinanceService by backend {
            override suspend fun movements(householdId: String, accountId: String?, limit: Int): List<Movement> {
                if (offline) throw AppError.Network
                return backend.movements(householdId, accountId, limit)
            }
        }
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()
        val draft = coffee(checking)

        offline = true
        // Guardado: el fallo de la recarga queda como problema de carga (ORC-119), no como fallo de guardado.
        model.add(draft)
        assertEquals(AppError.Network.message, model.error)
        offline = false
        model.add(draft)
        assertEquals(listOf("m1"), model.recent.map { it.id })
        assertEquals(98_750L, model.balances[checking.id])
    }

    @Test
    fun updatingAnOldVersionIsRejectedAndReloaded() = runBlocking {
        val service = InMemoryFinance()
        val checking = service.createAccount(AccountDraft("Corriente", openingMinor = 100_000), "h")
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()
        model.add(coffee(checking))
        val read = model.recent.single()
        assertNotNull("cada movimiento guardado tiene versión", read.updatedAt)
        model.tappedMovement = read

        // Otro dispositivo lo cambia mientras este tiene abierta la versión anterior.
        val saved = service.updateMovement(read.copy(amountMinor = -2_000))
        assertNotEquals(read.updatedAt, saved.updatedAt)

        rejected(AppError.MovementChanged.message) { model.update(read.copy(amountMinor = -3_000)) }
        rejected(AppError.MovementChanged.message) { service.updateMovement(saved.copy(updatedAt = null)) }
        assertEquals("se ve lo que guardó el otro dispositivo, no se pisa", listOf(-2_000L), model.recent.map { it.amountMinor })
        assertEquals("el movimiento abierto también se recarga", saved, model.tappedMovement)

        // Con el movimiento recargado, el cambio entra.
        model.update(model.recent.single().copy(amountMinor = -3_000))
        assertEquals(listOf(-3_000L), model.recent.map { it.amountMinor })

        // Uno borrado tampoco se cambia.
        val gone = model.recent.single()
        service.deleteMovement(gone.id)
        rejected(AppError.MovementChanged.message) { service.updateMovement(gone) }
    }

    @Test
    fun versionIsKeptAsTheExactServerText() {
        // Lo que devuelve el servidor: seis decimales y desplazamiento horario.
        val json = """{"id":"m1","household_id":"h","account_id":"a","booked_on":"2026-11-05","amount_minor":-1250,
            "description":"Café de prueba","updated_at":"2026-11-01T10:00:00.123456+00:00"}"""
        val movement = Json.decodeFromString<Movement>(json)
        assertEquals("2026-11-01T10:00:00.123456+00:00", movement.updatedAt)
        assertTrue(AppError.MovementChanged.message.contains("ha cambiado en otro dispositivo"))
        assertTrue(AppError.MovementChanged.message.contains("se ha vuelto a cargar"))
    }
}
