package com.savethemoney.android.data

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.util.UUID

/** Los mismos casos que CreditCardTests.swift, para que Android e iOS calculen igual. Datos inventados. */
class CreditCardTest {
    private val home = "home"
    private val card = "card"
    private val transfer = "transfer"

    private fun day(y: Int, m: Int, d: Int) = LocalDate.of(y, m, d)

    private fun move(amount: Long, on: LocalDate, payment: Boolean = false) = Movement(
        UUID.randomUUID().toString(), home, card, if (payment) transfer else null, on.toString(), amount,
        if (payment) "Pago de la tarjeta" else "Compra de prueba",
    )

    private fun terms(mode: CardPaymentMode = CardPaymentMode.Full, fixed: Long? = null) =
        CreditCardTerms(card, home, 300_000, paymentMode = mode, fixedPayment = fixed)

    private fun summary(t: CreditCardTerms, movements: List<Movement>, installments: List<CardInstallment> = emptyList(), today: LocalDate) =
        CreditCardCalculator.summary(t, movements.sumOf { it.amountMinor }, movements, installments, setOf(transfer), today)

    @Test fun cycleDates() {
        val t = terms()
        assertEquals(day(2027, 2, 1), t.statementClosing(day(2027, 1, 1)))
        assertEquals(day(2027, 2, 1), t.statementClosing(day(2027, 1, 31)))
        assertEquals(day(2027, 3, 1), t.paymentDate(day(2027, 2, 1)))
        val other = t.copy(statementDay = 25, paymentDelayMonths = 0, paymentDay = 10)
        assertEquals(day(2027, 1, 25), other.statementClosing(day(2027, 1, 24)))
        assertEquals(day(2027, 2, 25), other.statementClosing(day(2027, 1, 25)))
        assertEquals(day(2027, 1, 10), other.paymentDate(day(2027, 1, 25)))
        assertEquals(day(2027, 1, 25), other.cycleStart(day(2027, 2, 25)))
    }

    @Test fun fullPaymentEachMonth() {
        val movements = listOf(
            move(-15_000, day(2026, 9, 5)),
            move(15_000, day(2026, 11, 1), payment = true),
            move(-20_000, day(2026, 10, 10)),
            move(-10_000, day(2026, 10, 20)),
            move(2_000, day(2026, 10, 25)),
            move(-5_000, day(2026, 11, 2)),
        )
        val s = summary(terms(), movements, today = day(2026, 11, 4))
        assertEquals(33_000L, s.used)
        assertEquals(267_000L, s.available)
        assertEquals(day(2026, 12, 1), s.openStatement)
        assertEquals(5_000L, s.spentThisCycle)
        assertEquals(6, s.payments.size)
        assertEquals(day(2026, 12, 1), s.next?.due)
        assertEquals(28_000L, s.next?.amount)
        assertEquals(false, s.next?.isEstimate)
        assertEquals(day(2027, 1, 1), s.payments[1].due)
        assertEquals(5_000L, s.payments[1].amount)
        assertTrue(s.payments[1].isEstimate)
        assertEquals(0L, s.payments[2].amount)
        assertEquals(0L, s.interestInPayments)
        assertNull(s.payoff)
        assertFalse(s.isOverAlert)
    }

    @Test fun installmentsAddToEachPayment() {
        val purchase = move(-60_000, day(2026, 11, 3))
        val movements = listOf(move(-28_000, day(2026, 10, 10)), move(-5_000, day(2026, 11, 2)), purchase)
        val plan = CardInstallment("p", home, card, purchase.id, 6, 14.0)
        val s = summary(terms(), movements, listOf(plan), day(2026, 11, 4))
        assertEquals(10_412L, CardInstallment.payment(60_000, 6, 14.0))
        assertEquals(93_000L, s.used)
        assertEquals(5_000L, s.spentThisCycle)
        assertEquals(28_000L, s.payments[0].amount)
        assertEquals(5_000L + 10_412L, s.payments[1].amount)
        assertEquals(10_412L, s.payments[1].installments)
        assertEquals(700L, s.payments[1].interest)
        assertEquals(10_412L, s.payments[2].amount)
        val rows = CreditCardCalculator.amortization(60_000, 6, 14.0)
        assertEquals(60_000L, rows.sumOf { it.principal })
        assertEquals(10_414L, rows.last().payment)
        assertEquals(10_000L, CardInstallment.payment(30_000, 3, 0.0))
        assertEquals(6, CreditCardCalculator.remainingInstallments(plan, purchase, s))
    }

    @Test fun minimumPaymentWithInterest() {
        val s = summary(terms(CardPaymentMode.Minimum), listOf(move(-100_000, day(2026, 9, 5))), today = day(2026, 11, 4))
        assertEquals(100_000L, s.revolvingBalance)
        assertEquals(4_667L, s.next?.amount)
        assertEquals(1_667L, s.next?.interest)
        assertEquals(4_527L, s.payments[1].amount)
        assertTrue(s.interestInPayments > 0)
        val payoff = s.payoff!!
        assertTrue(payoff.months > 24)
        assertTrue(payoff.interest > 10_000)
    }

