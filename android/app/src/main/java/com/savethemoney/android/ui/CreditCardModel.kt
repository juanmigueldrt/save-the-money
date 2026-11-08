package com.savethemoney.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.savethemoney.android.data.Account
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.BudgetCategory
import com.savethemoney.android.data.CardAlerts
import com.savethemoney.android.data.CardInstallment
import com.savethemoney.android.data.CardReminder
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.CreditCardCalculator
import com.savethemoney.android.data.CreditCardSummary
import com.savethemoney.android.data.CreditCardTerms
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.Notifier
import kotlinx.coroutines.CancellationException
import java.time.LocalDate

/** Tarjetas del hogar: condiciones, aplazados, cargos y sus avisos (CreditCardModel de iOS). */
class CreditCardModel(
    private val household: Household,
    private val service: FinanceService,
    private val notifier: Notifier,
    val today: () -> LocalDate,
) {
    var terms by mutableStateOf(emptyMap<String, CreditCardTerms>())
        private set
    var installments by mutableStateOf(emptyList<CardInstallment>())
        private set
    var summaries by mutableStateOf(emptyMap<String, CreditCardSummary>())
        private set
    var error by mutableStateOf<String?>(null)
        private set

    // El Nav solo apila números de pantalla: estos campos dicen con qué abrirla.
    var selectedId by mutableStateOf<String?>(null)
    var purchaseId: String? = null

    private var accounts by mutableStateOf(emptyList<Account>())
    private var movements by mutableStateOf(emptyMap<String, List<Movement>>())
    private var balances = emptyMap<String, Long>()
    private var transferCategories = emptySet<String>()

    val cardAccounts: List<Account> get() = accounts.filter { it.kind == AccountKind.CreditCard && !it.isArchived }
    val selected: Account? get() = cardAccounts.firstOrNull { it.id == selectedId } ?: cardAccounts.firstOrNull()

    fun summary(account: Account): CreditCardSummary? = summaries[account.id]
    fun movements(account: Account): List<Movement> = movements[account.id].orEmpty()
    fun installment(movement: Movement): CardInstallment? = installments.firstOrNull { it.movementId == movement.id }
    fun plans(account: Account): List<CardInstallment> = installments.filter { it.accountId == account.id }
    fun takePurchase(): String? = purchaseId.also { purchaseId = null }

    /** Compras que se pueden aplazar: del extracto abierto, de 50 € o más y sin aplazar. */
    fun deferrable(account: Account): List<Movement> {
        val summary = summaries[account.id] ?: return emptyList()
        val start = summary.terms.cycleStart(summary.openStatement)
        return movements(account).filter {
            it.amountMinor <= -5_000 && !it.day.isBefore(start) && installment(it) == null && it.categoryId !in transferCategories
        }
    }

    /** Total de los próximos cargos de todas las tarjetas. */
    val nextPaymentsTotal: Long get() = summaries.values.sumOf { it.next?.amount ?: 0 }

    /** Nunca lanza: si falla, se quedan los datos que había y [error] dice por qué. */
    suspend fun load(accounts: List<Account>, balances: Map<String, Long>, categories: List<BudgetCategory>) {
        this.accounts = accounts
        this.balances = balances
        transferCategories = categories.filter { it.kind == CategoryKind.Transfer }.map { it.id }.toSet()
        try {
            terms = service.creditCards(household.id).associateBy { it.accountId }
            installments = service.cardInstallments(household.id)
            movements = cardAccounts.associate { it.id to service.movements(household.id, it.id, RECENT_LIMIT) }
            error = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: AppError) {
            error = e.message
        } catch (e: Exception) {
            error = AppError.Unknown("app").message
        }
        recompute()
    }

    private fun recompute() {
        summaries = cardAccounts.mapNotNull { account ->
            val t = terms[account.id] ?: return@mapNotNull null
            account.id to CreditCardCalculator.summary(
                t, balances[account.id] ?: account.openingMinor, movements(account), installments, transferCategories, today(),
            )
        }.toMap()
        val cards = cardAccounts.mapNotNull { account ->
            summaries[account.id]?.let { CardReminder(it, account.name, it.terms.payFromAccountId?.let(balances::get)) }
        }
        notifier.replaceReminders(CardAlerts.plan(cards, today()), CardAlerts.PREFIX)
        notifier.budgetAlerts(cards.mapNotNull { CardAlerts.limitAlert(it.summary, it.name) })
    }

    /** Al volver a encender los avisos en Más opciones. */
    fun reschedule() = recompute()

    suspend fun save(item: CreditCardTerms) {
        item.issue?.let { throw AppError.InvalidInput(it) }
        val saved = service.saveCreditCard(item)
        terms = terms + (saved.accountId to saved)
        recompute()
    }

    suspend fun deferPurchase(movement: Movement, months: Int, account: Account, rate: Double) {
        val plan = installment(movement)?.copy(months = months, rate = rate)
            ?: CardInstallment("", household.id, account.id, movement.id, months, rate)
        plan.issue?.let { throw AppError.InvalidInput(it) }
        service.saveInstallment(plan)
        installments = service.cardInstallments(household.id)
        recompute()
    }

    suspend fun remove(plan: CardInstallment) {
        service.deleteInstallment(plan.id)
        installments = service.cardInstallments(household.id)
        recompute()
    }

    private companion object {
        const val RECENT_LIMIT = 500
    }
}
