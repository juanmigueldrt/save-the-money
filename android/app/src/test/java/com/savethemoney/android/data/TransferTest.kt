package com.savethemoney.android.data

import com.savethemoney.android.ui.FinanceModel
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.LocalDate

/** El pago de una tarjeta como transferencia: las dos patas o ninguna, y sin duplicar. Datos inventados. */
class TransferTest {
    private val today = LocalDate.of(2026, 11, 4)

    private fun payment(from: Account, card: Account, id: String = "t1", amountMinor: Long = 30_000, toDescription: String = "Pago de la tarjeta") =
        TransferDraft(id, from.id, card.id, null, today, amountMinor, "Pago de Tarjeta", toDescription)

    @Test
    fun storesBothLegsOnceEvenWhenRepeated() = runBlocking {
        val service = InMemoryFinance()
        val checking = service.createAccount(AccountDraft("Corriente", openingMinor = 100_000), "h")
        val card = service.createAccount(AccountDraft("Tarjeta", AccountKind.CreditCard), "h")
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()

        model.transfer(payment(checking, card))
        assertEquals(70_000L, model.balances[checking.id])
        assertEquals(30_000L, model.balances[card.id])
        assertEquals(listOf(-30_000L, 30_000L), service.addTransfer(payment(checking, card), "h").map { it.amountMinor })

        // La misma petición otra vez (reintento tras un fallo de red): no se apunta nada nuevo.
        model.transfer(payment(checking, card))
        assertEquals(2, model.recent.size)
        assertEquals(70_000L, model.balances[checking.id])

        // Con otro importe, otro día o las cuentas cambiadas no se da por guardada: avisa y deja lo que había.
        val changed = listOf(
            payment(checking, card, amountMinor = 99_900),
            payment(checking, card).copy(bookedOn = today.plusDays(1)),
            payment(card, checking),
        )
        for (draft in changed) {
            try {
                model.transfer(draft)
                fail("con otros datos no se da por guardada: $draft")
            } catch (e: AppError) {
                assertEquals(TransferDraft.STORED_WITH_OTHER_DATA, e.message)
            }
        }
        assertEquals(2, model.recent.size)
        assertEquals(70_000L, model.balances[checking.id])

        // Otro id es otro pago.
        model.transfer(payment(checking, card, id = "t2", amountMinor = 5_000))
        assertEquals(65_000L, model.balances[checking.id])
        assertEquals(35_000L, model.balances[card.id])
    }

    @Test
    fun storesNothingWhenOneLegIsNotValid() = runBlocking {
        val service = InMemoryFinance()
        val checking = service.createAccount(AccountDraft("Corriente", openingMinor = 100_000), "h")
        val card = service.createAccount(AccountDraft("Tarjeta", AccountKind.CreditCard), "h")
        val rejected = listOf(
            payment(checking, card, toDescription = "   "),
            payment(checking, card, amountMinor = 0),
            payment(checking, card, amountMinor = -5_000),
            payment(checking, checking),
        )
        for (draft in rejected) {
            try {
                service.addTransfer(draft, "h")
                fail("no vale: $draft")
            } catch (_: AppError) {
            }
        }
        assertTrue(service.movements("h", null, 10).isEmpty())
        assertEquals(100_000L, service.balances("h")[checking.id])

        // El mismo id sirve para reintentar una transferencia que no se guardó.
        assertEquals(2, service.addTransfer(payment(checking, card), "h").size)
        assertEquals(70_000L, service.balances("h")[checking.id])
    }
}
