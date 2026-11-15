package com.savethemoney.android.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.YearMonth
import java.util.UUID

// Finance.swift y FinanceService de STMCore, con los mismos nombres de columna que Supabase.

@Serializable
enum class AccountKind(val title: String) {
    @SerialName("checking") Checking("Cuenta corriente"),
    @SerialName("savings") Savings("Ahorro"),
    @SerialName("credit_card") CreditCard("Tarjeta de crédito"),
    @SerialName("cash") Cash("Efectivo"),
    @SerialName("investment") Investment("Inversión"),
    @SerialName("loan") Loan("Préstamo"),
    @SerialName("other") Other("Otra");

    val isLiability: Boolean get() = this == CreditCard || this == Loan
}

/** Cuenta de un hogar. `ownerId` nulo significa compartida. */
@Serializable
data class Account(
    val id: String,
    @SerialName("household_id") val householdId: String,
    val name: String,
    val kind: AccountKind = AccountKind.Checking,
    val currency: String = "EUR",
    @SerialName("opening_balance_minor") val openingMinor: Long = 0,
    @SerialName("owner_id") val ownerId: String? = null,
    @SerialName("archived_at") val archivedAt: String? = null,
) {
    val isArchived: Boolean get() = archivedAt != null
    val isShared: Boolean get() = ownerId == null
}

@Serializable
enum class CategoryKind(val title: String) {
    @SerialName("income") Income("Ingreso"),
    @SerialName("expense") Expense("Gasto"),
    @SerialName("transfer") Transfer("Transferencia"),
}

@Serializable
enum class BudgetGroup(val title: String) {
    @SerialName("needs") Needs("Necesidades"),
    @SerialName("wants") Wants("Deseos"),
    @SerialName("savings") Savings("Ahorro"),
}

@Serializable
data class BudgetCategory(
    val id: String,
    @SerialName("household_id") val householdId: String,
    val name: String,
    val kind: CategoryKind = CategoryKind.Expense,
    @SerialName("budget_group") val budgetGroup: BudgetGroup? = null,
    val icon: String? = null,
) {
    val trimmedName: String get() = name.trim()

    /** Qué falla antes de guardarla, mirando también las demás categorías del hogar. */
    fun issue(among: List<BudgetCategory>): String? {
        if (trimmedName.isEmpty()) return "Ponle un nombre a la categoría."
        if (trimmedName.length > MAX_NAME) return "El nombre es demasiado largo (máximo $MAX_NAME letras)."
        if (kind != CategoryKind.Expense && budgetGroup != null) return "Sólo los gastos van en un grupo del 50/30/20."
        val repeated = among.any {
            it.id != id && it.householdId == householdId && it.kind == kind && it.trimmedName.equals(trimmedName, ignoreCase = true)
        }
        return if (repeated) "Ya hay una categoría de ${kind.title.lowercase()} con ese nombre." else null
    }

    companion object {
        const val MAX_NAME = 40

        /** Las mismas que crea el servidor para cada hogar nuevo. */
        fun defaults(householdId: String): List<BudgetCategory> {
            val e = CategoryKind.Expense
            val n = BudgetGroup.Needs
            val w = BudgetGroup.Wants
            val s = BudgetGroup.Savings
            return listOf(
                Triple("Nómina", CategoryKind.Income, null) to "banknote",
                Triple("Otros ingresos", CategoryKind.Income, null) to "plus.circle",
                Triple("Vivienda", e, n) to "house",
                Triple("Supermercado", e, n) to "cart",
                Triple("Suministros", e, n) to "bolt",
                Triple("Transporte", e, n) to "car",
                Triple("Salud", e, n) to "cross.case",
                Triple("Seguros", e, n) to "shield",
                Triple("Impuestos", e, n) to "building.columns",
                Triple("Multas y sanciones", e, n) to "exclamationmark.triangle",
                Triple("Tasas y trámites", e, n) to "doc.text",
                Triple("Restaurantes", e, w) to "fork.knife",
                Triple("Ocio", e, w) to "ticket",
                Triple("Compras", e, w) to "bag",
                Triple("Viajes", e, w) to "airplane",
                Triple("Suscripciones", e, w) to "repeat",
                Triple("Ahorro", e, s) to "banknote",
                Triple("Inversión", e, s) to "chart.line.uptrend.xyaxis",
                Triple("Deudas", e, s) to "creditcard",
                Triple("Transferencia entre cuentas", CategoryKind.Transfer, null) to "arrow.left.arrow.right",
            ).map { (row, icon) ->
                BudgetCategory(UUID.randomUUID().toString(), householdId, row.first, row.second, row.third, icon)
            }
        }
    }
}

