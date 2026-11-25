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

        assertNull("sin tocar nada no hay detalle", model.selectedMovement)

        // Se toca en la lista de la cuenta de ahorro, que no está en recent.
        val old = model.movements(quiet).single()
        assertEquals(500, model.recent.size)
        assertEquals(null, model.recent.firstOrNull { it.id == old.id })
        model.tappedMovement = old
        assertEquals(old, model.selectedMovement)

        // Editado: se ve el cambio. Borrado: ya no hay detalle, nunca otro movimiento.
        model.update(old.copy(description = "Antiguo editado"))
        assertEquals("Antiguo editado", model.selectedMovement?.description)
        model.delete(model.selectedMovement!!)
        assertNull(model.selectedMovement)
    }

    @Test
    fun selectedAccountIsNeverAnotherOne() = runBlocking {
        val service = InMemoryFinance()
        service.createAccount(AccountDraft("Corriente", AccountKind.Checking), "h")
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()
        assertNull(model.selectedAccount)
        model.selectedAccountId = "borrada"
        assertNull(model.selectedAccount)
    }
}
