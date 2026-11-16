package com.savethemoney.android.data

import com.savethemoney.android.ui.FinanceModel
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.LocalDate

/** Tipo de compra al apuntar un gasto en una tarjeta: a plazos o recurrente. Datos inventados. */
class CardPurchaseTest {
    private val today = LocalDate.of(2026, 11, 16)

    @Test
    fun quoteAddsInterest() {
        val q = CardPurchase.quote(60_000, 6, 14.0)
        assertEquals(CardInstallment.payment(60_000, 6, 14.0), q.monthly)
        assertEquals(q.monthly * 6, q.total)
        assertEquals(q.total - 60_000, q.interest)
        assertTrue(q.interest > 0)
        assertEquals(0L, CardPurchase.quote(60_000, 6, 0.0).interest)
    }

    @Test
    fun seriesStartsOnPurchaseAndPendsFromNextDay() {
        val m = Movement("m", "h", "card", "cat", "2026-11-16", -1299, " Streaming ")
        val s = CardPurchase.series(m, Recurrence.Monthly)
        assertEquals("Streaming", s.name)
        assertEquals(RecurringKind.Subscription, s.kind)
        assertEquals(1299L, s.amountMinor)
        assertEquals("card", s.accountId)
        assertEquals("cat", s.categoryId)
        assertEquals("2026-11-16", s.startsOn)
        assertEquals("2026-11-17", s.pendingFrom)
        assertTrue(s.createsPending)
        // El cargo del mismo día ya está apuntado: no sale como pendiente.
        assertTrue(PendingCharges.missing(listOf(s.copy(id = "s")), emptyList(), today).isEmpty())
        assertEquals(1, PendingCharges.missing(listOf(s.copy(id = "s")), emptyList(), LocalDate.of(2026, 12, 16)).size)
    }

    @Test
    fun addsMovementWithInstallmentOrSeries() = runBlocking {
        val service = InMemoryFinance()
        val card = service.createAccount(AccountDraft("Tarjeta", AccountKind.CreditCard), "h")
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()
        model.addCardPurchase(MovementDraft(card.id, null, today, -30_000, "Portátil"), CardPurchase.Installments(12))
        val plan = service.cardInstallments("h").single()
        assertEquals(12, plan.months)
        assertEquals(14.0, plan.rate, 0.0)
        assertEquals(model.recent.first { it.description == "Portátil" }.id, plan.movementId)

        model.addCardPurchase(MovementDraft(card.id, null, today, -999, "Música"), CardPurchase.Recurring(Recurrence.Monthly))
        assertNotNull(model.planning.series.firstOrNull { it.name == "Música" && it.accountId == card.id })
        assertTrue(model.planning.pending.isEmpty())

        // Plazos fuera de 2–48: no se guarda nada.
        val before = model.recent.size
        try {
            model.addCardPurchase(MovementDraft(card.id, null, today, -5_000, "Raro"), CardPurchase.Installments(60))
            fail("60 plazos no vale")
        } catch (_: AppError) {
        }
        assertEquals(before, model.recent.size)
    }
}