/** Movimiento de una cuenta. Importe negativo = gasto, positivo = ingreso. */
@Serializable
data class Movement(
    val id: String,
    @SerialName("household_id") val householdId: String,
    @SerialName("account_id") val accountId: String,
    @SerialName("category_id") val categoryId: String? = null,
    @SerialName("booked_on") val bookedOn: String,
    @SerialName("amount_minor") val amountMinor: Long,
    val description: String,
    val notes: String? = null,
    @SerialName("import_hash") val importHash: String? = null,
) {
    val day: LocalDate get() = LocalDate.parse(bookedOn.take(10))
    val isExpense: Boolean get() = amountMinor < 0

    fun toDraft() = MovementDraft(accountId, categoryId, day, amountMinor, description, notes, importHash)
}

/** Lo que se apunta o se importa, antes de tener id en el servidor. */
data class MovementDraft(
    val accountId: String,
    val categoryId: String? = null,
    val bookedOn: LocalDate,
    val amountMinor: Long,
    val description: String,
    val notes: String? = null,
    val importHash: String? = null,
) {
    /** Problema que impide guardarlo, en español, o nulo si es válido. */
    val issue: String? get() {
        val text = description.trim()
        return when {
            text.isEmpty() -> "Escribe un concepto."
            text.length > 200 -> "El concepto es demasiado largo (máximo 200 caracteres)."
            amountMinor == 0L -> "El importe no puede ser cero."
            notes != null && notes.length > 500 -> "Las notas son demasiado largas (máximo 500 caracteres)."
            else -> null
        }
    }
}

data class AccountDraft(
    val name: String,
    val kind: AccountKind = AccountKind.Checking,
    val openingMinor: Long = 0,
    val ownerId: String? = null,
) {
    val trimmedName: String get() = name.trim()

    val issue: String? get() = when {
        trimmedName.isEmpty() -> "Ponle un nombre a la cuenta."
        trimmedName.length > 60 -> "El nombre es demasiado largo (máximo 60 caracteres)."
        else -> null
    }
}

data class ImportResult(val inserted: Int, val duplicates: Int)

/**
 * Saldo al final de cada uno de los últimos [months] meses, el más antiguo primero:
 * se parte del saldo actual y se deshacen los movimientos posteriores.
 */
fun monthEndBalances(current: Long, movements: List<Movement>, today: LocalDate, months: Int = 6): List<Long> =
    (months - 1 downTo 0).map { back ->
        val end = today.minusMonths(back.toLong()).withDayOfMonth(1).plusMonths(1)
        current - movements.filter { !it.day.isBefore(end) }.sumOf { it.amountMinor }
    }

/** Cuentas, saldos, categorías y movimientos de un hogar (FinanceService de iOS). */
interface FinanceService {
    /** Borra todo lo apuntado en el hogar (RPC `reset_household`). */
    suspend fun resetHousehold(householdId: String)

    suspend fun accounts(householdId: String): List<Account>
    suspend fun balances(householdId: String): Map<String, Long>
    suspend fun createAccount(draft: AccountDraft, householdId: String): Account
    suspend fun updateAccount(account: Account): Account
    suspend fun deleteAccount(accountId: String)

    suspend fun categories(householdId: String): List<BudgetCategory>
    suspend fun createCategory(category: BudgetCategory): BudgetCategory
    suspend fun updateCategory(category: BudgetCategory): BudgetCategory
    suspend fun deleteCategory(categoryId: String)