    @Test fun minimumNeverBelowFloorNorAboveDebt() {
        val t = terms(CardPaymentMode.Minimum)
        assertEquals(1_500L, CreditCardCalculator.revolvingStep(10_000, t).payment)
        val small = CreditCardCalculator.revolvingStep(1_000, t)
        assertEquals(1_017L, small.payment)
        assertEquals(0L, small.remaining)
    }

    @Test fun fixedPaymentPaysOffSooner() {
        val movements = listOf(move(-100_000, day(2026, 9, 5)))
        val minimum = summary(terms(CardPaymentMode.Minimum), movements, today = day(2026, 11, 4))
        val fixed = summary(terms(CardPaymentMode.Fixed, 20_000), movements, today = day(2026, 11, 4))
        assertEquals(20_000L, fixed.next?.amount)
        assertTrue(fixed.payoff!!.months < minimum.payoff!!.months)
        assertTrue(fixed.payoff!!.interest < minimum.payoff!!.interest)
        val tooLow = summary(terms(CardPaymentMode.Fixed, 100), movements, today = day(2026, 11, 4))
        assertEquals(4_667L, tooLow.next?.amount)
    }

    @Test fun limitAlertAndReminders() {
        val s = summary(terms(), listOf(move(-250_000, day(2026, 10, 10))), today = day(2026, 11, 4))
        assertTrue(s.isOverAlert)
        val alert = CardAlerts.limitAlert(s, "Tarjeta de prueba")!!
        assertTrue(alert.title.contains("83 %"))
        assertTrue(alert.id.contains("2026-12-01"))

        val reminders = CardAlerts.plan(listOf(CardReminder(s, "Tarjeta de prueba", 100_000)), day(2026, 11, 4))
        assertEquals(1, reminders.size)
        assertEquals("2026-11-29", reminders[0].fireOn)
        assertTrue(reminders[0].id.startsWith(CardAlerts.PREFIX))
        assertTrue(reminders[0].body.contains("sólo hay"))
    }

    @Test fun termsValidation() {
        var t = terms()
        assertNull(t.issue)
        t = t.copy(paymentMode = CardPaymentMode.Fixed)
        assertNotNull(t.issue)
        t = t.copy(fixedPayment = 10_000)
        assertNull(t.issue)
        assertNotNull(t.copy(statementDay = 31).issue)
        assertNotNull(t.copy(payFromAccountId = card).issue)
    }

    @Test fun decodesServerRow() {
        val row = """{"account_id":"a","household_id":"h","credit_limit_minor":300000,"statement_day":1,"payment_day":1,"payment_delay_months":1,"payment_mode":"minimum","fixed_payment_minor":null,"min_payment_percent":3.00,"min_payment_minor":1500,"revolving_rate":20.00,"installment_rate":14.00,"pay_from_account_id":null,"remind_days_before":2,"alert_percent":80}"""
        val decoded = Json.decodeFromString<CreditCardTerms>(row)
        assertEquals(CardPaymentMode.Minimum, decoded.paymentMode)
        assertEquals(20.0, decoded.revolvingRate, 0.0)
    }

    @Test fun inMemoryRules() = runBlocking {
        val f = InMemoryFinance()
        val tarjeta = f.createAccount(AccountDraft("Tarjeta", AccountKind.CreditCard), home)
        val cuenta = f.createAccount(AccountDraft("Cuenta"), home)
        assertThrows(AppError::class.java) { runBlocking { f.saveCreditCard(CreditCardTerms(cuenta.id, home, 100_000)) } }

        val good = CreditCardTerms(tarjeta.id, home, 300_000, payFromAccountId = cuenta.id)
        f.saveCreditCard(good)
        f.saveCreditCard(good.copy(creditLimit = 250_000))
        assertEquals(listOf(250_000L), f.creditCards(home).map { it.creditLimit })

        val compra = f.addMovement(MovementDraft(tarjeta.id, null, day(2026, 11, 3), -60_000, "Compra"), home)
        val otra = f.addMovement(MovementDraft(cuenta.id, null, day(2026, 11, 3), -1_000, "Otra"), home)
        assertThrows(AppError::class.java) { runBlocking { f.saveInstallment(CardInstallment("", home, tarjeta.id, otra.id, 3)) } }
        f.saveInstallment(CardInstallment("", home, tarjeta.id, compra.id, 6))
        f.saveInstallment(CardInstallment("", home, tarjeta.id, compra.id, 9))
        assertEquals(listOf(9), f.cardInstallments(home).map { it.months })
        f.deleteMovement(compra.id)
        assertTrue(f.cardInstallments(home).isEmpty())
        f.deleteAccount(cuenta.id)
        assertNull(f.creditCards(home).first().payFromAccountId)
    }
}
