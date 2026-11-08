package com.savethemoney.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.Budget
import com.savethemoney.android.data.BudgetCategory
import com.savethemoney.android.data.BudgetReport
import com.savethemoney.android.data.BudgetAlertPlanner
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.Notifier
import com.savethemoney.android.data.monthContaining
import com.savethemoney.android.data.period
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.time.LocalDate
import java.time.YearMonth

/** Presupuesto y flujo del mes elegido; las dos pantallas miran el mismo mes (BudgetModel de iOS). */
class BudgetModel(private val household: Household, private val service: FinanceService, private val notifier: Notifier, private val today: () -> LocalDate) {
    var month by mutableStateOf(monthContaining(today(), household.monthStartDay))
        private set
    var budget by mutableStateOf<Budget?>(null)
        private set
    var proposal by mutableStateOf<Budget?>(null)
        private set
    private var movements by mutableStateOf(emptyList<Movement>())
    var error by mutableStateOf<String?>(null)
        private set

    val period: ClosedRange<LocalDate> get() = month.period(household.monthStartDay)

    /** Punto de partida del formulario: el de este mes, el último que haya o uno vacío 50/30/20. */
    val draft: Budget get() = budget ?: proposal?.copy(month = month) ?: Budget(household.id, month)

    /** Informe de los [months] meses que acaban en el elegido. */
    fun report(categories: List<BudgetCategory>, months: Int = 1): BudgetReport {
        val from = month.minusMonths(months - 1L).period(household.monthStartDay).start
        return BudgetReport(budget, from..period.endInclusive, categories, movements)
    }

    /** Meses que ofrece el selector, del más reciente al más antiguo. */
    fun months(): List<YearMonth> = (0L..12L).map { monthContaining(today(), household.monthStartDay).plusMonths(1 - it) }

    /** Avisa de los límites del mes en curso que se acercan o se pasan. */
    fun checkAlerts(categories: List<BudgetCategory>) {
        if (budget != null && today() in period) notifier.budgetAlerts(BudgetAlertPlanner.alerts(report(categories), month))
    }

    suspend fun show(next: YearMonth) {
        month = next
        load()
    }

    /** Nunca lanza: si falla, se quedan los datos que había y [error] dice por qué. */
    suspend fun load() {
        val target = month
        try {
            coroutineScope {
                val current = async { service.budget(household.id, target) }
                val last = async { service.latestBudget(household.id, target) }
                // Doce meses de golpe: el flujo trimestral y anual salen de la misma carga.
                val from = target.minusMonths(MAX_MONTHS - 1L).period(household.monthStartDay).start
                val list = async { service.movements(household.id, from, target.period(household.monthStartDay).endInclusive) }
                val saved = current.await()
                val previous = last.await()
                val rows = list.await()
                // Si ya se cambió de mes mientras cargaba, no se pisa.
                if (target != month) return@coroutineScope
                budget = saved
                proposal = if (saved == null) previous else null
                movements = rows
            }
            error = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: AppError) {
            error = e.message
        } catch (e: Exception) {
            error = AppError.Unknown("app").message
        }
    }

    suspend fun save(next: Budget) {
        budget = service.saveBudget(next)
        proposal = null
    }

    private companion object {
        const val MAX_MONTHS = 12
    }
}