    suspend fun movements(householdId: String, accountId: String?, limit: Int): List<Movement>
    suspend fun addMovement(draft: MovementDraft, householdId: String): Movement
    suspend fun updateMovement(movement: Movement): Movement
    suspend fun deleteMovement(movementId: String)

    /** Guarda varios de golpe. Los que ya estaban (misma huella en la cuenta) se ignoran. */
    suspend fun importMovements(drafts: List<MovementDraft>, householdId: String): ImportResult

    suspend fun budget(householdId: String, month: YearMonth): Budget?

    /** El último presupuesto anterior a [month], para proponerlo. */
    suspend fun latestBudget(householdId: String, month: YearMonth): Budget?
    suspend fun saveBudget(budget: Budget): Budget
    suspend fun movements(householdId: String, from: LocalDate, through: LocalDate): List<Movement>

    suspend fun recurringSeries(householdId: String): List<RecurringSeries>
    suspend fun createRecurring(series: RecurringSeries): RecurringSeries
    suspend fun updateRecurring(series: RecurringSeries): RecurringSeries
    suspend fun deleteRecurring(seriesId: String)
    suspend fun goals(householdId: String): List<Goal>
    suspend fun createGoal(goal: Goal): Goal
    suspend fun updateGoal(goal: Goal): Goal
    suspend fun deleteGoal(goalId: String)
    suspend fun contributions(householdId: String): List<GoalContribution>
    suspend fun addContribution(contribution: GoalContribution): GoalContribution
    suspend fun deleteContribution(contributionId: String)

    suspend fun creditCards(householdId: String): List<CreditCardTerms>

    /** Crea o cambia las condiciones de una tarjeta (una por cuenta). */
    suspend fun saveCreditCard(terms: CreditCardTerms): CreditCardTerms
    suspend fun cardInstallments(householdId: String): List<CardInstallment>

    /** Crea o cambia el aplazado de un movimiento (uno por movimiento). */
    suspend fun saveInstallment(installment: CardInstallment): CardInstallment
    suspend fun deleteInstallment(installmentId: String)

    suspend fun holdings(householdId: String): List<Holding>
    suspend fun createHolding(holding: Holding): Holding
    suspend fun updateHolding(holding: Holding): Holding
    suspend fun deleteHolding(holdingId: String)
    suspend fun holdingPrices(householdId: String): List<HoldingPrice>

    /** Apunta el precio de un día (sustituye al de ese día) y devuelve el activo; uno antiguo no cambia el actual. */
    suspend fun recordPrice(price: java.math.BigDecimal, day: LocalDate, holdingId: String): Holding
    suspend fun trades(householdId: String): List<InvestmentTrade>
    suspend fun addTrade(trade: InvestmentTrade): InvestmentTrade
    suspend fun deleteTrade(tradeId: String)
    suspend fun investmentPlans(householdId: String): List<InvestmentPlan>
    suspend fun createPlan(plan: InvestmentPlan): InvestmentPlan
    suspend fun updatePlan(plan: InvestmentPlan): InvestmentPlan
    suspend fun deletePlan(planId: String)

    /** Los del usuario con sesión, del más reciente al más antiguo. */
    suspend fun creditScores(): List<CreditScore>
    suspend fun addCreditScore(score: CreditScore): CreditScore
    suspend fun deleteCreditScore(scoreId: String)
}

/**
 * Modo demo y capturas: todo en memoria, con las reglas de borrado del servidor.
 * shortcut: no comprueba que seas del hogar; en la demo solo hay un hogar abierto cada vez.
 */
class InMemoryFinance : FinanceService {
    private val accounts = mutableListOf<Account>()
    private val categories = mutableListOf<BudgetCategory>()
    private val seeded = mutableSetOf<String>()
    private val movements = mutableListOf<Movement>()

    private fun id() = UUID.randomUUID().toString()
    private fun fail(text: String): Nothing = throw AppError.InvalidInput(text)

