package com.savethemoney.android.data

import com.savethemoney.android.ui.PlanningModel
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.LocalDate

/** Fase D, como PhaseDTests de iOS: cargos pendientes, emparejar con lo importado, resumen semanal y avisos de hábito. Datos inventados. */
class PhaseDTest {
    private val home = "h"
    private val account = "a"
    private var n = 0
    private fun day(y: Int, m: Int, d: Int) = LocalDate.of(y, m, d)

    private fun series(
        name: String = "Plataforma de vídeo", amount: Long = 1299, starts: LocalDate, pendingFrom: LocalDate? = null,
        kind: RecurringKind = RecurringKind.Subscription, id: String = "s${n++}",
    ) = RecurringSeries(id, home, name, kind, amount, account, startsOn = starts.toString(), pendingFrom = pendingFrom?.toString())

    private fun movement(minor: Long, on: LocalDate, text: String = "CARGO", accountId: String = account, category: String? = null) =
        Movement("m${n++}", home, accountId, category, on.toString(), minor, text)

    private fun charge(item: RecurringSeries, due: LocalDate, minor: Long = -1299, id: String = "c${n++}") =
        RecurringCharge(id, home, item.id, due.toString(), minor)

    @Test
    fun missingChargesStartAtPendingFromAndSkipKnown() {
        val item = series(starts = day(2026, 1, 31), pendingFrom = day(2026, 10, 1))
        val today = day(2026, 12, 2)
        val missing = PendingCharges.missing(listOf(item), emptyList(), today)
        // Desde el 1 de octubre: 31 oct y 30 nov (último día de un mes de 30).
        assertEquals(listOf(day(2026, 10, 31), day(2026, 11, 30)), missing.map { it.due })
        assertEquals("un gasto se apunta en negativo", -1299L, missing.first().amountMinor)
        assertTrue("lo ya apuntado no se repite", PendingCharges.missing(listOf(item), missing, today).isEmpty())

        assertTrue(PendingCharges.missing(listOf(item.copy(createsPending = false)), emptyList(), today).isEmpty())
        val income = series("Nómina", 150_000, day(2026, 11, 28), day(2026, 11, 1), RecurringKind.Income)
        assertEquals(150_000L, PendingCharges.missing(listOf(income), emptyList(), today).first().amountMinor)
    }

    @Test
    fun missingChargesLookBackAtMostTwoMonths() {
        val item = series(starts = day(2025, 1, 5), pendingFrom = day(2025, 1, 1))
        val today = day(2026, 11, 20)
        val missing = PendingCharges.missing(listOf(item), emptyList(), today)
        assertEquals(
            listOf(day(2026, 9, 5), day(2026, 10, 5), day(2026, 11, 5)).filter { !it.isBefore(today.minusDays(PendingCharges.LOOKBACK_DAYS)) },
            missing.map { it.due },
        )
    }

    @Test
    fun matchesImportedMovementInsteadOfDuplicating() {
        val item = series(starts = day(2026, 11, 5), pendingFrom = day(2026, 11, 1))
        val pending = charge(item, day(2026, 11, 5))
        val exact = movement(-1299, day(2026, 11, 7), "COMPRA")
        val farAway = movement(-1299, day(2026, 11, 20))
        val otherAccount = movement(-1299, day(2026, 11, 5), accountId = "otra")
        assertEquals(listOf(exact.id), PendingCharges.matches(listOf(pending), listOf(item), listOf(farAway, otherAccount, exact)).map { it.second })

        // Importe distinto (subida de precio) pero con el nombre en el concepto.
        val raised = movement(-1399, day(2026, 11, 5), "PLATAFORMA VIDEO SL")
        assertEquals(listOf(raised.id), PendingCharges.matches(listOf(pending), listOf(item), listOf(raised)).map { it.second })
        val unrelated = movement(-1399, day(2026, 11, 5), "SUPERMERCADO")
        assertTrue(PendingCharges.matches(listOf(pending), listOf(item), listOf(unrelated)).isEmpty())

        // Un movimiento que ya confirma otro cargo no se vuelve a usar.
        val linked = pending.copy(status = ChargeStatus.Confirmed, transactionId = exact.id)
        val next = charge(item, day(2026, 11, 6))
        assertTrue(PendingCharges.matches(listOf(linked, next), listOf(item), listOf(exact)).isEmpty())
    }

    @Test
    fun confirmSkipAndPendingListInMemory() = runBlocking {
        val backend = InMemoryFinance()
        val checking = backend.createAccount(AccountDraft("Cuenta"), home)
        val item = backend.createRecurring(
            RecurringSeries("", home, "Gimnasio", amountMinor = 3000, accountId = checking.id, startsOn = "2026-10-01", pendingFrom = "2026-10-01"),
        )
        val missing = PendingCharges.missing(listOf(item), emptyList(), day(2026, 11, 15))
        val created = backend.createCharges(missing + missing)
        assertEquals("los repetidos se ignoran", 2, created.size)
        assertEquals("un pendiente no toca el saldo", 0L, backend.balances(home)[checking.id])

        val draft = MovementDraft(checking.id, null, created[0].due, -3200, "Gimnasio")
        val movement = backend.confirmCharge(created[0].id, draft)
        backend.updateCharge(created[1], ChargeStatus.Skipped, null)
        val charges = backend.recurringCharges(home)
        assertEquals(movement.id, charges.first { it.id == created[0].id }.transactionId)
        assertEquals(-3200L, charges.first { it.id == created[0].id }.amountMinor)
        assertTrue(PendingCharges.pending(charges, listOf(item)).isEmpty())
        assertEquals(-3200L, backend.balances(home)[checking.id])

        try {
            backend.confirmCharge(created[0].id, draft.copy(description = "Otra vez"))
            fail("no se confirma dos veces")
        } catch (_: AppError) {
        }
    }

