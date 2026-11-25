package com.savethemoney.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import com.savethemoney.android.data.Account
import com.savethemoney.android.data.AccountDraft
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.BalanceAdjustment
import com.savethemoney.android.data.MovementFilter
import com.savethemoney.android.data.BudgetCategory
import com.savethemoney.android.data.CardPurchase
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.ImportResult
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.MovementTags
import com.savethemoney.android.data.Payee
import com.savethemoney.android.data.PendingCharge
import com.savethemoney.android.data.defaultAccount
import com.savethemoney.android.data.NoNotifier
import com.savethemoney.android.data.Notifier
import com.savethemoney.android.ui.icons.StmIcons
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.text.Collator
import com.savethemoney.android.data.MovementsCsv
import java.time.LocalDate
import java.util.Locale

/** Qué abre la pantalla 07: un movimiento a editar, una cuenta preelegida o una transferencia. */
data class MovementForm(
    val movement: Movement? = null,
    val accountId: String? = null,
    val transfer: Boolean = false,
    val toAccountId: String? = null,
    val amountMinor: Long? = null,
    val description: String = "",
)

/** Cuentas, saldos, categorías y movimientos del hogar abierto (FinanceModel de iOS). */
class FinanceModel(
    household: Household,
    private val service: FinanceService,
    val today: () -> LocalDate = LocalDate::now,
    notifier: Notifier = NoNotifier,
) {
    /** Cambia si el dueño le pone otro nombre; el id es siempre el mismo. */
    var household by mutableStateOf(household)

    val budgets = BudgetModel(household, service, notifier, today)
    val planning = PlanningModel(household, service, notifier, today)
    val cards = CreditCardModel(household, service, notifier, today)
    val tracking = TrackingModel(household, service, today)
    val investments = InvestmentModel(household, service, notifier, today)

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
    /** El movimiento que se tocó, tal cual salía en su lista: la de una cuenta puede traer movimientos que no están en [recent]. */
    var tappedMovement by mutableStateOf<Movement?>(null)
    var selectedAccountId by mutableStateOf<String?>(null)
    var movementForm: MovementForm? = null
    var accountToEdit: Account? = null
    var newAccountKind: AccountKind? = null
    var csvAccountId: String? = null

    val activeAccounts: List<Account> get() = accounts.filter { !it.isArchived }
    val archivedAccounts: List<Account> get() = accounts.filter { it.isArchived }

    /** Filtros de la lista de Movimientos; se mantienen al ir y volver de un movimiento. */
    var movementFilter by mutableStateOf(MovementFilter())
    /** Patrimonio: saldo de las cuentas activas que cuentan en el patrimonio. */
    val totalBalance: Long get() = activeAccounts.filter { it.includeInNetWorth }.sumOf(::balance)
    /** El tocado, con lo último de [recent] si está ahí; nunca otro. Nulo si no se tocó ninguno o se borró. */
    val selectedMovement: Movement? get() = tappedMovement?.let { t -> recent.firstOrNull { it.id == t.id } ?: t }
    val selectedAccount: Account? get() = accounts.firstOrNull { it.id == selectedAccountId }

    fun balance(account: Account): Long = balances[account.id] ?: account.openingMinor
    fun account(id: String?): Account? = accounts.firstOrNull { it.id == id }
    fun category(id: String?): BudgetCategory? = categories.firstOrNull { it.id == id }

    fun categories(kind: CategoryKind): List<BudgetCategory> {
        val collator = Collator.getInstance(Locale("es", "ES"))
        return categories.filter { it.kind == kind }.sortedWith(compareBy(collator) { it.name })
    }

    private fun thisMonth(m: Movement): Boolean = m.day.withDayOfMonth(1) == today().withDayOfMonth(1)

    /** Cambio del patrimonio este mes: lo que ha entrado menos lo que ha salido en las cuentas que cuentan; las transferencias se compensan. */
    val netThisMonth: Long get() {
        val ids = activeAccounts.filter { it.includeInNetWorth }.map { it.id }.toSet()
        return recent.filter { thisMonth(it) && it.accountId in ids }.sumOf { it.amountMinor }
    }

    /** Gasto del mes sin contar transferencias entre cuentas. */
    val spentThisMonth: Long get() = -recent
        .filter { thisMonth(it) && it.isExpense && !it.excluded && category(it.categoryId)?.kind != CategoryKind.Transfer }
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
            planning.load()
            planning.syncCharges(recent)
            budgets.load()
            budgets.checkAlerts(categories)
            cards.load(accounts, balances, categories)
            investments.load()
        } catch (e: CancellationException) {
            throw e
        } catch (e: AppError) {
            error = e.message
        } catch (e: Exception) {
            error = AppError.Unknown("app").message
        }
    }

    suspend fun movements(account: Account): List<Movement> = service.movements(household.id, account.id, RECENT_LIMIT)

    suspend fun createAccount(draft: AccountDraft): Account = service.createAccount(draft, household.id).also { reloadAccounts() }
    suspend fun updateAccount(account: Account) { service.updateAccount(account); reloadAccounts() }
    suspend fun deleteAccount(account: Account) { service.deleteAccount(account.id); reloadAll() }

    /** «Actualizar saldo»: apunta hoy un ajuste para que el saldo de la cuenta sea [actual]. */
    suspend fun adjustBalance(account: Account, actual: Long) {
        BalanceAdjustment.draft(account, balance(account), actual, today(), categories)?.let { add(it) }
    }

    suspend fun add(draft: MovementDraft) { service.addMovement(draft, household.id); reloadAll() }
    suspend fun update(movement: Movement) { update(listOf(movement)) }

    /** Guarda varios movimientos ya cambiados (edición masiva, «cambiar similares»). Recarga una vez al final. */
    suspend fun update(movements: List<Movement>) {
        if (movements.isEmpty()) return
        movements.forEach { m -> service.updateMovement(m).also { if (it.id == tappedMovement?.id) tappedMovement = it } }
        reloadAll()
    }

    /** Borra varios a la vez (sin «Deshacer»: la pantalla pide confirmación antes). */
    suspend fun delete(movements: List<Movement>) {
        movements.forEach { service.deleteMovement(it.id) }
        if (movements.any { it.id == tappedMovement?.id }) tappedMovement = null
        reloadAll()
    }

    /** La cuenta que sale elegida al apuntar: la predeterminada o la primera activa. */
    val defaultAccount: Account? get() = accounts.defaultAccount()

    /** Etiquetas y beneficiarios usados, para sugerir al escribir. */
    val knownTags: List<String> get() = MovementTags.all(recent)
    val knownPayees: List<String> get() = Payee.all(recent)

    suspend fun delete(movement: Movement) {
        service.deleteMovement(movement.id)
        if (movement.id == tappedMovement?.id) tappedMovement = null
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

    /** El CSV con todos los movimientos del hogar, listo para Excel. */
    suspend fun exportCsv(): ByteArray =
        MovementsCsv.bytes(service.movements(household.id, LocalDate.of(1900, 1, 1), LocalDate.of(2999, 12, 31)), accounts, categories)

    /** Borra todo lo apuntado en el hogar y vuelve a cargar. */
    suspend fun resetHousehold() {
        service.resetHousehold(household.id)
        load()
    }

    private suspend fun reloadAccounts() {
        accounts = service.accounts(household.id)
        balances = service.balances(household.id)
        cards.load(accounts, balances, categories)
    }

    private suspend fun reloadAll() {
        reloadAccounts()
        recent = service.movements(household.id, null, RECENT_LIMIT)
        // Pagos fijos: apunta los cargos que han llegado y empareja los que ya entraron por CSV.
        planning.syncCharges(recent)
    }

    /**
     * Gasto nuevo en una tarjeta: lo apunta y, según [purchase], lo aplaza con el TIN de la tarjeta
     * o crea su pago fijo. Se valida todo antes de guardar nada.
     */
    suspend fun addCardPurchase(draft: MovementDraft, purchase: CardPurchase) {
        draft.issue?.let { throw AppError.InvalidInput(it) }
        val rate = cards.terms[draft.accountId]?.installmentRate ?: 14.0
        val check = Movement("", household.id, draft.accountId, draft.categoryId, draft.bookedOn.toString(), draft.amountMinor, draft.description)
        when (purchase) {
            is CardPurchase.Installments -> CardPurchase.installment(check, purchase.months, rate).issue
            is CardPurchase.Recurring -> CardPurchase.series(check, purchase.recurrence).issue
            CardPurchase.Normal -> null
        }?.let { throw AppError.InvalidInput(it) }
        val movement = service.addMovement(draft, household.id)
        when (purchase) {
            is CardPurchase.Installments -> service.saveInstallment(CardPurchase.installment(movement, purchase.months, rate))
            is CardPurchase.Recurring -> planning.save(CardPurchase.series(movement, purchase.recurrence))
            CardPurchase.Normal -> Unit
        }
        reloadAll()
    }

    /** Confirma un pago fijo pendiente: crea su movimiento y recarga saldos y movimientos. */
    suspend fun confirm(item: PendingCharge, draft: MovementDraft) {
        planning.confirm(item, draft)
        reloadAll()
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
