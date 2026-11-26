package com.savethemoney.android.ui

import com.savethemoney.android.data.AccountDraft
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.InMemoryFinance
import com.savethemoney.android.data.MovementDraft
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

/** El detalle abre siempre el movimiento tocado, aunque no esté entre los 500 recientes. Datos inventados. */
class SelectionTest {
    private val today = LocalDate.of(2026, 11, 16)

    @Test
    fun selectedMovementIsTheTappedOneEvenOutsideRecent() = runBlocking {
        val service = InMemoryFinance()
        val busy = service.createAccount(AccountDraft("Corriente", AccountKind.Checking), "h")
        val quiet = service.createAccount(AccountDraft("Ahorro", AccountKind.Savings), "h")
        service.addMovement(MovementDraft(quiet.id, null, today.minusYears(2), -1_000, "Antiguo"), "h")
        repeat(501) { service.addMovement(MovementDraft(busy.id, null, today, -100, "Café $it"), "h") }
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()

        // Se toca en la lista de la cuenta de ahorro, que no está en recent.
        val old = model.movements(quiet).single()
        assertEquals(500, model.recent.size)
        assertEquals(null, model.recent.firstOrNull { it.id == old.id })
        assertNull("sin tocarlo no está cargado: la pantalla dice que no lo encuentra", model.movement(old.id))
        model.tappedMovement = old
        assertEquals(old, model.movement(old.id))
        assertNull("el tocado nunca responde por otro id", model.movement("otro"))

        // Editado: se ve el cambio. Borrado: ya no hay detalle, nunca otro movimiento.
        model.update(old.copy(description = "Antiguo editado"))
        assertEquals("Antiguo editado", model.movement(old.id)?.description)
        model.delete(model.movement(old.id)!!)
        assertNull(model.movement(old.id))
    }

    @Test
    fun aCardThatIsGoneIsNeverAnotherOne() = runBlocking {
        val service = InMemoryFinance()
        val visa = service.createAccount(AccountDraft("Visa", AccountKind.CreditCard), "h")
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()
        assertEquals("sin id, la primera tarjeta", visa.id, model.cards.card(null)?.id)
        assertEquals(visa.id, model.cards.card(visa.id)?.id)
        assertNull("una ruta con una tarjeta borrada no abre otra", model.cards.card("borrada"))
    }
}
