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
import com.savethemoney.android.data.MovementSearch
import com.savethemoney.android.data.MovementTags
import com.savethemoney.android.data.Payee
import com.savethemoney.android.data.PendingCharge
import com.savethemoney.android.data.ReportPeriod
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

    /**
     * La lista de Movimientos que se ve (la general o la de una cuenta), por páginas y con la búsqueda hecha en el servidor
     * (ORC-85). Va aparte de [recent]: saldos, resúmenes y sugerencias siguen viendo lo mismo que antes.
     */
    var list by mutableStateOf(MovementList())
        private set

    /** Por qué no se ha podido cargar la lista o su página siguiente. Lo ya cargado se queda. */
    var listError by mutableStateOf<String?>(null)
        private set
    private var listLoads by mutableStateOf(0)

    /** Se está cargando la lista o una página. */
    val isLoadingList: Boolean get() = listLoads > 0

    /** La lista se ha abierto alguna vez: desde entonces se recarga con cada cambio. */
    private var listShown = false
    var error by mutableStateOf<String?>(null)
        private set

    /** Qué lectura gana cuando dos se cruzan (ORC-122). */
    private val turns = ReadTurns()
    private var loads = 0

    /** Hay una carga completa en marcha. */
    val isLoading: Boolean get() = loads > 0

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

    /**
     * Cambio del patrimonio en el mes del hogar: lo que ha entrado menos lo que ha salido en las cuentas que cuentan;
     * las transferencias se compensan. Una cuenta archivada cuenta hasta el día en que se archivó (como en iOS).
     */
    val netThisMonth: Long get() {
        val period = ReportPeriod.ThisMonth.range(today(), household.monthStartDay)
        val counted = accounts.filter { it.includeInNetWorth }.associateBy { it.id }
        return recent.filter { m ->
            val account = counted[m.accountId] ?: return@filter false
            m.day in period && (account.archivedAt?.let { m.day < LocalDate.parse(it.take(10)) } ?: true)
        }.sumOf { it.amountMinor }
    }

    /** Gasto del mes del hogar sin contar transferencias entre cuentas. */
    val spentThisMonth: Long get() {
        val period = ReportPeriod.ThisMonth.range(today(), household.monthStartDay)
        return -recent
            .filter { it.day in period && it.isExpense && !it.excluded && category(it.categoryId)?.kind != CategoryKind.Transfer }
            .sumOf { it.amountMinor }
    }

    fun takeMovementForm(): MovementForm = (movementForm ?: MovementForm()).also { movementForm = null }
    fun takeAccountToEdit(): Account? = accountToEdit.also { accountToEdit = null }
    fun takeCsvAccount(): String? = csvAccountId.also { csvAccountId = null }

    /** Nunca lanza: si falla, se quedan los datos que había y [error] dice por qué. */
    suspend fun load() {
        val turn = turns.next()
        loads++
        try {
            val id = household.id
            coroutineScope {
                val a = async { service.accounts(id) }
                val b = async { service.balances(id) }
                val c = async { service.categories(id) }
                val r = async { service.movements(id, null, RECENT_LIMIT) }
                // Todo o nada: se espera a las cuatro antes de guardar ninguna.
                val newAccounts = a.await()
                val newBalances = b.await()
                val newCategories = c.await()
                val newRecent = r.await()
                turns.store(::accounts, newAccounts, turn)
                turns.store(::balances, newBalances, turn)
                turns.store(::categories, newCategories, turn)
                turns.store(::recent, newRecent, turn)
            }
            turns.store(::error, null, turn)
            reloadList()
            planning.load()
            planning.syncCharges(recent)
            budgets.load()
            budgets.checkAlerts(categories)
            cards.load(accounts, balances, categories)
            investments.load()
        } catch (e: Exception) {
            turns.fallaCarga(::error, turn, e)
        } finally {
            loads--
        }
    }

    /** Los últimos movimientos de la cuenta, para su gráfico. */
    suspend fun movements(account: Account): List<Movement> = service.movements(household.id, account.id, RECENT_LIMIT)

    /** Enseña la lista de esa cuenta (nula: todas) con esa búsqueda. Si es otra lista empieza de cero; si es la misma, vuelve a cargar lo que ya se veía. */
    suspend fun showList(accountId: String?, search: String) {
        listShown = true
        if (list.accountId != accountId || list.search != search) {
            // Desde aquí, una lectura de la lista anterior que llegue tarde ya no la pisa.
            turns.changed(::list, MovementList(accountId, search))
            turns.changed(::listError, null)
        }
        reloadList()
    }

    /**
     * La página siguiente, al llegar al final. Si falla, lo cargado se queda, [listError] lo dice y se puede volver a pedir.
     * No pide nada mientras otra lectura de la lista está en marcha: empezaría en un sitio viejo.
     */
    suspend fun loadMoreList() {
        val base = list
        val last = base.rows.lastOrNull() ?: return
        if (!base.hasMore || listLoads > 0) return
        readList {
            val (rows, hasMore) = fetchList(base, last, LIST_PAGE_SIZE)
            base.copy(rows = base.rows + rows, hasMore = hasMore)
        }
    }

    /** «Reintentar»: vuelve a cargar lo que había y una página más. */
    suspend fun retryList() = reloadList(LIST_PAGE_SIZE)

    /** Vuelve a pedir la lista abierta desde el principio, tantas filas como se veían (como poco una página). */
    private suspend fun reloadList(extra: Int = 0) {
        if (!listShown) return
        val current = list
        readList {
            val (rows, hasMore) = fetchList(current, null, maxOf(current.rows.size + extra, LIST_PAGE_SIZE))
            current.copy(rows = rows, hasMore = hasMore)
        }
    }

    /** Una lectura de la lista con su turno: lo que trae (o su error) sólo se guarda si nada que empezó después lo ha guardado ya. */
    private suspend fun readList(read: suspend () -> MovementList) {
        val turn = turns.next()
        listLoads++
        try {
            val loaded = read()
            turns.store(::list, loaded, turn)
            turns.store(::listError, null, turn)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            val message = (e as? AppError)?.message ?: AppError.Unknown("app").message
            turns.store(::listError, "No se han podido cargar los movimientos. $message", turn)
        } finally {
            listLoads--
        }
    }

    /**
     * Pide al menos [count] filas detrás de [after], página a página, hasta tenerlas o llegar al final. Una página que llega
     * incompleta es el final; una llena dice que puede haber más.
     */
    private suspend fun fetchList(list: MovementList, after: Movement?, count: Int): Pair<List<Movement>, Boolean> {
        val search = MovementSearch.of(list.search, categories)
        val rows = mutableListOf<Movement>()
        var cursor = after
        while (true) {
            val page = service.movements(household.id, list.accountId, search, cursor, LIST_PAGE_SIZE)
            rows += page
            if (page.size < LIST_PAGE_SIZE) return rows to false
            if (rows.size >= count) return rows to true
            cursor = page.last()
        }
    }

    // Escrituras: cada una corre como [escritura], así que termina (y recarga) aunque se salga de la pantalla.

    /** Una escritura falló cuando su pantalla ya no estaba: el aviso sale en el error del modelo. */
    private fun sinPantalla(e: Exception) {
        turns.changed(::error, (e as? AppError)?.message ?: AppError.Unknown("app").message)
    }

    suspend fun createAccount(draft: AccountDraft): Account = escritura(::sinPantalla) { guardarYRecargar(::reloadAccounts) { service.createAccount(draft, household.id) } }
    suspend fun updateAccount(account: Account): Unit = escritura(::sinPantalla) { guardarYRecargar(::reloadAccounts) { service.updateAccount(account) } }
    suspend fun deleteAccount(account: Account): Unit = escritura(::sinPantalla) {
        service.deleteAccount(account.id)
        reloadAll()
        reloadReferences()
    }

    /** «Actualizar saldo»: apunta hoy un ajuste para que el saldo de la cuenta sea [actual]. */
    suspend fun adjustBalance(account: Account, actual: Long) {
        BalanceAdjustment.draft(account, balance(account), actual, today(), categories)?.let { add(it) }
    }

    suspend fun add(draft: MovementDraft): Unit = escritura(::sinPantalla) { service.addMovement(draft, household.id); reloadAll() }

    /** Las dos patas de una transferencia (o el pago de una tarjeta): se guardan las dos o ninguna, y repetirla no duplica. */
    suspend fun transfer(draft: com.savethemoney.android.data.TransferDraft): Unit = escritura(::sinPantalla) {
        try {
            service.addTransfer(draft, household.id)
        } catch (e: AppError) {
            // Puede que ya estuviera guardada (con otros datos): se recarga para que se vea detrás del aviso.
            reloadAll()
            throw e
        }
        reloadAll()
    }

    /** Una compra o venta y, con [cash], su movimiento en la cuenta: los dos o ninguno, y repetirla no duplica. */
    suspend fun addTrade(trade: com.savethemoney.android.data.InvestmentTrade, cash: com.savethemoney.android.data.TradeCash?): Unit = escritura(::sinPantalla) {
        try {
            investments.add(trade, cash)
        } finally {
            // Saldos y movimientos al día; también si falla, por si se guardó y no llegó la respuesta.
            if (cash != null) reloadAll()
        }
    }
    suspend fun update(movement: Movement) { update(listOf(movement)) }

    /** Guarda varios movimientos ya cambiados (edición masiva, «cambiar similares»). Recarga una vez al final. */
    suspend fun update(movements: List<Movement>): Unit = escritura(::sinPantalla) {
        if (movements.isEmpty()) return@escritura
        try {
            // Guardar una pata de transferencia cambia también la otra (importe y día): si la otra también está en la lista,
            // se guarda sobre su versión nueva, que ya trae lo mismo, en vez de fallar como si la hubiera cambiado otro dispositivo.
            val versions = mutableMapOf<String, String?>()
            movements.forEach { m ->
                val saved = service.updateMovement(if (m.id in versions) m.copy(updatedAt = versions[m.id]) else m)
                if (saved.id == tappedMovement?.id) tappedMovement = saved
                val pairs = movements.filter { it.transferId != null && it.transferId == saved.transferId && it.id != saved.id }
                if (pairs.isNotEmpty()) service.movements(household.id, pairs.map { it.id }).forEach { versions[it.id] = it.updatedAt }
            }
        } catch (e: AppError.MovementChanged) {
            // Otro dispositivo lo cambió antes: se recarga (también el que está abierto) para que se vea lo nuevo detrás del aviso.
            reloadAll()
            try {
                tappedMovement = tappedMovement?.let { service.movements(household.id, listOf(it.id)).firstOrNull() }
            } catch (_: AppError) {
            }
            throw e
        }
        reloadAll()
    }

    /** Borra varios a la vez (sin «Deshacer»: la pantalla pide confirmación antes). Una pata de transferencia se lleva la otra. */
    suspend fun delete(movements: List<Movement>): Unit = escritura(::sinPantalla) {
        val transfers = mutableSetOf<String>()
        movements.forEach { m ->
            val transferId = m.transferId
            if (transferId == null) service.deleteMovement(m.id) else if (transfers.add(transferId)) service.deleteTransfer(transferId)
        }
        if (movements.any { it.id == tappedMovement?.id || (it.transferId != null && it.transferId == tappedMovement?.transferId) }) {
            tappedMovement = null
        }
        reloadAll()
    }

    /** La cuenta que sale elegida al apuntar: la predeterminada o la primera activa. */
    val defaultAccount: Account? get() = accounts.defaultAccount()

    /** Etiquetas y beneficiarios usados, para sugerir al escribir. */
    val knownTags: List<String> get() = MovementTags.all(recent)
    val knownPayees: List<String> get() = Payee.all(recent)

    /** Una pata de transferencia se borra con la otra y sin «Deshacer», que solo volvería a apuntar una. */
    suspend fun delete(movement: Movement): Unit = escritura(::sinPantalla) {
        val transferId = movement.transferId
        if (transferId == null) service.deleteMovement(movement.id) else service.deleteTransfer(transferId)
        if (movement.id == tappedMovement?.id) tappedMovement = null
        reloadAll()
        lastDeleted = movement.takeIf { transferId == null }
    }

    suspend fun undoDelete(): Unit = escritura(::sinPantalla) {
        val movement = lastDeleted ?: return@escritura
        add(movement.toDraft())
        lastDeleted = null
    }

    /** Varios movimientos de golpe (CSV). Las transferencias van por [transfer]. */
    suspend fun importMovements(drafts: List<MovementDraft>): ImportResult =
        escritura(::sinPantalla) { service.importMovements(drafts, household.id).also { reloadAll() } }

    /**
     * Una categoría sin versión ([BudgetCategory.updatedAt]) aún no se ha leído del servidor: es un alta, con el id que le dio
     * el formulario, y guardarla otra vez con el mismo no crea otra. Con versión es un cambio sobre esa versión.
     */
    suspend fun save(category: BudgetCategory): Unit = escritura(::sinPantalla) {
        category.issue(categories)?.let { throw AppError.InvalidInput(it) }
        val saved = try {
            if (category.updatedAt == null) service.createCategory(category) else service.updateCategory(category)
        } catch (e: AppError) {
            // Si otro dispositivo la cambió antes, se recarga para que se vea lo nuevo detrás del aviso.
            reloadAfterSave { reloadCategories() }
            throw e
        }
        // Se ve ya, aunque falle la recarga.
        turns.changed(::categories, categories.filter { it.id != category.id && it.id != saved.id } + saved)
        reloadAfterSave { reloadCategories() }?.let { turns.changed(::error, it) }
    }

    suspend fun delete(category: BudgetCategory): Unit = escritura(::sinPantalla) {
        service.deleteCategory(category.id)
        turns.changed(::categories, categories.filter { it.id != category.id })
        reloadAfterSave { reloadCategories() }?.let { turns.changed(::error, it) }
        reloadAll()
        reloadReferences()
    }

    /** El CSV con todos los movimientos del hogar, listo para Excel. */
    suspend fun exportCsv(): ByteArray =
        MovementsCsv.bytes(service.movements(household.id, LocalDate.of(1900, 1, 1), LocalDate.of(2999, 12, 31)), accounts, categories)

    /** Borra todo lo apuntado en el hogar y vuelve a cargar. */
    suspend fun resetHousehold(): Unit = escritura(::sinPantalla) {
        service.resetHousehold(household.id)
        load()
    }

    /** Tras guardar. Nunca lanza: lo guardado sigue guardado y, si falla, [error] lo dice como problema de carga. */
    private suspend fun reloadAccounts() {
        reloadAfterSave { fetchAccounts() }?.let { turns.changed(::error, it) }
    }

    /** Como [reloadAccounts], con los movimientos. */
    private suspend fun reloadAll() {
        reloadAfterSave {
            fetchAccounts()
            val turn = turns.next()
            turns.store(::recent, service.movements(household.id, null, RECENT_LIMIT), turn)
            // Pagos fijos: apunta los cargos que han llegado y empareja los que ya entraron por CSV.
            planning.syncCharges(recent)
        }?.let { turns.changed(::error, it) }
        // Lo cambiado puede estar en una página de la lista que no entra en [recent].
        reloadList()
    }

    /**
     * Tras borrar una cuenta o una categoría. El servidor deja sin ella (`on delete set null`, con versión nueva) los pagos
     * fijos, las metas, las inversiones, sus aportaciones y las tarjetas que la usaban, y el presupuesto pierde su límite.
     * Se recargan para que la siguiente edición no dé un falso «ha cambiado en otro dispositivo». Cada carga guarda su error.
     */
    private suspend fun reloadReferences() {
        planning.load()
        budgets.load()
        cards.load(accounts, balances, categories)
        investments.load()
    }

    private suspend fun fetchAccounts() {
        val turn = turns.next()
        val newAccounts = service.accounts(household.id)
        val newBalances = service.balances(household.id)
        turns.store(::accounts, newAccounts, turn)
        turns.store(::balances, newBalances, turn)
        cards.load(accounts, balances, categories)
    }

    private suspend fun reloadCategories() {
        val turn = turns.next()
        turns.store(::categories, service.categories(household.id), turn)
    }

    /**
     * Gasto nuevo en una tarjeta: lo apunta y, según [purchase], lo aplaza con el TIN de la tarjeta
     * o crea su pago fijo. Se valida todo antes de guardar nada.
     */
    suspend fun addCardPurchase(draft: MovementDraft, purchase: CardPurchase): Unit = escritura(::sinPantalla) {
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
    suspend fun confirm(item: PendingCharge, draft: MovementDraft): Unit = escritura(::sinPantalla) {
        planning.confirm(item, draft)
        reloadAll()
    }

    companion object {
        /** Movimientos recientes que se cargan para resúmenes, sugerencias y pagos fijos (la lista va por páginas). */
        private const val RECENT_LIMIT = 500

        /** Filas por página de la lista de Movimientos. */
        const val LIST_PAGE_SIZE = 200
    }
}

/** Lo que se ve en la lista de Movimientos: de qué cuenta (nula: todas), qué se busca y las filas cargadas, en el orden del servidor. */
data class MovementList(
    val accountId: String? = null,
    val search: String = "",
    val rows: List<Movement> = emptyList(),
    /** Puede haber más en el servidor: la última página llegó llena. */
    val hasMore: Boolean = false,
)

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
