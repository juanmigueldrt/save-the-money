package com.savethemoney.android.ui

import com.savethemoney.android.data.AccountDraft
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.BudgetAlert
import com.savethemoney.android.data.CardAlerts
import com.savethemoney.android.data.CardReminder
import com.savethemoney.android.data.CreditCardCalculator
import com.savethemoney.android.data.CreditCardTerms
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.HabitReminderPlanner
import com.savethemoney.android.data.HabitSettings
import com.savethemoney.android.data.Holding
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.InMemoryFinance
import com.savethemoney.android.data.InvestmentPlan
import com.savethemoney.android.data.InvestmentReminders
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.Notifier
import com.savethemoney.android.data.PlannedReminder
import com.savethemoney.android.data.RecurrenceUnit
import com.savethemoney.android.data.RecurringSeries
import com.savethemoney.android.data.ReminderPlanner
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal
import java.time.LocalDate
import java.time.LocalDateTime

/** Avisos locales (ORC-86, ORC-121): una carga fallida no los toca, entre todos no pasan de 64 y no se pierden. Datos inventados. */
class AvisosTest {
    private val home = "home"
    private val household = Household(home, "Casa")

    private fun day(y: Int, m: Int, d: Int) = LocalDate.of(y, m, d)

    /** Guarda lo que se programaría, por prefijo, y cuántas veces se sustituye. */
    private class Recorded : Notifier {
        override var enabled = true
        override var budgetAlertsEnabled = true
        override var habits = HabitSettings()
        val byPrefix = mutableMapOf<String, List<PlannedReminder>>()
        val calls = mutableListOf<String>()
        override fun replaceReminders(reminders: List<PlannedReminder>, prefix: String) {
            byPrefix[prefix] = reminders
            calls += prefix
        }
        override fun budgetAlerts(alerts: List<BudgetAlert>) = Unit
        fun count(prefix: String) = calls.count { it == prefix }
    }

    /** El mismo backend, pero sin conexión para todo lo que se lee al cargar. */
    private fun offline(backend: InMemoryFinance): FinanceService = object : FinanceService by backend {
        override suspend fun recurringSeries(householdId: String): List<RecurringSeries> = throw AppError.Network
        override suspend fun holdings(householdId: String): List<Holding> = throw AppError.Network
        override suspend fun creditCards(householdId: String): List<CreditCardTerms> = throw AppError.Network
    }

    @Test fun pagosFijosCargaFallidaNoBorraLosAvisos() = runBlocking {
        val backend = InMemoryFinance()
        backend.createRecurring(RecurringSeries("", home, "Gimnasio", amountMinor = 3000, startsOn = "2026-11-20", remindDaysBefore = 1))
        val notifier = Recorded()
        PlanningModel(household, backend, notifier) { day(2026, 11, 10) }.load()
        val scheduled = notifier.byPrefix.getValue(ReminderPlanner.PREFIX)
        assertEquals(listOf("2026-11-19", "2026-12-19"), scheduled.map { it.fireOn })

        val reopened = PlanningModel(household, offline(backend), notifier) { day(2026, 11, 10) }
        reopened.load()
        assertEquals(AppError.Network.message, reopened.error)
        assertEquals("una carga fallida no reprograma", 1, notifier.count(ReminderPlanner.PREFIX))
        assertEquals(scheduled, notifier.byPrefix[ReminderPlanner.PREFIX])
    }

    @Test fun aportacionesCargaFallidaNoBorraLosAvisos() = runBlocking {
        val backend = InMemoryFinance()
        val fund = backend.createHolding(Holding("", home, "Fondo de prueba", price = BigDecimal.TEN))
        backend.createPlan(InvestmentPlan("", home, fund.id, amountMinor = 5000, startsOn = "2026-11-15", remindDaysBefore = 1))
        val notifier = Recorded()
        InvestmentModel(household, backend, notifier) { day(2026, 11, 10) }.load()
        val scheduled = notifier.byPrefix.getValue(InvestmentReminders.PREFIX)
        assertEquals(listOf("2026-11-14", "2026-12-14"), scheduled.map { it.fireOn })

        val reopened = InvestmentModel(household, offline(backend), notifier) { day(2026, 11, 10) }
        reopened.load()
        assertEquals(AppError.Network.message, reopened.error)
        assertEquals("una carga fallida no reprograma", 1, notifier.count(InvestmentReminders.PREFIX))
        assertEquals(scheduled, notifier.byPrefix[InvestmentReminders.PREFIX])

        // El interruptor de Más opciones vuelve a programar las aportaciones con lo último cargado.
        InvestmentModel(household, backend, notifier) { day(2026, 11, 10) }.apply { load() }.reschedule()
        assertEquals(3, notifier.count(InvestmentReminders.PREFIX))
    }

