package com.savethemoney.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import com.savethemoney.android.data.Account
import com.savethemoney.android.data.AccountDraft
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.BudgetCategory
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.ImportResult
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.ui.icons.StmIcons
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.text.Collator
import java.time.LocalDate
import java.util.Locale

/** Qué abre la pantalla 07: un movimiento a editar, una cuenta preelegida o una transferencia. */
data class MovementForm(val movement: Movement? = null, val accountId: String? = null, val transfer: Boolean = false)

/** Cuentas, saldos, categorías y movimientos del hogar abierto (FinanceModel de iOS). */
class FinanceModel(val household: Household, private val service: FinanceService, val today: () -> LocalDate = LocalDate::now) {
    val budgets = BudgetModel(household, service, today)

    var accounts by mutableStateOf(emptyList<Account>())
        private set
    var balances by mutableStateOf(emptyMap<String, Long>())
        private set
    var categories by mutableStateOf(emptyList<BudgetCategory>())
        private set
    var recent by mutableStateOf(emptyList<Movement>())
        private set
    var error by mutableStateOf<String?>(null)
        private set

    /** Lo que se acaba de borrar en la lista, para poder deshacerlo. */
    var lastDeleted by mutableStateOf<Movement?>(null)

    // El Nav solo apila números de pantalla: estos campos dicen con qué abrirla.
    var selectedMovementId by mutableStateOf<String?>(null)
    var selectedAccountId by mutableStateOf<String?>(null)
    var movementForm: MovementForm? = null
    var accountToEdit: Account? = null
    var csvAccountId: String? = null

    val activeAccounts: List<Account> get() = accounts.filter { !it.isArchived }
    val totalBalance: Long get() = activeAccounts.sumOf(::balance)
    val selectedMovement: Movement? get() = recent.firstOrNull { it.id == selectedMovementId } ?: recent.firstOrNull()
    val selectedAccount: Account? get() = accounts.firstOrNull { it.id == selectedAccountId } ?: activeAccounts.firstOrNull()

    fun balance(account: Account): Long = balances[account.id] ?: account.openingMinor
    fun account(id: String?): Account? = accounts.firstOrNull { it.id == id }
    fun category(id: String?): BudgetCategory? = categories.firstOrNull { it.id == id }

    fun categories(kind: CategoryKind): List<BudgetCategory> {
        val collator = Collator.getInstance(Locale("es", "ES"))
        return categories.filter { it.kind == kind }.sortedWith(compareBy(collator) { it.name })
    }

    private fun thisMonth(m: Movement): Boolean = m.day.withDayOfMonth(1) == today().withDayOfMonth(1)

    /** Lo que ha entrado menos lo que ha salido este mes; las transferencias se compensan. */
    val netThisMonth: Long get() = recent.filter(::thisMonth).sumOf { it.amountMinor }

    /** Gasto del mes sin contar transferencias entre cuentas. */
    val spentThisMonth: Long get() = -recent
        .filter { thisMonth(it) && it.isExpense && category(it.categoryId)?.kind != CategoryKind.Transfer }
        .sumOf { it.amountMinor }

    fun takeMovementForm(): MovementForm = (movementForm ?: MovementForm()).also { movementForm = null }
    fun takeAccountToEdit(): Account? = accountToEdit.also { accountToEdit = null }
    fun takeCsvAccount(): String? = csvAccountId.also { csvAccountId = null }

