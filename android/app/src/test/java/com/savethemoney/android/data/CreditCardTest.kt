package com.savethemoney.android.data

import com.savethemoney.android.ui.CreditCardModel
import com.savethemoney.android.ui.FinanceModel
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
    private val shopping = "shopping"

    private fun day(y: Int, m: Int, d: Int) = LocalDate.of(y, m, d)

    private fun move(amount: Long, on: LocalDate, payment: Boolean = false, refund: Boolean = false) = Movement(
        UUID.randomUUID().toString(), home, card, if (payment) transfer else if (refund) shopping else null, on.toString(), amount,
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
            move(2_000, day(2026, 10, 25), refund = true),
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
        assertEquals(emptyList<String>(), s.uncategorizedCredits)
    }

    /** ORC-79: el pago del extracto anterior, importado de un CSV sin categoría, no es una devolución. */
    @Test fun uncategorizedCreditDoesNotReduceCharges() {
        val credit = move(50_000, day(2026, 10, 5))
        val old = move(1_000, day(2026, 9, 20)) // extracto ya cobrado: no cambia ningún cargo
        val movements = listOf(move(-51_000, day(2026, 9, 12)), old, credit, move(-30_000, day(2026, 10, 10)))
        val today = day(2026, 11, 20)
        val s = summary(terms(), movements, today = today)
        assertEquals(30_000L, s.used)
        assertEquals(day(2026, 12, 1), s.next?.due)
        assertEquals(30_000L, s.next?.amount)
        assertEquals(30_000L, s.next?.purchases)
        assertEquals(30_000L, s.revolvingBalance)
        assertEquals(listOf(credit.id), s.uncategorizedCredits)

        // En el extracto abierto tampoco baja lo gastado.
        val open = move(2_000, day(2026, 11, 10))
        val later = summary(terms(), movements + move(-5_000, day(2026, 11, 5)) + open, today = today)
        assertEquals(5_000L, later.spentThisCycle)
        assertEquals(listOf(30_000L, 5_000L, 0L, 0L, 0L, 0L), later.payments.map { it.amount })
        assertEquals(listOf(credit.id, open.id), later.uncategorizedCredits)

        // Al clasificarlo deja de avisar: como pago no toca el cargo; como devolución lo baja.
        val asPayment = summary(terms(), movements.map { if (it.id == credit.id) it.copy(categoryId = transfer) else it }, today = today)
        assertEquals(30_000L, asPayment.next?.amount)
        assertEquals(emptyList<String>(), asPayment.uncategorizedCredits)
        val asRefund = summary(terms(), movements.map { if (it.id == credit.id) it.copy(categoryId = shopping) else it }, today = today)
        assertEquals(0L, asRefund.next?.amount)
        assertEquals(emptyList<String>(), asRefund.uncategorizedCredits)
    }

    /**
     * ORC-78: la app solo carga los 500 movimientos más recientes de la tarjeta, y la compra aplazada puede ser
     * más antigua. Mismos números que summaries de testdata/vectors/card_installments.json.
     */
    @Test fun installmentSurvivesMoreThan500LaterMovements() {
        val purchase = move(-120_000, day(2025, 10, 15))
        val plan = CardInstallment("p", home, card, purchase.id, 24, 14.0)
        val short = listOf(purchase, move(55_835, day(2026, 11, 1), payment = true), move(-30_000, day(2026, 10, 10)), move(-5_000, day(2026, 11, 5)))
        // 520 movimientos posteriores a la compra, en extractos ya pagados: no cambian lo que se debe.
        val filler = (0 until 260).flatMap { listOf(move(-1_000, day(2026, 3, 10)), move(1_000, day(2026, 4, 1), payment = true)) }
        val today = day(2026, 11, 20)
        val expected = summary(terms(), short, listOf(plan), today)
        assertEquals(99_165L, expected.used)
        assertEquals(30_000L, expected.revolvingBalance)
        assertEquals(List(6) { 5_762L }, expected.payments.map { it.installments })
        assertEquals(listOf(35_762L, 10_762L, 5_762L, 5_762L, 5_762L, 5_762L), expected.payments.map { it.amount })
        assertEquals(listOf(749L, 690L, 631L, 571L, 511L, 449L), expected.payments.map { it.interest })
        assertEquals(emptyList<String>(), expected.unresolvedInstallments)

        val recent = (short + filler).sortedByDescending { it.bookedOn }.take(500)
        assertFalse(purchase in recent)
        fun cardSummary(movements: List<Movement>) =
            CreditCardCalculator.summary(terms(), -99_165, movements, listOf(plan), setOf(transfer), today)
        // Solo con los recientes falta la compra: no se puede calcular el aplazado, y el resumen lo dice.
        val cut = cardSummary(recent)
        assertEquals(listOf("p"), cut.unresolvedInstallments)
        assertEquals(94_165L, cut.revolvingBalance)
        assertEquals(List(6) { 0L }, cut.payments.map { it.installments })
        // Con la compra pedida aparte (lo que hace la app), sale lo mismo que con el historial corto.
        val full = cardSummary(recent + purchase)
        assertEquals(emptyList<String>(), full.unresolvedInstallments)
        assertEquals(expected.revolvingBalance, full.revolvingBalance)
        assertEquals(expected.payments, full.payments)
    }

    /** Lo mismo, cargando por el modelo con el servicio en memoria. */
    @Test fun modelLoadsInstallmentPurchaseOutsideTheRecentMovements() = runBlocking {
        val service = InMemoryFinance()
        val account = service.createAccount(AccountDraft("Tarjeta", AccountKind.CreditCard), home)
        val pay = service.categories(home).first { it.kind == CategoryKind.Transfer }.id
        suspend fun add(amount: Long, on: LocalDate, payment: Boolean = false) =
            service.addMovement(MovementDraft(account.id, if (payment) pay else null, on, amount, if (payment) "Pago de la tarjeta" else "Compra de prueba"), home)
        val purchase = add(-120_000, day(2025, 10, 15))
        service.saveCreditCard(CreditCardTerms(account.id, home, 300_000))
        service.saveInstallment(CardInstallment("", home, account.id, purchase.id, 24, 14.0))
        repeat(260) {
            add(-1_000, day(2026, 3, 10))
            add(1_000, day(2026, 4, 1), payment = true)
        }
        add(55_835, day(2026, 11, 1), payment = true)
        add(-30_000, day(2026, 10, 10))
        add(-5_000, day(2026, 11, 5))
        assertFalse(service.movements(home, account.id, 500).any { it.id == purchase.id })

        val model = FinanceModel(Household(home, "Casa"), service, { day(2026, 11, 20) })
        model.load()
        val s = model.cards.summary(account)!!
        assertNull(model.cards.error)
        assertEquals(99_165L, s.used)
        assertEquals(emptyList<String>(), s.unresolvedInstallments)
        assertEquals(30_000L, s.revolvingBalance)
        assertEquals(List(6) { 5_762L }, s.payments.map { it.installments })
        assertEquals(listOf(35_762L, 10_762L, 5_762L, 5_762L, 5_762L, 5_762L), s.payments.map { it.amount })
        assertEquals(listOf(749L, 690L, 631L, 571L, 511L, 449L), s.payments.map { it.interest })
        assertTrue(model.cards.movements(account).any { it.id == purchase.id })
    }

    /**
     * ORC-132: hoy 2026-11-20 están sin cobrar el extracto del 1-11 (se cobra el 1-12) y el abierto (se cierra el 1-12).
     * 600 compras de 1 € en el ciclo abierto y una de 300 € del ciclo anterior: con los 500 más recientes faltaban
     * 100 compras del ciclo abierto y la de 300 €. Mismo caso que CreditCardLoadTests.swift.
     */
    @Test fun modelLoadsEveryMovementOfTheUnpaidStatements() = runBlocking {
        val service = InMemoryFinance()
        val account = service.createAccount(AccountDraft("Tarjeta", AccountKind.CreditCard), home)
        suspend fun add(amount: Long, on: LocalDate) = service.addMovement(MovementDraft(account.id, null, on, amount, "Compra de prueba"), home)
        service.saveCreditCard(CreditCardTerms(account.id, home, 300_000))
        add(-30_000, day(2026, 10, 10))
        repeat(600) { add(-100, day(2026, 11, 5)) }
        // Una compra de un extracto ya cobrado: no hace falta cargarla.
        val paid = add(-7_000, day(2026, 9, 15))

        val model = FinanceModel(Household(home, "Casa"), service, { day(2026, 11, 20) })
        model.load()
        assertNull(model.cards.error)
        val s = model.cards.summary(account)!!
        assertEquals(60_000L, s.spentThisCycle)
        assertEquals(listOf(30_000L, 60_000L, 0L, 0L, 0L, 0L), s.payments.map { it.amount })
        assertFalse(s.movementsTruncated)
        assertFalse(model.cards.movements(account).any { it.id == paid.id })

        // Con más movimientos que el tope de una petición, el resumen lo dice.
        repeat(CreditCardModel.CYCLE_LIMIT) { add(-100, day(2026, 11, 6)) }
        model.load()
        assertTrue(model.cards.summary(account)!!.movementsTruncated)
    }

    /** Un aplazado guardado en otro dispositivo para una compra antigua: al cambiar los aplazados aquí se carga su compra. */
    @Test fun installmentFromAnotherDeviceLoadsItsPurchase() = runBlocking {
        val service = InMemoryFinance()
        val account = service.createAccount(AccountDraft("Tarjeta", AccountKind.CreditCard), home)
        suspend fun add(amount: Long, on: LocalDate) = service.addMovement(MovementDraft(account.id, null, on, amount, "Compra de prueba"), home)
        service.saveCreditCard(CreditCardTerms(account.id, home, 300_000))
        val old = add(-120_000, day(2025, 10, 15))
        val recent = add(-6_000, day(2026, 11, 2))
        val model = FinanceModel(Household(home, "Casa"), service, { day(2026, 11, 20) })
        model.load()

        service.saveInstallment(CardInstallment("", home, account.id, old.id, 24, 14.0))
        model.cards.deferPurchase(recent, 3, account, 14.0)
        assertEquals(emptyList<String>(), model.cards.summary(account)!!.unresolvedInstallments)
        assertTrue(model.cards.movements(account).any { it.id == old.id })
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
        // Se cambian las guardadas (con su versión), como hace el formulario.
        f.saveCreditCard(f.saveCreditCard(good).copy(creditLimit = 250_000))
        assertEquals(listOf(250_000L), f.creditCards(home).map { it.creditLimit })

        val compra = f.addMovement(MovementDraft(tarjeta.id, null, day(2026, 11, 3), -60_000, "Compra"), home)
        val otra = f.addMovement(MovementDraft(cuenta.id, null, day(2026, 11, 3), -1_000, "Otra"), home)
        assertThrows(AppError::class.java) { runBlocking { f.saveInstallment(CardInstallment("", home, tarjeta.id, otra.id, 3)) } }
        f.saveInstallment(f.saveInstallment(CardInstallment("", home, tarjeta.id, compra.id, 6)).copy(months = 9))
        assertEquals(listOf(9), f.cardInstallments(home).map { it.months })
        f.deleteMovement(compra.id)
        assertTrue(f.cardInstallments(home).isEmpty())
        f.deleteAccount(cuenta.id)
        assertNull(f.creditCards(home).first().payFromAccountId)
    }
}
