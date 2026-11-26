package com.savethemoney.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.Budget
import com.savethemoney.android.data.BudgetAlertPlanner
import com.savethemoney.android.data.BudgetCarryOver
import com.savethemoney.android.data.BudgetCategory
import com.savethemoney.android.data.BudgetPeriod
import com.savethemoney.android.data.BudgetReport
import com.savethemoney.android.data.ExtraBudget
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.Notifier
import com.savethemoney.android.data.PaySchedule
import com.savethemoney.android.data.PeriodInsights
import com.savethemoney.android.data.SmartBudget
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.time.LocalDate

/**
 * Presupuesto y flujo del periodo elegido (de un cobro al siguiente). Lo comparten Presupuesto,
 * Flujo y Resumen, para que todas miren el mismo periodo (BudgetModel de iOS).
 */
class BudgetModel(val household: Household, private val service: FinanceService, private val notifier: Notifier, private val today: () -> LocalDate) {
    /** Cuándo cobra quien ha entrado. Sin guardar: cada mes desde el día de inicio del hogar. */
    var schedule by mutableStateOf(PaySchedule.monthly(household.monthStartDay))
        private set

    /** true si la persona ya ha dicho cuándo cobra. */
    var hasOwnSchedule by mutableStateOf(false)
        private set
    var period by mutableStateOf(schedule.period(today()))
        private set

    /** El presupuesto guardado de este periodo. */
    var budget by mutableStateOf<Budget?>(null)
        private set

    /** Si no hay presupuesto en este periodo, el último que haya, para proponerlo. */
    var proposal by mutableStateOf<Budget?>(null)
        private set

    /** El último presupuesto anterior, para el arrastre. */
    private var previousBudget by mutableStateOf<Budget?>(null)
    private var movements by mutableStateOf(emptyList<Movement>())
    var extraBudgets by mutableStateOf(emptyList<ExtraBudget>())
        private set
    var error by mutableStateOf<String?>(null)
        private set

    /** Qué lectura gana cuando dos se cruzan (ORC-144). */
    private val turns = ReadTurns()

    /** El presupuesto extra que abre el formulario (nulo = uno nuevo). */
    private var extraToEdit: ExtraBudget? = null

    fun edit(extra: ExtraBudget?) { extraToEdit = extra }
    fun takeExtra(): ExtraBudget? = extraToEdit.also { extraToEdit = null }

    /** Los 3 periodos anteriores, del más reciente al más antiguo. */
    val previousPeriods: List<BudgetPeriod>
        get() = generateSequence(schedule.periodBefore(period)) { schedule.periodBefore(it) }.take(3).toList()

    val isCurrentPeriod: Boolean get() = today() in period

    /** Punto de partida del formulario: el de este periodo, el último o uno vacío 50/30/20. */
    val draft: Budget get() = budget ?: proposal?.copy(period = period) ?: Budget(household.id, period)

    /** Días del informe: el periodo, o los [months] meses que acaban en él (para el flujo). */
    fun range(months: Int = 1): ClosedRange<LocalDate> =
        if (months <= 1) period.range else period.start.minusMonths(months - 1L)..period.end

    /** Arrastre que llega del periodo anterior (vacío si este presupuesto no arrastra). */
    fun carried(categories: List<BudgetCategory>): Map<String, Long> {
        val previous = previousBudget ?: return emptyMap()
        val before = previousPeriods.first()
        if (budget?.carryOver != true || previous.period != before) return emptyMap()
        // Lo arrastrado al anterior no se encadena: basta con un periodo hacia atrás.
        return BudgetCarryOver.amounts(BudgetReport(previous, before.range, categories, movements))
    }

    fun report(categories: List<BudgetCategory>, months: Int = 1): BudgetReport =
        BudgetReport(budget, range(months), categories, movements, if (months <= 1) carried(categories) else emptyMap())

    fun insights(categories: List<BudgetCategory>) = PeriodInsights(report(categories), budget, today())

    /** Límites propuestos con la media de los 3 periodos anteriores. */
    fun suggestedLimits(categories: List<BudgetCategory>) = SmartBudget.suggestedLimits(movements, categories, previousPeriods)

    /** Periodos que ofrece el selector, del siguiente al de hace un año. */
    fun periods(): List<BudgetPeriod> =
        generateSequence(schedule.periodAfter(schedule.period(today()))) { schedule.periodBefore(it) }
            .takeWhile { it.end >= today().minusYears(1) }.take(60).toList()