    private fun build(draft: MovementDraft, householdId: String): Movement {
        draft.issue?.let(::fail)
        return Movement(
            id(), householdId, draft.accountId, draft.categoryId, draft.bookedOn.toString(), draft.amountMinor,
            draft.description.trim(), draft.notes, draft.importHash,
        )
    }

    override suspend fun resetHousehold(householdId: String) {
        accounts.removeAll { it.householdId == householdId }
        categories.removeAll { it.householdId == householdId }
        seeded -= householdId
        movements.removeAll { it.householdId == householdId }
        budgets.removeAll { it.householdId == householdId }
        series.removeAll { it.householdId == householdId }
        goals.removeAll { it.householdId == householdId }
        contributions.removeAll { it.householdId == householdId }
        cards.removeAll { it.householdId == householdId }
        installments.removeAll { it.householdId == householdId }
        holdings.removeAll { it.householdId == householdId }
        prices.removeAll { it.householdId == householdId }
        trades.removeAll { it.householdId == householdId }
        plans.removeAll { it.householdId == householdId }
    }

    override suspend fun accounts(householdId: String) = accounts.filter { it.householdId == householdId }

    override suspend fun balances(householdId: String) = accounts(householdId).associate { a ->
        a.id to a.openingMinor + movements.filter { it.accountId == a.id }.sumOf { it.amountMinor }
    }

    override suspend fun createAccount(draft: AccountDraft, householdId: String): Account {
        draft.issue?.let(::fail)
        return Account(id(), householdId, draft.trimmedName, draft.kind, openingMinor = draft.openingMinor, ownerId = draft.ownerId)
            .also { accounts += it }
    }

    override suspend fun updateAccount(account: Account): Account {
        val i = accounts.indexOfFirst { it.id == account.id }
        if (i < 0) throw AppError.Unknown("cuenta")
        accounts[i] = account.copy(name = account.name.trim())
        return accounts[i]
    }

    override suspend fun deleteAccount(accountId: String) {
        accounts.removeAll { it.id == accountId }
        movements.removeAll { it.accountId == accountId }
        cards.removeAll { it.accountId == accountId }
        installments.removeAll { it.accountId == accountId }
        cards.replaceAll { if (it.payFromAccountId == accountId) it.copy(payFromAccountId = null) else it }
    }

    override suspend fun categories(householdId: String): List<BudgetCategory> {
        if (seeded.add(householdId)) categories += BudgetCategory.defaults(householdId)
        return categories.filter { it.householdId == householdId }.sortedBy { it.name }
    }

    override suspend fun createCategory(category: BudgetCategory): BudgetCategory {
        category.issue(categories)?.let(::fail)
        return category.copy(id = id(), name = category.trimmedName).also { categories += it }
    }

    override suspend fun updateCategory(category: BudgetCategory): BudgetCategory {
        category.issue(categories)?.let(::fail)
        val i = categories.indexOfFirst { it.id == category.id }
        if (i < 0) throw AppError.Unknown("categoría")
        categories[i] = category.copy(name = category.trimmedName, kind = categories[i].kind)
        return categories[i]
    }

    override suspend fun deleteCategory(categoryId: String) {
        categories.removeAll { it.id == categoryId }
        movements.replaceAll { if (it.categoryId == categoryId) it.copy(categoryId = null) else it }
    }

    override suspend fun movements(householdId: String, accountId: String?, limit: Int) = movements
        .filter { it.householdId == householdId && (accountId == null || it.accountId == accountId) }
        .asReversed()
        .sortedByDescending { it.bookedOn }
        .take(limit)

    override suspend fun addMovement(draft: MovementDraft, householdId: String) =
        build(draft, householdId).also { movements += it }

    override suspend fun updateMovement(movement: Movement): Movement {
        movement.toDraft().issue?.let(::fail)
        val i = movements.indexOfFirst { it.id == movement.id }
        if (i < 0) throw AppError.Unknown("movimiento")
        movements[i] = movement.copy(description = movement.description.trim())
        return movements[i]
    }

