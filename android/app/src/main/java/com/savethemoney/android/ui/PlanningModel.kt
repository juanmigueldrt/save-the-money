package com.savethemoney.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.Goal
import com.savethemoney.android.data.GoalContribution
import com.savethemoney.android.data.GoalProgress
import com.savethemoney.android.data.ChargeStatus
import com.savethemoney.android.data.HabitReminderPlanner
import com.savethemoney.android.data.HabitSettings
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.PendingCharge
import com.savethemoney.android.data.PendingCharges
import com.savethemoney.android.data.RecurringCharge
import com.savethemoney.android.data.Notifier
import com.savethemoney.android.data.RecurringKind
import com.savethemoney.android.data.RecurringSeries
import com.savethemoney.android.data.ReminderPlanner
import com.savethemoney.android.data.UpcomingCharge
import com.savethemoney.android.data.upcoming
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.text.Collator
import java.time.Instant
import java.time.LocalDate
import java.util.Locale

/** Pagos recurrentes y metas del hogar abierto; al cambiar los pagos se reprograman los avisos (PlanningModel de iOS). */
class PlanningModel(
    val household: Household,
    private val service: FinanceService,
    private val notifier: Notifier,
    val today: () -> LocalDate,
) {
    var series by mutableStateOf(emptyList<RecurringSeries>())
        private set
    var goals by mutableStateOf(emptyList<Goal>())
        private set
    var contributions by mutableStateOf(emptyList<GoalContribution>())
        private set
    /** Cargos de los pagos fijos (pendientes, confirmados y saltados). */
    var charges by mutableStateOf(emptyList<RecurringCharge>())
        private set
    var error by mutableStateOf<String?>(null)
        private set

    // El Nav solo apila números de pantalla: estos campos dicen con qué abrirla.
    var selectedGoalId by mutableStateOf<String?>(null)
    var seriesToEdit: RecurringSeries? = null
    var chargeToConfirm: PendingCharge? = null
    var goalToEdit: Goal? = null

    val activeSeries: List<RecurringSeries> get() = series.filter { !it.isArchived }
    val upcoming: List<UpcomingCharge> get() = series.upcoming(today())
    val selectedGoal: Goal? get() = goals.firstOrNull { it.id == selectedGoalId }

    val progress: List<GoalProgress> get() = goals.filter { !it.isArchived }.map(::progress)

    fun progress(goal: Goal) = GoalProgress(goal, contributions, today())
    fun contributions(goal: Goal) = contributions.filter { it.goalId == goal.id }

    fun takeSeries(): RecurringSeries? = seriesToEdit.also { seriesToEdit = null }
    fun takeGoal(): Goal? = goalToEdit.also { goalToEdit = null }

    /** Cargos que han llegado y esperan que los confirmes. */
    val pending: List<PendingCharge> get() = PendingCharges.pending(charges, series)

    /** Próximo gasto fijo, para Inicio. */
    val nextExpense: UpcomingCharge? get() = upcoming.firstOrNull { it.series.kind != RecurringKind.Income }

    /** Nunca lanza: si falla, se quedan los datos que había y [error] dice por qué. */
    suspend fun load() {
        var loaded = false
        try {
            coroutineScope {
                val s = async { service.recurringSeries(household.id) }
                val g = async { service.goals(household.id) }
                val c = async { service.contributions(household.id) }
                series = s.await()
                goals = g.await()
                contributions = c.await()
            }
            error = null
            loaded = true
        } catch (e: CancellationException) {
            throw e
        } catch (e: AppError) {
            error = e.message
        } catch (e: Exception) {
            error = AppError.Unknown("app").message
        }
        // Aparte: si los cargos fallan, los pagos fijos y las metas se ven igual.
        quietly { charges = service.recurringCharges(household.id) }
        // Si la carga falla, los avisos ya programados se quedan como estaban.
        if (loaded) reschedule()
    }

    // MARK: cargos pendientes

    /**
     * Apunta los cargos que han llegado y empareja los pendientes con movimientos ya apuntados
     * (del CSV o a mano), para que no se dupliquen. Se llama cada vez que cambian los movimientos. Nunca lanza.
     */
    suspend fun syncCharges(movements: List<Movement>) {
        if (series.isEmpty()) return
        val missing = PendingCharges.missing(series, charges, today())
        if (missing.isNotEmpty()) quietly {
            val created = service.createCharges(missing)
            // Si otro dispositivo los creó a la vez, se vuelven a leer.
            charges = if (created.size < missing.size) service.recurringCharges(household.id) else charges + created
        }
        for ((charge, movement) in PendingCharges.matches(charges, series, movements)) quietly {
            service.updateCharge(charge, ChargeStatus.Confirmed, movement)
            charges = charges.map { if (it.id == charge) it.copy(status = ChargeStatus.Confirmed, transactionId = movement) else it }
        }
    }

    /** Crea el movimiento del cargo, con el importe, día, cuenta y categoría que se hayan puesto. */
    suspend fun confirm(item: PendingCharge, draft: MovementDraft): Movement {
        draft.issue?.let { throw AppError.InvalidInput(it) }
        val movement = service.confirmCharge(item.id, draft)
        charges = charges.map {
            if (it.id == item.id) it.copy(status = ChargeStatus.Confirmed, transactionId = movement.id, amountMinor = movement.amountMinor) else it
        }
        return movement
    }

    /** Ese cargo no se ha cobrado (o no se va a cobrar). */
    suspend fun skip(item: PendingCharge) {
        service.updateCharge(item.id, ChargeStatus.Skipped, null)
        charges = charges.map { if (it.id == item.id) it.copy(status = ChargeStatus.Skipped) else it }
    }

    private suspend fun quietly(block: suspend () -> Unit) {
        try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
        }
    }

    private fun reschedule() {
        notifier.replaceReminders(ReminderPlanner.plan(series, today()), ReminderPlanner.PREFIX)
        rescheduleHabits()
    }

    /** Recordatorio para apuntar gastos y aviso del resumen semanal, según Más opciones. */
    var habits: HabitSettings
        get() = notifier.habits
        set(value) {
            notifier.habits = value
            rescheduleHabits()
        }

    private fun rescheduleHabits() = notifier.replaceReminders(notifier.habits.plan(today()), HabitReminderPlanner.PREFIX)

    var alertsEnabled: Boolean
        get() = notifier.enabled
        set(value) {
            notifier.enabled = value
            reschedule()
        }

    var budgetAlertsEnabled: Boolean
        get() = notifier.budgetAlertsEnabled
        set(value) { notifier.budgetAlertsEnabled = value }

    suspend fun save(item: RecurringSeries) {
        item.issue?.let { throw AppError.InvalidInput(it) }
        val saved = if (series.none { it.id == item.id }) service.createRecurring(item) else service.updateRecurring(item)
        val collator = Collator.getInstance(Locale("es", "ES"))
        series = (series.filter { it.id != saved.id } + saved).sortedWith(compareBy(collator) { it.trimmedName })
        reschedule()
    }

    suspend fun setArchived(item: RecurringSeries, archived: Boolean) =
        save(item.copy(archivedAt = if (archived) Instant.now().toString() else null))

    suspend fun delete(item: RecurringSeries) {
        service.deleteRecurring(item.id)
        series = series.filter { it.id != item.id }
        charges = charges.filter { it.seriesId != item.id }
        reschedule()
    }

    suspend fun save(goal: Goal) {
        goal.issue?.let { throw AppError.InvalidInput(it) }
        val saved = if (goals.none { it.id == goal.id }) service.createGoal(goal) else service.updateGoal(goal)
        goals = if (goals.any { it.id == saved.id }) goals.map { if (it.id == saved.id) saved else it } else goals + saved
    }

    suspend fun setArchived(goal: Goal, archived: Boolean) =
        save(goal.copy(archivedAt = if (archived) Instant.now().toString() else null))

    suspend fun delete(goal: Goal) {
        service.deleteGoal(goal.id)
        goals = goals.filter { it.id != goal.id }
        contributions = contributions.filter { it.goalId != goal.id }
    }

    suspend fun contribute(amount: Long, goal: Goal, day: LocalDate, note: String?) {
        val item = GoalContribution("", household.id, goal.id, amount, day.toString(), note?.trim()?.ifEmpty { null })
        item.issue?.let { throw AppError.InvalidInput(it) }
        val saved = service.addContribution(item)
        contributions = (contributions + saved).sortedByDescending { it.madeOn }
        // Al llegar al objetivo, se marca como conseguida.
        if (progress(goal).isReached && goal.completedAt == null) save(goal.copy(completedAt = Instant.now().toString()))
    }

    suspend fun delete(contribution: GoalContribution) {
        service.deleteContribution(contribution.id)
        contributions = contributions.filter { it.id != contribution.id }
    }
}