    @Test fun tarjetasCargaFallidaNoBorraLosAvisos() = runBlocking {
        val backend = InMemoryFinance()
        val card = backend.createAccount(AccountDraft("Tarjeta", AccountKind.CreditCard), home)
        backend.addMovement(MovementDraft(card.id, null, day(2026, 10, 10), -30_000, "Compra de prueba"), home)
        backend.saveCreditCard(CreditCardTerms(card.id, home, 300_000))
        val accounts = backend.accounts(home)
        val balances = backend.balances(home)
        val notifier = Recorded()
        CreditCardModel(household, backend, notifier) { day(2026, 11, 4) }.load(accounts, balances, emptyList())
        val scheduled = notifier.byPrefix.getValue(CardAlerts.PREFIX)
        assertEquals(1, scheduled.size)

        val reopened = CreditCardModel(household, offline(backend), notifier) { day(2026, 11, 4) }
        reopened.load(accounts, balances, emptyList())
        assertEquals(AppError.Network.message, reopened.error)
        assertEquals("una carga fallida no reprograma", 1, notifier.count(CardAlerts.PREFIX))
        assertEquals(scheduled, notifier.byPrefix[CardAlerts.PREFIX])
    }

    @Test fun avisoDeHoyConLaHoraPasadaSeMuestraAlMomento() {
        // A las 10:00 se crea un pago que vence mañana con aviso un día antes: el aviso era hoy a las 9:00.
        val series = RecurringSeries("s", home, "Gimnasio", amountMinor = 3000, startsOn = "2026-11-27", remindDaysBefore = 1)
        val planned = ReminderPlanner.plan(listOf(series), day(2026, 11, 26))
        val (now, later) = LocalNotifier.split(planned, emptySet(), LocalDateTime.of(2026, 11, 26, 10, 0))
        assertEquals(listOf("2026-11-26"), now.map { it.fireOn })
        assertEquals(listOf("2026-12-26"), later.map { it.fireOn })
    }

    @Test fun planificadorDescartaLoMostradoYLoDeDiasPasados() {
        fun aviso(id: String, fireOn: String, hour: Int = 9) = PlannedReminder(id, fireOn, hour, "Aviso de prueba", "Texto")
        val pending = listOf(
            aviso("ayer", "2026-11-25"),
            aviso("mostrado", "2026-11-26"),
            aviso("hoy-pasado", "2026-11-26"),
            aviso("hoy-justo", "2026-11-26", hour = 10),
            aviso("hoy-luego", "2026-11-26", hour = 21),
            aviso("manana", "2026-11-27"),
        )
        val (now, later) = LocalNotifier.split(pending, setOf("mostrado"), LocalDateTime.of(2026, 11, 26, 10, 0))
        assertEquals(listOf("hoy-pasado", "hoy-justo"), now.map { it.id })
        assertEquals(listOf("hoy-luego", "manana"), later.map { it.id })
    }

    @Test fun alertaSoloSeMarcaComoEnviadaSiSeMuestra() {
        val alerts = listOf(BudgetAlert("a", "Comida al 80 %", "Texto"), BudgetAlert("b", "Ocio pasado", "Texto"))
        val shown = mutableListOf<String>()
        val sinPermiso = LocalNotifier.sendAlerts(alerts, setOf("viejo"), { false })
        assertEquals(setOf("viejo"), sinPermiso)
        val conPermiso = LocalNotifier.sendAlerts(alerts, sinPermiso) { shown += it.id; true }
        assertEquals(setOf("viejo", "a", "b"), conPermiso)
        // Lo ya enviado no se vuelve a mostrar.
        LocalNotifier.sendAlerts(alerts, conPermiso) { shown += it.id; true }
        assertEquals(listOf("a", "b"), shown)
    }

    @Test fun todosLosAvisosJuntosNoPasanDe64() {
        val today = day(2026, 11, 2)
        val series = (0 until 60).map {
            RecurringSeries("s$it", home, "Pago de prueba", amountMinor = 1000, unit = RecurrenceUnit.Week, startsOn = today.toString())
        }
        val recurring = ReminderPlanner.plan(series, today)

        val holding = Holding("h", home, "Fondo de prueba", price = BigDecimal.TEN)
        val plans = (0 until 20).map {
            InvestmentPlan("p$it", home, holding.id, amountMinor = 5000, unit = RecurrenceUnit.Week, startsOn = today.toString())
        }
        val investments = InvestmentReminders.plan(plans, listOf(holding), today)

        val purchase = Movement("m", home, "card", null, "2026-10-10", -50_000, "Compra de prueba")
        val base = CreditCardCalculator.summary(CreditCardTerms("card", home, 300_000), -50_000, listOf(purchase), emptyList(), emptySet(), today)
        val cards = (0 until 20).map { CardReminder(base.copy(terms = base.terms.copy(accountId = "card$it")), "Tarjeta de prueba", null) }
        val cardReminders = CardAlerts.plan(cards, today)

        // Recordatorio diario para apuntar gastos y resumen de los lunes: el máximo de los hábitos.
        val habits = HabitReminderPlanner.logReminders(today, 21, weekly = false) + HabitReminderPlanner.weeklySummary(today)

        assertEquals(10, investments.size)
        assertEquals(10, cardReminders.size)
        assertEquals(24, habits.size)
        assertEquals("los pagos fijos se quedan con lo que dejan libre los demás", 20, recurring.size)
        assertTrue(recurring.size + investments.size + cardReminders.size + habits.size <= 64)
    }
}