    override suspend fun deleteMovement(movementId: String) {
        movements.removeAll { it.id == movementId }
        installments.removeAll { it.movementId == movementId }
    }

    override suspend fun importMovements(drafts: List<MovementDraft>, householdId: String): ImportResult {
        var inserted = 0
        var duplicates = 0
        for (draft in drafts) {
            val movement = build(draft, householdId)
            if (movement.importHash != null && movements.any { it.accountId == movement.accountId && it.importHash == movement.importHash }) {
                duplicates++
            } else {
                movements += movement
                inserted++
            }
        }
        return ImportResult(inserted, duplicates)
    }

    private val budgets = mutableListOf<Budget>()

    override suspend fun budget(householdId: String, month: YearMonth) =
        budgets.firstOrNull { it.householdId == householdId && it.month == month }

    override suspend fun latestBudget(householdId: String, month: YearMonth) =
        budgets.filter { it.householdId == householdId && it.month < month }.maxByOrNull { it.month }

    override suspend fun saveBudget(budget: Budget): Budget {
        budget.issue?.let(::fail)
        budgets.removeAll { it.householdId == budget.householdId && it.month == budget.month }
        budgets += budget
        return budget
    }

    override suspend fun movements(householdId: String, from: LocalDate, through: LocalDate) =
        movements.filter { it.householdId == householdId && it.day in from..through }

    private val series = mutableListOf<RecurringSeries>()
    private val goals = mutableListOf<Goal>()
    private val contributions = mutableListOf<GoalContribution>()

    override suspend fun recurringSeries(householdId: String) = series.filter { it.householdId == householdId }.sortedBy { it.name }

    override suspend fun createRecurring(series: RecurringSeries): RecurringSeries {
        series.issue?.let(::fail)
        return series.copy(id = id(), name = series.trimmedName).also { this.series += it }
    }

    override suspend fun updateRecurring(series: RecurringSeries): RecurringSeries {
        series.issue?.let(::fail)
        this.series.replaceAll { if (it.id == series.id) series else it }
        return series
    }

    override suspend fun deleteRecurring(seriesId: String) {
        series.removeAll { it.id == seriesId }
    }

    override suspend fun goals(householdId: String) = goals.filter { it.householdId == householdId }

    override suspend fun createGoal(goal: Goal): Goal {
        goal.issue?.let(::fail)
        return goal.copy(id = id(), name = goal.trimmedName).also { goals += it }
    }

    override suspend fun updateGoal(goal: Goal): Goal {
        goal.issue?.let(::fail)
        goals.replaceAll { if (it.id == goal.id) goal else it }
        return goal
    }

    override suspend fun deleteGoal(goalId: String) {
        goals.removeAll { it.id == goalId }
        contributions.removeAll { it.goalId == goalId }
    }

    override suspend fun contributions(householdId: String) =
        contributions.filter { it.householdId == householdId }.sortedByDescending { it.madeOn }

    override suspend fun addContribution(contribution: GoalContribution): GoalContribution {
        contribution.issue?.let(::fail)
        return contribution.copy(id = id()).also { contributions += it }
    }

    override suspend fun deleteContribution(contributionId: String) {
        contributions.removeAll { it.id == contributionId }
    }

    private val cards = mutableListOf<CreditCardTerms>()
    private val installments = mutableListOf<CardInstallment>()

    override suspend fun creditCards(householdId: String) = cards.filter { it.householdId == householdId }

    override suspend fun saveCreditCard(terms: CreditCardTerms): CreditCardTerms {
        terms.issue?.let(::fail)
        if (accounts.none { it.id == terms.accountId && it.kind == AccountKind.CreditCard }) fail("Esa cuenta no es una tarjeta de crédito.")
        cards.removeAll { it.accountId == terms.accountId }
        cards += terms
        return terms
    }

    override suspend fun cardInstallments(householdId: String) = installments.filter { it.householdId == householdId }

