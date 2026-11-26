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

    /** Tarjetas cuyos extractos sin cobrar tienen más movimientos que [CYCLE_LIMIT]. */
    private var truncatedAccounts = emptySet<String>()

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
            // Sin condiciones no hay cálculo: no hace falta ningún movimiento (se cargan al guardarlas).
            val loaded = cardAccounts.mapNotNull { account -> terms[account.id]?.let { account.id to cardMovements(account.id, it) } }
            movements = loaded.associate { (id, result) -> id to result.first }
            truncatedAccounts = loaded.filter { (_, result) -> result.second }.map { it.first }.toSet()
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

    /**
     * Lo que necesita el cálculo de la tarjeta: todos los movimientos de los extractos sin cobrar (por fecha, no los N más
     * recientes) y la compra de cada aplazado. El segundo valor dice si se ha llegado a [CYCLE_LIMIT].
     */
    private suspend fun cardMovements(accountId: String, terms: CreditCardTerms): Pair<List<Movement>, Boolean> {
        val since = terms.cycleStart(CreditCardCalculator.firstUnpaidStatement(terms, today()))
        val list = service.movements(household.id, accountId, since, CYCLE_LIMIT)
        return withPurchases(list, accountId) to (list.size >= CYCLE_LIMIT)
    }

    /** Añade las compras de los aplazados de la tarjeta que falten, por antiguas que sean. */
    private suspend fun withPurchases(list: List<Movement>, accountId: String): List<Movement> {
        val known = list.map { it.id }.toSet()
        val missing = installments.filter { it.accountId == accountId && it.movementId !in known }.map { it.movementId }
        return if (missing.isEmpty()) list else list + service.movements(household.id, missing)
    }

    /** Tras recargar los aplazados: uno creado en otro dispositivo puede ser de una compra que no se había cargado. */
    private suspend fun loadMissingPurchases() {
        movements = movements.mapValues { (id, list) -> withPurchases(list, id) }
    }

    private fun recompute() {
        summaries = cardAccounts.mapNotNull { account ->
            val t = terms[account.id] ?: return@mapNotNull null
            account.id to CreditCardCalculator.summary(
                t, balances[account.id] ?: account.openingMinor, movements(account), installments, transferCategories, today(),
            ).copy(movementsTruncated = account.id in truncatedAccounts)
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
        // Con otro día de extracto cambian los ciclos sin cobrar: se vuelven a cargar sus movimientos.
        val (list, cut) = cardMovements(saved.accountId, saved)
        movements = movements + (saved.accountId to list)
        truncatedAccounts = if (cut) truncatedAccounts + saved.accountId else truncatedAccounts - saved.accountId
        recompute()
    }

    suspend fun deferPurchase(movement: Movement, months: Int, account: Account, rate: Double) {
        val plan = installment(movement)?.copy(months = months, rate = rate)
            ?: CardInstallment("", household.id, account.id, movement.id, months, rate)
        plan.issue?.let { throw AppError.InvalidInput(it) }
        service.saveInstallment(plan)
        installments = service.cardInstallments(household.id)
        loadMissingPurchases()
        recompute()
    }

    suspend fun remove(plan: CardInstallment) {
        service.deleteInstallment(plan.id)
        installments = service.cardInstallments(household.id)
        loadMissingPurchases()
        recompute()
    }

    companion object {
        /**
         * Tope de movimientos de los extractos sin cobrar de una tarjeta: el servidor da como mucho 1000 filas por petición.
         * Si se llega, el resumen lo dice ([CreditCardSummary.movementsTruncated]) en vez de dar cifras recortadas sin avisar.
         */
        const val CYCLE_LIMIT = 1000
    }
}
