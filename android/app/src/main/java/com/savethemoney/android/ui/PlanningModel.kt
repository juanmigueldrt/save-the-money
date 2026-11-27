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

    /** Qué lectura gana cuando dos se cruzan (ORC-144). */
    private val turns = ReadTurns()

    val activeSeries: List<RecurringSeries> get() = series.filter { !it.isArchived }
    val upcoming: List<UpcomingCharge> get() = series.upcoming(today())
    fun goal(id: String): Goal? = goals.firstOrNull { it.id == id }

    val progress: List<GoalProgress> get() = goals.filter { !it.isArchived }.map(::progress)

    fun progress(goal: Goal) = GoalProgress(goal, contributions, today())
    fun contributions(goal: Goal) = contributions.filter { it.goalId == goal.id }

    /** Cargos que han llegado y esperan que los confirmes. */
    val pending: List<PendingCharge> get() = PendingCharges.pending(charges, series)

    /** Próximo gasto fijo, para Inicio. */
    val nextExpense: UpcomingCharge? get() = upcoming.firstOrNull { it.series.kind != RecurringKind.Income }

    /** Nunca lanza: si falla, se quedan los datos que había y [error] dice por qué. */
    suspend fun load() {
        val turn = turns.next()
        var loaded = false
        try {
            coroutineScope {
                val s = async { service.recurringSeries(household.id) }
                val g = async { service.goals(household.id) }
                val c = async { service.contributions(household.id) }
                // Todo o nada: se espera a las tres antes de guardar ninguna.
                val newSeries = s.await()
                val newGoals = g.await()
                val newContributions = c.await()
                turns.store(::series, newSeries, turn)
                turns.store(::goals, newGoals, turn)
                turns.store(::contributions, newContributions, turn)
            }
            turns.store(::error, null, turn)
            loaded = true
        } catch (e: Exception) {
            turns.fallaCarga(::error, turn, e)
        }
        // Aparte: si los cargos fallan, los pagos fijos y las metas se ven igual.
        quietly { turns.store(::charges, service.recurringCharges(household.id), turn) }
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
            if (created.size < missing.size) {
                // Si otro dispositivo los creó a la vez, se vuelven a leer.
                val turn = turns.next()
                turns.store(::charges, service.recurringCharges(household.id), turn)
            } else {
                turns.changed(::charges, charges + created)
            }
        }
        var stale = false
        for ((chargeId, movement) in PendingCharges.matches(charges, series, movements)) {
            val charge = charges.firstOrNull { it.id == chargeId } ?: continue
            try {
                val saved = service.updateCharge(charge, ChargeStatus.Confirmed, movement)
                turns.changed(::charges, charges.map { if (it.id == saved.id) saved else it })
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                stale = true
            }
        }
        // Si alguno no se pudo enlazar (por ejemplo, otro dispositivo lo cambió antes), se vuelven a leer.
        if (stale) reloadCharges()
    }

    /** Nunca lanza: si no se pueden leer, se quedan los que había. */
    private suspend fun reloadCharges() = quietly {
        val turn = turns.next()
        turns.store(::charges, service.recurringCharges(household.id), turn)
    }

    // Escrituras: cada una corre como [escritura], así que termina aunque se salga de la pantalla.

    /** Una escritura falló cuando su pantalla ya no estaba: el aviso sale en el error del modelo. */
    private fun sinPantalla(e: Exception) {
        turns.changed(::error, (e as? AppError)?.message ?: AppError.Unknown("app").message)
    }

    /** Crea el movimiento del cargo, con el importe, día, cuenta y categoría que se hayan puesto. */
    suspend fun confirm(item: PendingCharge, draft: MovementDraft): Movement = escritura(::sinPantalla) {
        draft.issue?.let { throw AppError.InvalidInput(it) }
        val movement = service.confirmCharge(item.id, draft)
        turns.changed(
            ::charges,
            charges.map {
                if (it.id == item.id) it.copy(status = ChargeStatus.Confirmed, transactionId = movement.id, amountMinor = movement.amountMinor) else it
            },
        )
        // Confirmarlo cambia su versión en el servidor: se vuelven a leer.
        reloadCharges()
        movement
    }

    /** Ese cargo no se ha cobrado (o no se va a cobrar). */
    suspend fun skip(item: PendingCharge): Unit = escritura(::sinPantalla) {
        val saved = try {
            service.updateCharge(item.charge, ChargeStatus.Skipped, null)
        } catch (e: AppError) {
            // Si otro dispositivo lo cambió antes, se recarga para que se vea lo nuevo detrás del aviso.
            reloadCharges()
            throw e
        }
        turns.changed(::charges, charges.map { if (it.id == saved.id) saved else it })
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

    /**
     * Un pago fijo sin versión ([RecurringSeries.updatedAt]) aún no se ha leído del servidor: es un alta, con el id que le dio el
     * formulario, y guardarlo otra vez con el mismo no crea otro. Con versión es un cambio sobre esa versión.
     */
    suspend fun save(item: RecurringSeries): Unit = escritura(::sinPantalla) {
        item.issue?.let { throw AppError.InvalidInput(it) }
        val saved = try {
            if (item.updatedAt == null) service.createRecurring(item) else service.updateRecurring(item)
        } catch (e: AppError) {
            // Si otro dispositivo lo cambió antes, se recarga para que se vea lo nuevo detrás del aviso.
            quietly {
                val turn = turns.next()
                turns.store(::series, service.recurringSeries(household.id), turn)
                reschedule()
            }
            throw e
        }
        val collator = Collator.getInstance(com.savethemoney.android.data.Region.locale)
        turns.changed(::series, (series.filter { it.id != saved.id } + saved).sortedWith(compareBy(collator) { it.trimmedName }))
        reschedule()
    }

    suspend fun setArchived(item: RecurringSeries, archived: Boolean) =
        save(item.copy(archivedAt = if (archived) Instant.now().toString() else null))

    /**
     * Los pagos fijos que crea una importación CSV, en una sola escritura: salir de la pantalla a mitad no deja de guardar
     * los que faltan. Para en el primero que falla, como guardarlos uno a uno.
     */
    suspend fun save(items: List<RecurringSeries>): Unit = escritura(::sinPantalla) { items.forEach { save(it) } }

    suspend fun delete(item: RecurringSeries): Unit = escritura(::sinPantalla) {
        service.deleteRecurring(item.id)
        turns.changed(::series, series.filter { it.id != item.id })
        turns.changed(::charges, charges.filter { it.seriesId != item.id })
        reschedule()
    }

    /**
     * Una meta sin versión ([Goal.updatedAt]) aún no se ha leído del servidor: es un alta, con el id que le dio el formulario,
     * y guardarla otra vez con el mismo no crea otra. Con versión es un cambio sobre esa versión.
     */
    suspend fun save(goal: Goal): Unit = escritura(::sinPantalla) {
        goal.issue?.let { throw AppError.InvalidInput(it) }
        val saved = try {
            if (goal.updatedAt == null) service.createGoal(goal) else service.updateGoal(goal)
        } catch (e: AppError) {
            // Si otro dispositivo la cambió antes, se recarga para que se vea lo nuevo detrás del aviso.
            reloadGoals()
            throw e
        }
        turns.changed(::goals, if (goals.any { it.id == saved.id }) goals.map { if (it.id == saved.id) saved else it } else goals + saved)
    }

    /** Tras una escritura que ha fallado. Nunca lanza: si también falla, se queda lo que había. */
    private suspend fun reloadGoals() = quietly {
        val turn = turns.next()
        val newGoals = service.goals(household.id)
        val newContributions = service.contributions(household.id)
        turns.store(::goals, newGoals, turn)
        turns.store(::contributions, newContributions, turn)
    }

    suspend fun setArchived(goal: Goal, archived: Boolean) =
        save(goal.copy(archivedAt = if (archived) Instant.now().toString() else null))

    suspend fun delete(goal: Goal): Unit = escritura(::sinPantalla) {
        service.deleteGoal(goal.id)
        turns.changed(::goals, goals.filter { it.id != goal.id })
        turns.changed(::contributions, contributions.filter { it.goalId != goal.id })
    }

    /** [id] lo da el formulario, uno por formulario: apuntarla otra vez con el mismo no la duplica. */
    suspend fun contribute(amount: Long, goal: Goal, day: LocalDate, note: String?, id: String = ""): Unit = escritura(::sinPantalla) {
        val item = GoalContribution(id, household.id, goal.id, amount, day.toString(), note?.trim()?.ifEmpty { null })
        item.issue?.let { throw AppError.InvalidInput(it) }
        val saved = try {
            service.addContribution(item)
        } catch (e: AppError) {
            // Puede que ya estuviera guardada con otros datos: se recarga para que se vea detrás del aviso.
            reloadGoals()
            throw e
        }
        turns.changed(::contributions, (contributions.filter { it.id != saved.id } + saved).sortedByDescending { it.madeOn })
        // Al llegar al objetivo, se marca como conseguida. Sobre la meta que hay cargada ahora, no la del formulario: solo se
        // le pone la fecha, así que no pisa nada de lo que otro dispositivo haya cambiado.
        val current = goals.firstOrNull { it.id == goal.id } ?: goal
        if (progress(current).isReached && current.completedAt == null) save(current.copy(completedAt = Instant.now().toString()))
    }

    suspend fun delete(contribution: GoalContribution): Unit = escritura(::sinPantalla) {
        service.deleteContribution(contribution.id)
        turns.changed(::contributions, contributions.filter { it.id != contribution.id })
    }
}