    override suspend fun saveInstallment(installment: CardInstallment): CardInstallment {
        installment.issue?.let(::fail)
        if (movements.none { it.id == installment.movementId && it.accountId == installment.accountId }) fail("Solo se aplazan compras de la tarjeta.")
        val saved = installment.copy(id = installments.firstOrNull { it.movementId == installment.movementId }?.id ?: id())
        installments.removeAll { it.id == saved.id }
        installments += saved
        return saved
    }

    override suspend fun deleteInstallment(installmentId: String) {
        installments.removeAll { it.id == installmentId }
    }

    private val holdings = mutableListOf<Holding>()
    private val prices = mutableListOf<HoldingPrice>()
    private val trades = mutableListOf<InvestmentTrade>()
    private val plans = mutableListOf<InvestmentPlan>()

    override suspend fun holdings(householdId: String) = holdings.filter { it.householdId == householdId }.sortedBy { it.trimmedName }

    override suspend fun createHolding(holding: Holding): Holding {
        holding.issue?.let(::fail)
        return holding.copy(id = id(), name = holding.trimmedName, symbol = holding.trimmedSymbol).also { holdings += it }
    }

    override suspend fun updateHolding(holding: Holding): Holding {
        holding.issue?.let(::fail)
        val saved = holding.copy(name = holding.trimmedName, symbol = holding.trimmedSymbol)
        holdings[holdings.indexOfFirst { it.id == holding.id }] = saved
        return saved
    }

    override suspend fun deleteHolding(holdingId: String) {
        holdings.removeAll { it.id == holdingId }
        prices.removeAll { it.holdingId == holdingId }
        trades.removeAll { it.holdingId == holdingId }
        plans.removeAll { it.holdingId == holdingId }
    }

    override suspend fun holdingPrices(householdId: String) = prices.filter { it.householdId == householdId }.sortedBy { it.pricedOn }

    override suspend fun recordPrice(price: java.math.BigDecimal, day: LocalDate, holdingId: String): Holding {
        if (price.signum() < 0) fail("El precio no puede ser negativo.")
        val index = holdings.indexOfFirst { it.id == holdingId }
        val holding = holdings[index]
        prices.removeAll { it.holdingId == holdingId && it.day == day }
        prices += HoldingPrice(id(), holding.householdId, holdingId, day.toString(), price)
        if (holding.priceDay?.isAfter(day) == true) return holding
        return holding.copy(price = price, priceOn = day.toString()).also { holdings[index] = it }
    }

    override suspend fun trades(householdId: String) = trades.filter { it.householdId == householdId }.sortedBy { it.tradedOn }

    override suspend fun addTrade(trade: InvestmentTrade): InvestmentTrade {
        trade.issue(trades.filter { it.holdingId == trade.holdingId })?.let(::fail)
        return trade.copy(id = id()).also { trades += it }
    }

    override suspend fun deleteTrade(tradeId: String) { trades.removeAll { it.id == tradeId } }

    override suspend fun investmentPlans(householdId: String) = plans.filter { it.householdId == householdId }.sortedBy { it.startsOn }

    override suspend fun createPlan(plan: InvestmentPlan): InvestmentPlan {
        plan.issue?.let(::fail)
        return plan.copy(id = id()).also { plans += it }
    }

    override suspend fun updatePlan(plan: InvestmentPlan): InvestmentPlan {
        plan.issue?.let(::fail)
        plans[plans.indexOfFirst { it.id == plan.id }] = plan
        return plan
    }

    override suspend fun deletePlan(planId: String) { plans.removeAll { it.id == planId } }

    private val scores = mutableListOf<CreditScore>()

    override suspend fun creditScores() = scores.sortedByDescending { it.recordedOn }

    override suspend fun addCreditScore(score: CreditScore): CreditScore {
        score.issue?.let(::fail)
        return score.copy(id = id()).also { scores += it }
    }

    override suspend fun deleteCreditScore(scoreId: String) {
        scores.removeAll { it.id == scoreId }
    }
}