    @Test
    fun modelCreatesPendingAndMatchesImported() = runBlocking {
        val backend = InMemoryFinance()
        val checking = backend.createAccount(AccountDraft("Cuenta"), home)
        backend.createRecurring(RecurringSeries("", home, "Gimnasio", amountMinor = 3000, accountId = checking.id, startsOn = "2026-10-01", pendingFrom = "2026-10-01"))
        val model = PlanningModel(Household(home, "Casa"), backend, NoNotifier) { day(2026, 11, 15) }
        model.load()
        val imported = backend.addMovement(MovementDraft(checking.id, null, day(2026, 11, 2), -3000, "GIMNASIO"), home)
        model.syncCharges(listOf(imported))
        assertEquals("el de octubre sigue pendiente", listOf(day(2026, 10, 1)), model.pending.map { it.charge.due })
        assertEquals(imported.id, backend.recurringCharges(home).first { it.due == day(2026, 11, 1) }.transactionId)
        model.syncCharges(listOf(imported))
        assertEquals("no se duplican al volver a sincronizar", 2, backend.recurringCharges(home).size)
    }

    @Test
    fun weeklySummary() {
        val food = BudgetCategory("food", home, "Comida", CategoryKind.Expense, BudgetGroup.Needs)
        val salary = BudgetCategory("salary", home, "Nómina", CategoryKind.Income)
        val transfer = BudgetCategory("transfer", home, "Traspaso", CategoryKind.Transfer)
        // Hoy es miércoles 18 nov 2026: la semana del resumen es la del 9 al 15.
        val today = day(2026, 11, 18)
        assertEquals(2, today.weekdayIndex)
        assertEquals(day(2026, 11, 16), today.startOfWeek)
        val movements = listOf(
            movement(-5000, day(2026, 11, 10), "SUPER", category = food.id),
            movement(-2000, day(2026, 11, 15), "CENA", category = food.id),
            movement(-9000, day(2026, 11, 12), "LIBRERIA"),
            movement(-100_000, day(2026, 11, 11), "A AHORRO", category = transfer.id),
            movement(200_000, day(2026, 11, 13), "NOMINA", category = salary.id),
            movement(-8000, day(2026, 11, 4), "SEMANA ANTERIOR", category = food.id),
            movement(-3000, day(2026, 11, 17), "ESTA SEMANA", category = food.id),
        )
        val summary = WeeklySummary(movements, listOf(food, salary, transfer), today, heatmapWeeks = 2)
        assertEquals(day(2026, 11, 9), summary.week.start)
        assertEquals("sin traspasos ni la semana en curso", 16_000L, summary.week.spent)
        assertEquals(200_000L, summary.week.income)
        assertEquals(8_000L, summary.previous.spent)
        assertEquals(100L, summary.change.second)
        assertEquals(listOf("LIBRERIA", "SUPER", "CENA"), summary.biggest.map { it.description })
        assertEquals("Sin categoría", summary.topCategories.first().title)
        assertEquals(2, summary.heatmap.size)
        assertEquals(day(2026, 11, 12), summary.heatmap[1][3].day)
        assertEquals(1.0, summary.heatmap[1][3].intensity, 0.0)
        assertEquals("9 nov – 15 nov", summary.title)
        assertTrue(summary.notificationBody.startsWith("Gastaste"))
        assertEquals(3000L, WeeklySummary(movements, listOf(food, salary, transfer), today, includeCurrent = true).week.spent)
    }

    @Test
    fun habitReminders() {
        val today = day(2026, 11, 18)
        assertEquals(3, HabitReminderPlanner.logReminders(today, 21, weekly = false, days = 3).size)
        val sundays = HabitReminderPlanner.logReminders(today, 21, weekly = true, days = 14)
        assertEquals(listOf("2026-11-22", "2026-11-29"), sundays.map { it.fireOn })
        val weekly = HabitReminderPlanner.weeklySummary(today, weeks = 2)
        assertEquals(listOf("2026-11-23", "2026-11-30"), weekly.map { it.fireOn })
        assertTrue(weekly.all { it.id.startsWith(HabitReminderPlanner.PREFIX) })
        // Por defecto, sólo el resumen de los lunes.
        assertEquals(3, HabitSettings().plan(today).size)
        assertTrue(HabitSettings(weeklySummary = false).plan(today).isEmpty())
    }

    @Test
    fun seriesCodingKeepsPendingFields() {
        val item = series(starts = day(2026, 11, 5), pendingFrom = day(2026, 11, 1))
        val json = Json.encodeToString(item)
        assertTrue(json.contains("\"pending_from\":\"2026-11-01\""))
        val decoded = Json { ignoreUnknownKeys = true }.decodeFromString<RecurringSeries>(
            """{"id":"s","household_id":"h","name":"X","amount_minor":1,"starts_on":"2026-11-05","creates_pending":false}""",
        )
        assertEquals(false, decoded.createsPending)
        val charge = Json.decodeFromString<RecurringCharge>(
            """{"id":"c","household_id":"h","series_id":"s","due_on":"2026-11-05","amount_minor":-1299,"status":"skipped","transaction_id":null}""",
        )
        assertEquals(ChargeStatus.Skipped, charge.status)
    }
}
