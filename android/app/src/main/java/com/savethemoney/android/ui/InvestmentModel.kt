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
        try {
            holdings = service.holdings(household.id)
            prices = service.holdingPrices(household.id)
            trades = service.trades(household.id)
            plans = service.investmentPlans(household.id)
            error = null
            reschedule()
        } catch (e: CancellationException) {
            throw e
        } catch (e: AppError) {
            error = e.message
        } catch (e: Exception) {
            error = AppError.Unknown("app").message
        }
    }

    suspend fun loadMembers(backend: Backend) {
        members = runCatching { backend.members(household.id) }.getOrElse { if (it is CancellationException) throw it else members }
    }

    private fun reschedule() = notifier.replaceReminders(InvestmentReminders.plan(plans, holdings, today()), InvestmentReminders.PREFIX)

    suspend fun save(holding: Holding): Holding {
        val isNew = holdings.none { it.id == holding.id }
        val saved = if (isNew) service.createHolding(holding) else service.updateHolding(holding)
        holdings = (holdings.filter { it.id != saved.id } + saved).sortedBy { it.trimmedName.lowercase() }
        return saved
    }

    suspend fun delete(holding: Holding) {
        service.deleteHolding(holding.id)
        holdings = holdings.filter { it.id != holding.id }
        prices = prices.filter { it.holdingId != holding.id }
        trades = trades.filter { it.holdingId != holding.id }
        plans = plans.filter { it.holdingId != holding.id }
        reschedule()
    }

    suspend fun recordPrice(price: BigDecimal, day: LocalDate, holding: Holding) {
        val saved = service.recordPrice(price, day, holding.id)
        holdings = holdings.map { if (it.id == saved.id) saved else it }
        prices = service.holdingPrices(household.id)
    }

    suspend fun add(trade: InvestmentTrade) {
        trade.issue(trades)?.let { throw AppError.InvalidInput(it) }
        trades = trades + service.addTrade(trade)
    }

    suspend fun delete(trade: InvestmentTrade) {
        service.deleteTrade(trade.id)
        trades = trades.filter { it.id != trade.id }
    }

    suspend fun save(plan: InvestmentPlan) {
        val isNew = plans.none { it.id == plan.id }
        val saved = if (isNew) service.createPlan(plan) else service.updatePlan(plan)
        plans = (plans.filter { it.id != saved.id } + saved).sortedBy { it.startsOn }
        reschedule()
    }

    suspend fun setPaused(paused: Boolean, plan: InvestmentPlan) = save(plan.copy(pausedAt = if (paused) Instant.now().toString() else null))

    suspend fun delete(plan: InvestmentPlan) {
        service.deletePlan(plan.id)
        plans = plans.filter { it.id != plan.id }
        reschedule()
    }
}
