package com.savethemoney.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.Backend
import com.savethemoney.android.data.ChartRange
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.Holding
import com.savethemoney.android.data.HoldingPrice
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.HouseholdMember
import com.savethemoney.android.data.InvestmentPlan
import com.savethemoney.android.data.InvestmentReminders
import com.savethemoney.android.data.InvestmentTrade
import com.savethemoney.android.data.Notifier
import com.savethemoney.android.data.PlanCharge
import com.savethemoney.android.data.Portfolio
import com.savethemoney.android.data.PortfolioPoint
import com.savethemoney.android.data.Position
import com.savethemoney.android.data.PriceHistory
import com.savethemoney.android.data.TradeCash
import com.savethemoney.android.data.charges
import com.savethemoney.android.data.counts
import com.savethemoney.android.data.monthlyTotal
import kotlinx.coroutines.CancellationException
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth

/** Inversiones del hogar abierto: activos, precios, operaciones y planes (InvestmentModel de iOS). */
class InvestmentModel(
    private val household: Household,
    private val service: FinanceService,
    private val notifier: Notifier,
    val today: () -> LocalDate,
) {
    var holdings by mutableStateOf(emptyList<Holding>())
        private set
    var prices by mutableStateOf(emptyList<HoldingPrice>())
        private set
    var trades by mutableStateOf(emptyList<InvestmentTrade>())
        private set
    var plans by mutableStateOf(emptyList<InvestmentPlan>())
        private set
    var members by mutableStateOf(emptyList<HouseholdMember>())
        private set
    var error by mutableStateOf<String?>(null)
        private set

    /** Qué lectura gana cuando dos se cruzan (ORC-144). */
    private val turns = ReadTurns()

    // El Nav solo apila números de pantalla: estos campos dicen con qué abrirla.
    var selectedId by mutableStateOf<String?>(null)
    var holdingToEdit: Holding? = null
    var planToEdit: InvestmentPlan? = null

    val householdId: String get() = household.id
    val activeHoldings: List<Holding> get() = holdings.filter { !it.isArchived }
    val portfolio: Portfolio get() = Portfolio(holdings, trades)
    val selected: Holding? get() = holdings.firstOrNull { it.id == selectedId }
    val livePlans: List<InvestmentPlan> get() = plans.filter { !it.isArchived }
    val monthlyPlanned: Long get() = plans.monthlyTotal(today())
    val planCounts: Pair<Int, Int> get() = plans.counts(today())

    fun takeHoldingToEdit(): Holding? = holdingToEdit.also { holdingToEdit = null }
    fun takePlanToEdit(): InvestmentPlan? = planToEdit.also { planToEdit = null }
    fun holding(id: String?): Holding? = holdings.firstOrNull { it.id == id }
    fun position(holding: Holding) = Position(holding, trades)
    fun trades(holding: Holding) = trades.filter { it.holdingId == holding.id }.sortedByDescending { it.day }
    fun evolution(range: ChartRange): List<PortfolioPoint> = PriceHistory.evolution(holdings, prices, trades, range, today())
    fun charges(month: YearMonth): List<PlanCharge> = plans.charges(month)

    fun priceHistory(holding: Holding, range: ChartRange): List<Pair<LocalDate, BigDecimal>> {
        val start = range.start(today(), null)
        return PriceHistory.points(holding, prices, trades).filter { !it.first.isBefore(start) }
    }

    fun yearRange(holding: Holding) = PriceHistory.range(holding, prices, trades, today().minusMonths(12), today())

    /** "Ana" o "Compartido". */
    fun ownerName(id: String?): String = if (id == null) "Compartido" else members.firstOrNull { it.profile.id == id }?.profile?.name ?: "Otro miembro"

    /** Nunca lanza: si falla, se quedan los datos que había y [error] dice por qué. */
    suspend fun load() {
        val turn = turns.next()
        try {
            // Todo o nada: se leen las cuatro antes de guardar ninguna.
            val newHoldings = service.holdings(household.id)
            val newPrices = service.holdingPrices(household.id)
            val newTrades = service.trades(household.id)
            val newPlans = service.investmentPlans(household.id)
            turns.store(::holdings, newHoldings, turn)
            turns.store(::prices, newPrices, turn)
            turns.store(::trades, newTrades, turn)
            turns.store(::plans, newPlans, turn)
            turns.store(::error, null, turn)
            reschedule()
        } catch (e: CancellationException) {
            throw e
        } catch (e: AppError) {
            turns.store(::error, e.message, turn)
        } catch (e: Exception) {
            turns.store(::error, AppError.Unknown("app").message, turn)
        }
    }

    suspend fun loadMembers(backend: Backend) {
        val turn = turns.next()
        turns.store(::members, runCatching { backend.members(household.id) }.getOrElse { if (it is CancellationException) throw it else return }, turn)
    }

    /** También al volver a encender los avisos en Más opciones. */
    fun reschedule() = notifier.replaceReminders(InvestmentReminders.plan(plans, holdings, today()), InvestmentReminders.PREFIX)

    // Escrituras: cada una corre como [escritura], así que termina (y recarga) aunque se salga de la pantalla.

    /** Una escritura falló cuando su pantalla ya no estaba: el aviso sale en el error del modelo. */
    private fun sinPantalla(e: Exception) {
        turns.changed(::error, (e as? AppError)?.message ?: AppError.Unknown("app").message)
    }

    /**
     * Un activo sin versión ([Holding.updatedAt]) aún no se ha leído del servidor: es un alta, con el id que le dio el
     * formulario, y guardarlo otra vez con el mismo no crea otro. Con versión es un cambio sobre esa versión.
     */
    suspend fun save(holding: Holding): Holding = escritura(::sinPantalla) {
        val saved = try {
            if (holding.updatedAt == null) service.createHolding(holding) else service.updateHolding(holding)
        } catch (e: AppError) {
            // Si otro dispositivo lo cambió antes, se recarga para que se vea lo nuevo detrás del aviso.
            reloadAfterSave {
                val turn = turns.next()
                turns.store(::holdings, service.holdings(household.id), turn)
            }
            throw e
        }
        turns.changed(::holdings, (holdings.filter { it.id != saved.id } + saved).sortedBy { it.trimmedName.lowercase() })
        saved
    }

    suspend fun delete(holding: Holding): Unit = escritura(::sinPantalla) {
        service.deleteHolding(holding.id)
        turns.changed(::holdings, holdings.filter { it.id != holding.id })
        turns.changed(::prices, prices.filter { it.holdingId != holding.id })
        turns.changed(::trades, trades.filter { it.holdingId != holding.id })
        turns.changed(::plans, plans.filter { it.holdingId != holding.id })
        reschedule()
    }

    suspend fun recordPrice(price: BigDecimal, day: LocalDate, holding: Holding): Unit = escritura(::sinPantalla) {
        val saved = service.recordPrice(price, day, holding.id)
        turns.changed(::holdings, holdings.map { if (it.id == saved.id) saved else it })
        reloadAfterSave {
            val turn = turns.next()
            turns.store(::prices, service.holdingPrices(household.id), turn)
        }?.let { turns.changed(::error, it) }
    }

    /**
     * Guarda la operación y, con [cash], su movimiento en la cuenta: los dos o ninguno, en una sola llamada.
     * Con el mismo id (uno por formulario) reintentar no duplica. Desde las pantallas se llama por
     * FinanceModel.addTrade, que además recarga los saldos.
     */
    suspend fun add(trade: InvestmentTrade, cash: TradeCash? = null): Unit = escritura(::sinPantalla) {
        trade.issue(trades)?.let { throw AppError.InvalidInput(it) }
        val saved = try {
            service.addTrade(trade, cash)
        } catch (e: AppError) {
            // Puede que ya estuviera guardada (con otros datos): se recarga para que se vea detrás del aviso.
            try {
                val turn = turns.next()
                turns.store(::trades, service.trades(household.id), turn)
            } catch (_: AppError) {
            }
            throw e
        }
        turns.changed(::trades, trades.filter { it.id != saved.id } + saved)
    }

    suspend fun delete(trade: InvestmentTrade): Unit = escritura(::sinPantalla) {
        trade.deletionIssue(trades)?.let { throw AppError.InvalidInput(it) }
        service.deleteTrade(trade.id)
        turns.changed(::trades, trades.filter { it.id != trade.id })
    }

    /** Como [save] de un activo: sin versión es un alta con el id del formulario; con versión, un cambio sobre ella. */
    suspend fun save(plan: InvestmentPlan): Unit = escritura(::sinPantalla) {
        val saved = try {
            if (plan.updatedAt == null) service.createPlan(plan) else service.updatePlan(plan)
        } catch (e: AppError) {
            // Si otro dispositivo lo cambió antes, se recarga para que se vea lo nuevo detrás del aviso.
            reloadAfterSave {
                val turn = turns.next()
                turns.store(::plans, service.investmentPlans(household.id), turn)
            }
            reschedule()
            throw e
        }
        turns.changed(::plans, (plans.filter { it.id != saved.id } + saved).sortedBy { it.startsOn })
        reschedule()
    }

    suspend fun setPaused(paused: Boolean, plan: InvestmentPlan) = save(plan.copy(pausedAt = if (paused) Instant.now().toString() else null))

    suspend fun delete(plan: InvestmentPlan): Unit = escritura(::sinPantalla) {
        service.deletePlan(plan.id)
        turns.changed(::plans, plans.filter { it.id != plan.id })
        reschedule()
    }
}