    /** Nunca lanza: si falla, se quedan los datos que había y [error] dice por qué. */
    suspend fun load() {
        try {
            val id = household.id
            coroutineScope {
                val a = async { service.accounts(id) }
                val b = async { service.balances(id) }
                val c = async { service.categories(id) }
                val r = async { service.movements(id, null, RECENT_LIMIT) }
                accounts = a.await()
                balances = b.await()
                categories = c.await()
                recent = r.await()
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

    suspend fun movements(account: Account): List<Movement> = service.movements(household.id, account.id, RECENT_LIMIT)

    suspend fun createAccount(draft: AccountDraft) { service.createAccount(draft, household.id); reloadAccounts() }
    suspend fun updateAccount(account: Account) { service.updateAccount(account); reloadAccounts() }
    suspend fun deleteAccount(account: Account) { service.deleteAccount(account.id); reloadAll() }

    suspend fun add(draft: MovementDraft) { service.addMovement(draft, household.id); reloadAll() }
    suspend fun update(movement: Movement) { service.updateMovement(movement); reloadAll() }

    suspend fun delete(movement: Movement) {
        service.deleteMovement(movement.id)
        reloadAll()
        lastDeleted = movement
    }

    suspend fun undoDelete() {
        val movement = lastDeleted ?: return
        add(movement.toDraft())
        lastDeleted = null
    }

    /** También para las dos patas de una transferencia: van en una sola petición. */
    suspend fun importMovements(drafts: List<MovementDraft>): ImportResult =
        service.importMovements(drafts, household.id).also { reloadAll() }

    suspend fun save(category: BudgetCategory) {
        category.issue(categories)?.let { throw AppError.InvalidInput(it) }
        if (categories.any { it.id == category.id }) service.updateCategory(category) else service.createCategory(category)
        categories = service.categories(household.id)
    }

    suspend fun delete(category: BudgetCategory) {
        service.deleteCategory(category.id)
        categories = service.categories(household.id)
        reloadAll()
    }

    private suspend fun reloadAccounts() {
        accounts = service.accounts(household.id)
        balances = service.balances(household.id)
    }

    private suspend fun reloadAll() {
        reloadAccounts()
        recent = service.movements(household.id, null, RECENT_LIMIT)
    }

    private companion object {
        const val RECENT_LIMIT = 500
    }
}

/** Fechas en español con los textos del diseño ("Hoy", "3 de noviembre", "5 nov 2026"). */
object Fechas {
    private val meses = listOf(
        "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
    )

    fun mes(d: LocalDate): String = meses[d.monthValue - 1]
    fun mesTitulo(d: LocalDate): String = mes(d).replaceFirstChar { it.uppercase() }
    fun corto(d: LocalDate) = "${d.dayOfMonth} ${mes(d).take(3)}"

    /** Cabecera de grupo: "Hoy", "Ayer", "3 de noviembre", y el año si no es el actual. */
    fun dia(d: LocalDate, hoy: LocalDate): String = when (d) {
        hoy -> "Hoy"
        hoy.minusDays(1) -> "Ayer"
        else -> "${d.dayOfMonth} de ${mes(d)}" + if (d.year != hoy.year) " de ${d.year}" else ""
    }

    /** "Hoy, 5 nov 2026" o "3 nov 2026". */
    fun largo(d: LocalDate, hoy: LocalDate): String = (if (d == hoy) "Hoy, " else "") + "${corto(d)} ${d.year}"

    /** "03/10/2026", como en la vista previa del CSV. */
    fun numerica(d: LocalDate): String = "%02d/%02d/%d".format(d.dayOfMonth, d.monthValue, d.year)
}

/** Icono del diseño para el nombre de símbolo que guarda la base de datos. */
fun iconoCategoria(category: BudgetCategory?): ImageVector = when (category?.icon) {
    "banknote" -> if (category.kind == CategoryKind.Income) StmIcons.work else StmIcons.savings
    "plus.circle" -> StmIcons.add
    "house" -> StmIcons.home
    "cart", "bag" -> StmIcons.shoppingCart
    "bolt" -> StmIcons.bolt
    "car" -> StmIcons.directionsCar
    "cross.case" -> StmIcons.fitnessCenter
    "shield" -> StmIcons.lock
    "building.columns" -> StmIcons.accountBalance
    "exclamationmark.triangle" -> StmIcons.gavel
    "doc.text" -> StmIcons.description
    "fork.knife" -> StmIcons.restaurant
    "ticket" -> StmIcons.theaterComedy
    "airplane" -> StmIcons.flight
    "repeat" -> StmIcons.subscriptions
    "chart.line.uptrend.xyaxis" -> StmIcons.trendingUp
    "creditcard" -> StmIcons.creditCard
    "arrow.left.arrow.right" -> StmIcons.syncAlt
    else -> StmIcons.category
}

fun iconoCuenta(kind: AccountKind): ImageVector = when (kind) {
    AccountKind.Checking -> StmIcons.accountBalance
    AccountKind.Savings -> StmIcons.savings
    AccountKind.CreditCard -> StmIcons.creditCard
    AccountKind.Investment -> StmIcons.trendingUp
    AccountKind.Loan -> StmIcons.description
    AccountKind.Cash, AccountKind.Other -> StmIcons.category
}