    /** Avisa de los límites del periodo en curso que se acercan o se pasan. */
    fun checkAlerts(categories: List<BudgetCategory>) {
        if (budget != null && isCurrentPeriod) notifier.budgetAlerts(BudgetAlertPlanner.alerts(report(categories)))
    }

    suspend fun showPrevious() = show(schedule.periodBefore(period))
    suspend fun showNext() = show(schedule.periodAfter(period))
    suspend fun showCurrent() = show(schedule.period(today()))

    suspend fun show(next: BudgetPeriod) {
        period = next
        load()
    }

    /** Nunca lanza: si falla, se quedan los datos que había y [error] dice por qué. */
    suspend fun load() {
        val turn = turns.next()
        try {
            val saved = service.paySchedule()
            if (saved != null && (saved != schedule || !hasOwnSchedule) && turns.mayStore(::schedule, turn)) {
                val wasCurrent = isCurrentPeriod
                schedule = saved
                hasOwnSchedule = true
                // Con otro día de cobro, el periodo en pantalla se recalcula.
                period = saved.period(if (wasCurrent) today() else period.end)
            }
            val target = period
            // Doce meses de golpe: el flujo trimestral y anual y los 3 periodos anteriores salen de la misma carga.
            val from = minOf(previousPeriods.last().start, target.start.minusMonths(MAX_MONTHS - 1L))
            coroutineScope {
                val current = async { service.budget(household.id, target.start) }
                val last = async { service.latestBudget(household.id, target.start) }
                val list = async { service.movements(household.id, from, target.end) }
                val extras = async { service.extraBudgets(household.id) }
                val found = current.await()
                val latest = last.await()
                val rows = list.await()
                val extraList = extras.await()
                // Si ya se cambió de periodo mientras cargaba, no se pisa.
                if (target != period) return@coroutineScope
                turns.store(::budget, found, turn)
                turns.store(::proposal, if (found == null) latest else null, turn)
                turns.store(::previousBudget, latest, turn)
                turns.store(::movements, rows, turn)
                turns.store(::extraBudgets, extraList, turn)
            }
            turns.store(::error, null, turn)
        } catch (e: CancellationException) {
            throw e
        } catch (e: AppError) {
            turns.store(::error, e.message, turn)
        } catch (e: Exception) {
            turns.store(::error, AppError.Unknown("app").message, turn)
        }
    }

    // Escrituras: cada una corre como [escritura], así que termina (y recarga) aunque se salga de la pantalla.

    /** Una escritura falló cuando su pantalla ya no estaba: el aviso sale en el error del modelo. */
    private fun sinPantalla(e: Exception) {
        turns.changed(::error, (e as? AppError)?.message ?: AppError.Unknown("app").message)
    }

    suspend fun save(next: Budget): Unit = escritura(::sinPantalla) {
        turns.changed(::budget, service.saveBudget(next))
        turns.changed(::proposal, null)
    }

    suspend fun save(next: PaySchedule): Unit = escritura(::sinPantalla) {
        turns.changed(::schedule, service.savePaySchedule(next))
        hasOwnSchedule = true
        period = next.period(today())
        load()
    }

    suspend fun save(extra: ExtraBudget): Unit = escritura(::sinPantalla) {
        val saved = service.saveExtraBudget(extra)
        turns.changed(::extraBudgets, extraBudgets.filter { it.id != saved.id } + saved)
        reloadAfterSave {
            val turn = turns.next()
            turns.store(::extraBudgets, service.extraBudgets(household.id), turn)
        }?.let { turns.changed(::error, it) }
    }

    suspend fun delete(extra: ExtraBudget): Unit = escritura(::sinPantalla) {
        service.deleteExtraBudget(extra.id)
        turns.changed(::extraBudgets, extraBudgets.filter { it.id != extra.id })
    }

    /** Movimientos que puede necesitar un presupuesto extra (sus fechas pueden salirse del periodo). */
    suspend fun movements(extra: ExtraBudget): List<Movement> = try {
        service.movements(household.id, extra.startsOn, maxOf(extra.endsOn ?: today(), extra.startsOn))
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        emptyList()
    }

    private companion object {
        const val MAX_MONTHS = 12
    }
}
