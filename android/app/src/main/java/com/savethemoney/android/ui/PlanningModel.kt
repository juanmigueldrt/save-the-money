package com.savethemoney.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.Goal
import com.savethemoney.android.data.GoalContribution
import com.savethemoney.android.data.GoalProgress
import com.savethemoney.android.data.Household
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
    var error by mutableStateOf<String?>(null)
        private set

    // El Nav solo apila números de pantalla: estos campos dicen con qué abrirla.
    var selectedGoalId by mutableStateOf<String?>(null)
    var seriesToEdit: RecurringSeries? = null
    var goalToEdit: Goal? = null

    val activeSeries: List<RecurringSeries> get() = series.filter { !it.isArchived }
    val upcoming: List<UpcomingCharge> get() = series.upcoming(today())
    val selectedGoal: Goal? get() = goals.firstOrNull { it.id == selectedGoalId }

    val progress: List<GoalProgress> get() = goals.filter { !it.isArchived }.map(::progress)

    fun progress(goal: Goal) = GoalProgress(goal, contributions, today())
    fun contributions(goal: Goal) = contributions.filter { it.goalId == goal.id }

    fun takeSeries(): RecurringSeries? = seriesToEdit.also { seriesToEdit = null }
    fun takeGoal(): Goal? = goalToEdit.also { goalToEdit = null }

    /** Próximo gasto fijo, para Inicio. */
    val nextExpense: UpcomingCharge? get() = upcoming.firstOrNull { it.series.kind != RecurringKind.Income }

    /** Nunca lanza: si falla, se quedan los datos que había y [error] dice por qué. */
    suspend fun load() {
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
        } catch (e: CancellationException) {
            throw e
        } catch (e: AppError) {
            error = e.message
        } catch (e: Exception) {
            error = AppError.Unknown("app").message
        }
        reschedule()
    }

    private fun reschedule() = notifier.replaceReminders(ReminderPlanner.plan(series, today()))

    var alertsEnabled: Boolean
        get() = notifier.enabled
        set(value) {
            notifier.enabled = value
            reschedule()
        }

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
