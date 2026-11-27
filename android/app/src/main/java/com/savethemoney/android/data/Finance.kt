package com.savethemoney.android.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.LocalDate
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
    /** Cuándo se dio de alta: el saldo inicial es el que tenía ese día. Null si no se sabe: cuenta desde siempre. */
    @SerialName("created_at") val createdAt: String? = null,
    /** La que sale elegida al apuntar un movimiento. */
    @SerialName("is_default") val isDefault: Boolean = false,
    /** Si suma en el patrimonio neto. */
    @SerialName("include_in_net_worth") val includeInNetWorth: Boolean = true,
    /** Versión de la fila: el `updated_at` del servidor tal cual llegó (como [Movement.updatedAt]). Se devuelve igual al cambiarla. */
    @SerialName("updated_at") val updatedAt: String? = null,
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
    /** Versión de la fila: el `updated_at` del servidor tal cual llegó (como [Movement.updatedAt]). Se devuelve igual al cambiarla. */
    @SerialName("updated_at") val updatedAt: String? = null,
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

/** Lo que el patrimonio necesita de un movimiento: en qué cuenta, qué día y cuánto. */
interface AccountAmount {
    val accountId: String
    val day: LocalDate
    val amountMinor: Long
}

/**
 * Un movimiento con sólo lo que usa el patrimonio (ORC-149): la descarga completa pesa un tercio que con todas las
 * columnas. [id] sólo sirve para pedir la página siguiente.
 */
@Serializable
data class MovementAmount(
    val id: String,
    @SerialName("account_id") override val accountId: String,
    @SerialName("booked_on") val bookedOn: String,
    @SerialName("amount_minor") override val amountMinor: Long,
) : AccountAmount {
    @kotlinx.serialization.Transient override val day: LocalDate = LocalDate.parse(bookedOn.take(10))

    constructor(movement: Movement) : this(movement.id, movement.accountId, movement.bookedOn, movement.amountMinor)
}

/** Movimiento de una cuenta. Importe negativo = gasto, positivo = ingreso. */
@Serializable
data class Movement(
    val id: String,
    @SerialName("household_id") val householdId: String,
    @SerialName("account_id") override val accountId: String,
    @SerialName("category_id") val categoryId: String? = null,
    @SerialName("booked_on") val bookedOn: String,
    @SerialName("amount_minor") override val amountMinor: Long,
    val description: String,
    val notes: String? = null,
    @SerialName("import_hash") val importHash: String? = null,
    /** No cuenta en presupuesto, informes ni flujo (sí en el saldo). */
    val excluded: Boolean = false,
    /** Cuándo se marcó como revisado (ISO 8601); nulo = sin revisar. */
    @SerialName("reviewed_at") val reviewedAt: String? = null,
    /** A quién se paga o quién paga. */
    val payee: String? = null,
    /** Etiquetas en minúsculas, sin «#». */
    val tags: List<String> = emptyList(),
    /** Versión de la fila: el `updated_at` del servidor tal cual llegó, sin convertirlo a fecha. Se devuelve igual al cambiar el movimiento. */
    @SerialName("updated_at") val updatedAt: String? = null,
    /**
     * El mismo en las dos patas de una transferencia (la salida es la negativa); nulo en el resto de movimientos y en las
     * transferencias apuntadas antes de que existiera. Lo pone el servidor al crearla; no se cambia.
     */
    @SerialName("transfer_id") val transferId: String? = null,
) : AccountAmount {
    /** Se analiza una vez al crear el movimiento: los informes la leen miles de veces. */
    @kotlinx.serialization.Transient override val day: LocalDate = LocalDate.parse(bookedOn.take(10))
    val isExpense: Boolean get() = amountMinor < 0
    val isReviewed: Boolean get() = reviewedAt != null

    fun toDraft() = MovementDraft(accountId, categoryId, day, amountMinor, description, notes, importHash, excluded, payee, tags)
}

/**
 * Lo que se apunta o se importa, antes de guardarlo. [id] lo genera la app una vez por formulario: reintentar tras un
 * fallo de red no apunta el movimiento dos veces.
 */
data class MovementDraft(
    val accountId: String,
    val categoryId: String? = null,
    val bookedOn: LocalDate,
    val amountMinor: Long,
    val description: String,
    val notes: String? = null,
    val importHash: String? = null,
    val excluded: Boolean = false,
    val payee: String? = null,
    val tags: List<String> = emptyList(),
    val id: String = UUID.randomUUID().toString(),
) {
    /** Problema que impide guardarlo, en español, o nulo si es válido. */
    val issue: String? get() {
        val text = description.trim()
        return when {
            text.isEmpty() -> "Escribe un concepto."
            text.length > 200 -> "El concepto es demasiado largo (máximo 200 caracteres)."
            amountMinor == 0L -> "El importe no puede ser cero."
            notes != null && notes.length > 500 -> "Las notas son demasiado largas (máximo 500 caracteres)."
            payee != null && payee.trim().length > 80 -> "El beneficiario es demasiado largo (máximo 80 caracteres)."
            else -> MovementTags.issue(tags)
        }
    }
}

/**
 * Una transferencia entre dos cuentas, antes de guardarla: sale [amountMinor] (siempre positivo) de una y entra en la otra.
 * Por ejemplo el pago de una tarjeta. [id] lo genera la app una vez por formulario: reintentar tras un fallo de red no duplica.
 */
data class TransferDraft(
    val id: String,
    val fromAccountId: String,
    val toAccountId: String,
    val categoryId: String? = null,
    val bookedOn: LocalDate,
    val amountMinor: Long,
    val fromDescription: String,
    val toDescription: String,
    val notes: String? = null,
    val excluded: Boolean = false,
    val payee: String? = null,
    val tags: List<String> = emptyList(),
) {
    /** Las dos patas: la salida de una cuenta y la entrada en la otra. */
    val legs: List<MovementDraft> get() = listOf(
        MovementDraft(fromAccountId, categoryId, bookedOn, -amountMinor, fromDescription, notes, excluded = excluded, payee = payee, tags = tags),
        MovementDraft(toAccountId, categoryId, bookedOn, amountMinor, toDescription, notes, excluded = excluded, payee = payee, tags = tags),
    )

    /** Problema que impide guardarla, en español, o nulo si es válida. */
    val issue: String? get() = when {
        fromAccountId == toAccountId -> "Elige dos cuentas distintas."
        amountMinor <= 0L -> "El importe tiene que ser mayor que cero."
        else -> legs.firstNotNullOfOrNull { it.issue }
    }

    companion object {
        /** Lo que ve quien repite una transferencia ya guardada después de cambiar cuenta, importe o día. */
        const val STORED_WITH_OTHER_DATA = "Esto ya se guardó con otros datos. Cierra el formulario y revisa lo guardado antes de repetirlo."

        /** Lo que ve quien cambia o borra una pata cuando la otra no se puede cambiar con ella. */
        const val OTHER_LEG_LOCKED = "No se puede cambiar la otra parte de la transferencia. Recarga e inténtalo de nuevo."

        /** Lo que se avisa antes de borrar una pata: se borran las dos. */
        const val DELETE_WARNING = "Se borran los dos movimientos, la salida de una cuenta y la entrada en la otra. No se puede deshacer."

        /** Lo que se avisa al editar una pata. */
        const val EDIT_NOTE = "Es una transferencia: el importe y la fecha cambian también en el movimiento de la otra cuenta."
    }
}

data class AccountDraft(
    val name: String,
    val kind: AccountKind = AccountKind.Checking,
    val openingMinor: Long = 0,
    val ownerId: String? = null,
    /** Lo genera la app una vez por formulario: reintentar el alta con el mismo no crea otra cuenta. */
    val id: String = UUID.randomUUID().toString(),
) {
    val trimmedName: String get() = name.trim()

    val issue: String? get() = when {
        trimmedName.isEmpty() -> "Ponle un nombre a la cuenta."
        trimmedName.length > 60 -> "El nombre es demasiado largo (máximo 60 caracteres)."
        else -> null
    }
}

/** «Actualizar saldo»: escribes lo que hay de verdad en la cuenta y se apunta un ajuste por la diferencia. */
object BalanceAdjustment {
    const val DESCRIPTION = "AJUSTE DE SALDO"

    /**
     * El movimiento de ajuste, o nulo si el saldo ya coincide.
     * Va con la categoría de transferencia (si la hay) para que no cuente como gasto ni ingreso.
     */
    fun draft(account: Account, current: Long, actual: Long, day: LocalDate, categories: List<BudgetCategory>): MovementDraft? {
        val difference = actual - current
        if (difference == 0L) return null
        val transfer = categories.firstOrNull { it.kind == CategoryKind.Transfer && it.householdId == account.householdId }
            ?: categories.firstOrNull { it.kind == CategoryKind.Transfer }
        return MovementDraft(account.id, transfer?.id, day, difference, DESCRIPTION)
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

    /**
     * Una página de la lista de movimientos (ORC-85): más recientes primero por día y, dentro del día, por id descendente,
     * como mucho [limit], empezando justo después de [after] (la última fila de la página anterior). Con [accountId], sólo
     * los de esa cuenta; con [search], sólo los que encuentra la búsqueda.
     */
    suspend fun movements(householdId: String, accountId: String?, search: MovementSearch?, after: Movement?, limit: Int): List<Movement>

    /** Movimientos por id, sean o no de los más recientes. Los que ya no existen no vienen. */
    suspend fun movements(householdId: String, ids: List<String>): List<Movement>

    /** Movimientos de la cuenta desde ese día (incluido), más recientes primero, como mucho [limit]. */
    suspend fun movements(householdId: String, accountId: String, since: LocalDate, limit: Int): List<Movement>

    /**
     * Repetir la llamada con el mismo [MovementDraft.id] devuelve el movimiento ya guardado y no apunta nada nuevo (RPC
     * `create_movement`); si se repite con otra cuenta, otro importe u otro día falla con [TransferDraft.STORED_WITH_OTHER_DATA].
     */
    suspend fun addMovement(draft: MovementDraft, householdId: String): Movement

    /**
     * Guarda las dos patas de una transferencia (primero la salida), o ninguna si algo falla (RPC `create_transfer`).
     * Repetir la llamada con el mismo id devuelve las ya guardadas y no apunta nada nuevo; si se repite con otra cuenta,
     * otro importe u otro día falla con [TransferDraft.STORED_WITH_OTHER_DATA].
     */
    suspend fun addTransfer(draft: TransferDraft, householdId: String): List<Movement>

    /**
     * Solo cambia el movimiento si sigue en la versión leída ([Movement.updatedAt], RPC `update_movement`). Si otro
     * dispositivo lo cambió o lo borró antes, no guarda nada y falla con [AppError.MovementChanged]. Devuelve la versión nueva.
     */
    suspend fun updateMovement(movement: Movement): Movement
    suspend fun deleteMovement(movementId: String)

    /**
     * Borra las dos patas de una transferencia ([Movement.transferId]) en una sola llamada, o ninguna (RPC `delete_transfer`).
     * Si la otra pata ya no existe borra la que queda; si ya no queda ninguna no hace nada.
     */
    suspend fun deleteTransfer(transferId: String)

    /** Guarda varios de golpe. Los que ya estaban (misma huella en la cuenta) se ignoran. */
    suspend fun importMovements(drafts: List<MovementDraft>, householdId: String): ImportResult

    /** El presupuesto propio que empieza ese día, o nulo si aún no se ha hecho. */
    suspend fun budget(householdId: String, startingOn: LocalDate): Budget?

    /** El último presupuesto propio que empieza antes de ese día, para proponerlo. */
    suspend fun latestBudget(householdId: String, before: LocalDate): Budget?
    suspend fun saveBudget(budget: Budget): Budget

    /** Cuándo cobra quien ha entrado (nulo si aún no lo ha dicho). Es privado de cada persona. */
    suspend fun paySchedule(): PaySchedule?
    suspend fun savePaySchedule(schedule: PaySchedule): PaySchedule

    /** Presupuestos extra propios del hogar, el favorito primero. */
    suspend fun extraBudgets(householdId: String): List<ExtraBudget>
    suspend fun saveExtraBudget(budget: ExtraBudget): ExtraBudget
    suspend fun deleteExtraBudget(id: String)
    suspend fun movements(householdId: String, from: LocalDate, through: LocalDate): List<Movement>

    /** Todos los movimientos del hogar con sólo cuenta, día e importe, para rehacer el patrimonio (ORC-149). */
    suspend fun movementAmounts(householdId: String): List<MovementAmount> =
        movements(householdId, LocalDate.of(1900, 1, 1), LocalDate.of(2999, 12, 31)).map(::MovementAmount)

    suspend fun recurringSeries(householdId: String): List<RecurringSeries>
    suspend fun createRecurring(series: RecurringSeries): RecurringSeries
    suspend fun updateRecurring(series: RecurringSeries): RecurringSeries
    suspend fun deleteRecurring(seriesId: String)

    /** Cargos propios de los pagos fijos (pendientes, confirmados y saltados). */
    suspend fun recurringCharges(householdId: String): List<RecurringCharge>

    /** Apunta cargos pendientes; los que ya existen (misma serie y día) se ignoran. */
    suspend fun createCharges(charges: List<RecurringCharge>): List<RecurringCharge>

    /** Crea el movimiento del cargo y lo marca como confirmado. Devuelve el movimiento. */
    suspend fun confirmCharge(chargeId: String, draft: MovementDraft): Movement

    /**
     * Enlaza el cargo con un movimiento que ya existe (confirmado) o lo salta. [charge] es el cargo tal como se leyó: solo se
     * cambia si sigue en esa versión ([RecurringCharge.updatedAt]); si no, [AppError.MovementChanged]. Devuelve el cargo con
     * su versión nueva.
     */
    suspend fun updateCharge(charge: RecurringCharge, status: ChargeStatus, transactionId: String?): RecurringCharge
    suspend fun goals(householdId: String): List<Goal>
    suspend fun createGoal(goal: Goal): Goal
    suspend fun updateGoal(goal: Goal): Goal
    suspend fun deleteGoal(goalId: String)
    suspend fun contributions(householdId: String): List<GoalContribution>
    suspend fun addContribution(contribution: GoalContribution): GoalContribution
    suspend fun deleteContribution(contributionId: String)

    suspend fun creditCards(householdId: String): List<CreditCardTerms>

    /**
     * Crea o cambia las condiciones de una tarjeta (una por cuenta). Sin versión ([CreditCardTerms.updatedAt] nulo) es un alta:
     * repetirla devuelve las guardadas y, si ya había otras distintas, falla con [TransferDraft.STORED_WITH_OTHER_DATA]. Con
     * versión es un cambio: solo entra si siguen en esa versión; si no, [AppError.MovementChanged].
     */
    suspend fun saveCreditCard(terms: CreditCardTerms): CreditCardTerms
    suspend fun cardInstallments(householdId: String): List<CardInstallment>

    /**
     * Crea o cambia el aplazado de un movimiento (uno por movimiento), con las mismas reglas que [saveCreditCard]: sin versión
     * es un alta con el `id` que trae; con versión, un cambio de plazo e interés sobre esa versión.
     */
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

    /**
     * Guarda una compra o venta y, con [cash], su movimiento en la cuenta: los dos o ninguno (RPC `create_trade`).
     * Repetir la llamada con el mismo id devuelve la operación ya guardada y no apunta nada nuevo; con otros datos
     * falla con [TransferDraft.STORED_WITH_OTHER_DATA]. Una venta que deje la posición en negativo en cualquier
     * fecha falla con [InvestmentTrade.NOT_ENOUGH_SHARES].
     */
    suspend fun addTrade(trade: InvestmentTrade, cash: TradeCash? = null): InvestmentTrade

    /** Borrar una compra de la que depende una venta posterior falla con [InvestmentTrade.NEEDED_BY_LATER_SALE]. */
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
 * Con `backend` (la demo), cada miembro ve y toca solo lo que ha creado, como el RLS del servidor.
 * shortcut: sin `backend` (pruebas de una sola persona) no comprueba quién eres ni que seas del hogar.
 */
class InMemoryFinance(private val backend: Backend? = null) : FinanceService {
    private val accounts = mutableListOf<Account>()
    private val categories = mutableListOf<BudgetCategory>()

    /** Hogar y persona que ya tienen sus categorías de partida. */
    private val seeded = mutableSetOf<Pair<String, String?>>()
    private val movements = mutableListOf<Movement>()

    /** Quién creó cada fila, por su id (el `created_by` del servidor). */
    private val creators = mutableMapOf<String, String?>()

    /** Las patas de cada transferencia guardada, por su id: repetirla no la duplica. */
    private val transferLegs = mutableMapOf<String, List<String>>()

    private fun id() = UUID.randomUUID().toString()
    private fun fail(text: String): Nothing = throw AppError.InvalidInput(text)

    private suspend fun me() = backend?.currentUserId()

    private suspend fun isMember(householdId: String) =
        backend == null || (backend.currentUserId() != null && backend.households().any { it.id == householdId })

    /** Como `private.is_mine` del servidor: la fila es de quien la creó mientras siga en ese hogar. */
    private suspend fun mine(householdId: String): (String) -> Boolean {
        if (backend == null) return { true }
        val user = backend.currentUserId()
        val member = isMember(householdId)
        return { id -> member && creators[id] == user }
    }

    /** Quien crea una fila tiene que ser del hogar; devuelve quién es, para apuntarlo. */
    private suspend fun creator(householdId: String): String? {
        if (!isMember(householdId)) throw AppError.Unknown("no es miembro")
        return me()
    }

    /** Lo que ve quien usa un id que ya es de otra persona (el 23505 del servidor). */
    private fun idUsed(): Nothing = fail("Ya hay un registro igual guardado. Revisa el formulario.")

    /** Contador para la versión de cada fila: cambia en cada escritura, como `updated_at` en el servidor. */
    private var movementVersion = 0

    private fun nextVersion() = "v${++movementVersion}"

    /**
     * Un alta con un id que ya está guardado, como las funciones `create_…` del servidor (ORC-142): si es de otra persona no
     * vale (23505); si es propia y [same] dice que trae los mismos datos, devuelve la guardada y no se crea nada; con otros
     * datos falla (STM01). Nulo si ese id aún no está guardado.
     */
    private fun <T> replayed(stored: T?, id: String, mine: (String) -> Boolean, same: (T) -> Boolean): T? {
        if (stored == null) return null
        if (!mine(id)) idUsed()
        if (!same(stored)) fail(TransferDraft.STORED_WITH_OTHER_DATA)
        return stored
    }

    /**
     * Como las funciones `update_…` del servidor (ORC-142): una fila borrada ([stored] nulo), ajena o en otra versión que la
     * leída no se cambia (STM05). [creator] es el id de la fila que dice de quién es.
     */
    private suspend fun <T> requireCurrent(stored: T?, creator: String, household: (T) -> String, version: (T) -> String?, seen: String?): T {
        if (stored == null || !mine(household(stored))(creator) || version(stored) != seen) throw AppError.MovementChanged
        return stored
    }

    /** La cuenta y la categoría tienen que ser propias, como pide el RLS al apuntar. */
    private fun build(draft: MovementDraft, householdId: String, mine: (String) -> Boolean): Movement {
        draft.issue?.let(::fail)
        if (!mine(draft.accountId)) throw AppError.Unknown("cuenta de otra persona")
        if (draft.categoryId?.let(mine) == false) throw AppError.Unknown("categoría de otra persona")
        return Movement(
            draft.id, householdId, draft.accountId, draft.categoryId, draft.bookedOn.toString(), draft.amountMinor,
            draft.description.trim(), draft.notes, draft.importHash, draft.excluded, null, Payee.clean(draft.payee), draft.tags,
            nextVersion(),
        )
    }

    /** Como el servidor: borra solo lo tuyo de ese hogar y te repone tus categorías de partida. */
    override suspend fun resetHousehold(householdId: String) {
        val mine = mine(householdId)
        fun <T> MutableList<T>.dropMine(household: (T) -> String, id: (T) -> String) = removeAll { household(it) == householdId && mine(id(it)) }
        accounts.dropMine({ it.householdId }, { it.id })
        categories.dropMine({ it.householdId }, { it.id })
        seeded -= householdId to me()
        movements.dropMine({ it.householdId }, { it.id })
        myBudgets().removeAll { it.householdId == householdId }
        extras.dropMine({ it.householdId }, { it.id })
        series.dropMine({ it.householdId }, { it.id })
        charges.dropMine({ it.householdId }, { it.id })
        goals.dropMine({ it.householdId }, { it.id })
        contributions.dropMine({ it.householdId }, { it.id })
        // Las condiciones de una tarjeta son de quien creó su cuenta.
        cards.dropMine({ it.householdId }, { it.accountId })
        installments.dropMine({ it.householdId }, { it.id })
        holdings.dropMine({ it.householdId }, { it.id })
        prices.dropMine({ it.householdId }, { it.id })
        trades.dropMine({ it.householdId }, { it.id })
        plans.dropMine({ it.householdId }, { it.id })
    }

    override suspend fun accounts(householdId: String): List<Account> {
        val mine = mine(householdId)
        return accounts.filter { it.householdId == householdId && mine(it.id) }
    }

    override suspend fun balances(householdId: String) = accounts(householdId).associate { a ->
        a.id to a.openingMinor + movements.filter { it.accountId == a.id }.sumOf { it.amountMinor }
    }

    override suspend fun createAccount(draft: AccountDraft, householdId: String): Account {
        val user = creator(householdId)
        draft.issue?.let(::fail)
        // Repetir el alta solo vale con el mismo hogar, nombre, tipo y saldo inicial.
        replayed(accounts.firstOrNull { it.id == draft.id }, draft.id, mine(householdId)) {
            it.householdId == householdId && it.name == draft.trimmedName && it.kind == draft.kind && it.openingMinor == draft.openingMinor
        }?.let { return it }
        return Account(
            draft.id, householdId, draft.trimmedName, draft.kind, openingMinor = draft.openingMinor, ownerId = draft.ownerId,
            updatedAt = nextVersion(),
        ).also {
            accounts += it
            creators[it.id] = user
        }
    }

    override suspend fun updateAccount(account: Account): Account {
        val stored = requireCurrent(accounts.firstOrNull { it.id == account.id }, account.id, { it.householdId }, { it.updatedAt }, account.updatedAt)
        val mine = mine(stored.householdId)
        if (account.isDefault && !account.isArchived) {
            // Como en la base de datos: sólo una predeterminada por persona. La que deja de serlo cambia de versión.
            accounts.replaceAll {
                if (it.id != account.id && mine(it.id) && it.isDefault) it.copy(isDefault = false, updatedAt = nextVersion()) else it
            }
        }
        val saved = account.copy(name = account.name.trim(), updatedAt = nextVersion())
        accounts[accounts.indexOfFirst { it.id == account.id }] = saved
        return saved
    }

    override suspend fun deleteAccount(accountId: String) {
        accounts.firstOrNull { it.id == accountId }?.let { if (!mine(it.householdId)(accountId)) return }
        accounts.removeAll { it.id == accountId }
        movements.removeAll { it.accountId == accountId }
        cards.removeAll { it.accountId == accountId }
        installments.removeAll { it.accountId == accountId }
        // Como `on delete set null` del servidor: lo que la usaba se queda sin cuenta y con versión nueva
        // (el disparador `touch_updated_at` también salta en ese cambio).
        cards.replaceAll { if (it.payFromAccountId == accountId) it.copy(payFromAccountId = null, updatedAt = nextVersion()) else it }
        series.replaceAll { if (it.accountId == accountId) it.copy(accountId = null, updatedAt = nextVersion()) else it }
        goals.replaceAll { if (it.accountId == accountId) it.copy(accountId = null, updatedAt = nextVersion()) else it }
        holdings.replaceAll { if (it.accountId == accountId) it.copy(accountId = null, updatedAt = nextVersion()) else it }
        plans.replaceAll { if (it.accountId == accountId) it.copy(accountId = null, updatedAt = nextVersion()) else it }
    }

    override suspend fun categories(householdId: String): List<BudgetCategory> {
        // Cada miembro recibe sus categorías de partida, como el disparador del servidor.
        if (isMember(householdId) && seeded.add(householdId to me())) {
            val user = me()
            BudgetCategory.defaults(householdId).forEach {
                // Como cualquier fila del servidor, nacen con versión.
                categories += it.copy(updatedAt = nextVersion())
                creators[it.id] = user
            }
        }
        val mine = mine(householdId)
        return categories.filter { it.householdId == householdId && mine(it.id) }.sortedBy { it.name }
    }

    override suspend fun createCategory(category: BudgetCategory): BudgetCategory {
        val user = creator(category.householdId)
        // Como el índice único del servidor: el nombre no se repite entre las categorías propias.
        val mine = mine(category.householdId)
        category.issue(categories.filter { mine(it.id) })?.let(::fail)
        // Repetir el alta solo vale con el mismo hogar, nombre y tipo.
        replayed(categories.firstOrNull { it.id == category.id }, category.id, mine) {
            it.householdId == category.householdId && it.name == category.trimmedName && it.kind == category.kind
        }?.let { return it }
        return category.copy(id = category.id.ifEmpty(::id), name = category.trimmedName, updatedAt = nextVersion()).also {
            categories += it
            creators[it.id] = user
        }
    }

    override suspend fun updateCategory(category: BudgetCategory): BudgetCategory {
        val stored = requireCurrent(categories.firstOrNull { it.id == category.id }, category.id, { it.householdId }, { it.updatedAt }, category.updatedAt)
        val mine = mine(stored.householdId)
        category.issue(categories.filter { mine(it.id) })?.let(::fail)
        val saved = category.copy(name = category.trimmedName, kind = stored.kind, updatedAt = nextVersion())
        categories.replaceAll { if (it.id == saved.id) saved else it }
        return saved
    }

    override suspend fun deleteCategory(categoryId: String) {
        categories.firstOrNull { it.id == categoryId }?.let { if (!mine(it.householdId)(categoryId)) return }
        categories.removeAll { it.id == categoryId }
        // Como `on delete set null` del servidor: sin categoría y con versión nueva.
        movements.replaceAll { if (it.categoryId == categoryId) it.copy(categoryId = null, updatedAt = nextVersion()) else it }
        series.replaceAll { if (it.categoryId == categoryId) it.copy(categoryId = null, updatedAt = nextVersion()) else it }
    }

    override suspend fun movements(householdId: String, accountId: String?, limit: Int): List<Movement> {
        val mine = mine(householdId)
        return movements
            .filter { it.householdId == householdId && (accountId == null || it.accountId == accountId) && mine(it.id) }
            .asReversed()
            .sortedByDescending { it.bookedOn }
            .take(limit)
    }

    override suspend fun movements(householdId: String, accountId: String?, search: MovementSearch?, after: Movement?, limit: Int): List<Movement> {
        val mine = mine(householdId)
        // El mismo orden que el servidor: día y, dentro del día, id (como uuid de Postgres), de mayor a menor.
        val order = compareByDescending<Movement> { it.bookedOn }.thenByDescending { it.id.lowercase() }
        return movements
            .filter { it.householdId == householdId && (accountId == null || it.accountId == accountId) && mine(it.id) }
            .filter { search?.matches(it) ?: true }
            .filter { after == null || order.compare(it, after) > 0 }
            .sortedWith(order)
            .take(limit)
    }

    override suspend fun movements(householdId: String, ids: List<String>): List<Movement> {
        val mine = mine(householdId)
        return movements.filter { it.householdId == householdId && it.id in ids && mine(it.id) }
    }

    override suspend fun movements(householdId: String, accountId: String, since: LocalDate, limit: Int): List<Movement> {
        val mine = mine(householdId)
        return movements
            .filter { it.householdId == householdId && it.accountId == accountId && !it.day.isBefore(since) && mine(it.id) }
            .asReversed()
            .sortedByDescending { it.bookedOn }
            .take(limit)
    }

    override suspend fun addMovement(draft: MovementDraft, householdId: String): Movement {
        val user = creator(householdId)
        val mine = mine(householdId)
        val movement = build(draft, householdId, mine)
        movements.firstOrNull { it.id == draft.id }?.let { stored ->
            // Como el servidor: un id que ya usó otra persona no se ve, así que no vale.
            if (!mine(stored.id)) idUsed()
            // Repetirlo solo vale con la misma cuenta, importe y día.
            val same = stored.householdId == householdId && stored.accountId == movement.accountId &&
                stored.amountMinor == movement.amountMinor && stored.bookedOn == movement.bookedOn
            if (!same) fail(TransferDraft.STORED_WITH_OTHER_DATA)
            return stored
        }
        movements += movement
        creators[movement.id] = user
        return movement
    }

    override suspend fun addTransfer(draft: TransferDraft, householdId: String): List<Movement> {
        val user = creator(householdId)
        val mine = mine(householdId)
        draft.issue?.let(::fail)
        transferLegs[draft.id]?.let { ids ->
            // Como el servidor: si las patas son de otra persona, ese id ya está usado.
            if (!ids.all(mine)) idUsed()
            val stored = movements.filter { it.id in ids }
            // Repetirla solo vale con las mismas cuentas, importe y día.
            val same = stored.map { it.accountId } == listOf(draft.fromAccountId, draft.toAccountId) &&
                stored.map { it.amountMinor } == listOf(-draft.amountMinor, draft.amountMinor) &&
                stored.all { it.bookedOn == draft.bookedOn.toString() }
            if (!same) fail(TransferDraft.STORED_WITH_OTHER_DATA)
            return stored
        }
        // Se validan las dos patas antes de guardar ninguna.
        val legs = draft.legs.map { build(it, householdId, mine).copy(transferId = draft.id) }
        movements += legs
        legs.forEach { creators[it.id] = user }
        transferLegs[draft.id] = legs.map { it.id }
        return legs
    }

    override suspend fun updateMovement(movement: Movement): Movement {
        movement.toDraft().issue?.let(::fail)
        val i = movements.indexOfFirst { it.id == movement.id }
        // Como el servidor: un movimiento borrado, ajeno o en otra versión que la leída no se cambia.
        if (i < 0) throw AppError.MovementChanged
        val mine = mine(movements[i].householdId)
        if (!mine(movement.id) || movements[i].updatedAt != movement.updatedAt) throw AppError.MovementChanged
        if (!mine(movement.accountId) || movement.categoryId?.let(mine) == false) throw AppError.Unknown("cuenta o categoría de otra persona")
        val transferId = movements[i].transferId
        if (transferId != null) keepTransferLegsTogether(movement, movements[i], transferId, mine)
        movements[i] = movement.copy(
            description = movement.description.trim(), payee = Payee.clean(movement.payee), updatedAt = nextVersion(), transferId = transferId,
        )
        return movements[i]
    }

    /** Como el trigger del servidor: el importe y el día de una pata cambian también en la otra. */
    private fun keepTransferLegsTogether(updated: Movement, before: Movement, transferId: String, mine: (String) -> Boolean) {
        val invalid = "Algún dato no es válido. Revisa el formulario."
        // La salida sigue siendo negativa y la entrada positiva.
        if (updated.isExpense != before.isExpense) fail(invalid)
        // Si la otra pata ya no existe, la que queda es un movimiento normal.
        val pair = movements.indexOfFirst { it.transferId == transferId && it.id != updated.id }
        if (pair < 0) return
        if (movements[pair].accountId == updated.accountId) fail(invalid)
        if (movements[pair].amountMinor == -updated.amountMinor && movements[pair].bookedOn == updated.bookedOn) return
        if (!mine(movements[pair].id)) fail(TransferDraft.OTHER_LEG_LOCKED)
        movements[pair] = movements[pair].copy(amountMinor = -updated.amountMinor, bookedOn = updated.bookedOn, updatedAt = nextVersion())
    }

    override suspend fun deleteMovement(movementId: String) {
        movements.firstOrNull { it.id == movementId }?.let { if (!mine(it.householdId)(movementId)) return }
        movements.removeAll { it.id == movementId }
        installments.removeAll { it.movementId == movementId }
    }

    override suspend fun deleteTransfer(transferId: String) {
        val legs = movements.filter { it.transferId == transferId }
        // Como el servidor: o se borran todas las patas o ninguna.
        if (legs.any { !mine(it.householdId)(it.id) }) fail(TransferDraft.OTHER_LEG_LOCKED)
        val ids = legs.map { it.id }.toSet()
        movements.removeAll { it.id in ids }
        installments.removeAll { it.movementId in ids }
    }

    override suspend fun importMovements(drafts: List<MovementDraft>, householdId: String): ImportResult {
        val user = creator(householdId)
        val mine = mine(householdId)
        var inserted = 0
        var duplicates = 0
        for (draft in drafts) {
            val movement = build(draft, householdId, mine)
            if (movement.importHash != null && movements.any { it.accountId == movement.accountId && it.importHash == movement.importHash }) {
                duplicates++
            } else {
                movements += movement
                creators[movement.id] = user
                inserted++
            }
        }
        return ImportResult(inserted, duplicates)
    }

    /** Presupuestos de cada persona, por quien los guardó: uno por persona, hogar y periodo. */
    private val budgets = mutableMapOf<String?, MutableList<Budget>>()

    private suspend fun myBudgets() = budgets.getOrPut(me()) { mutableListOf() }

    override suspend fun budget(householdId: String, startingOn: LocalDate) =
        myBudgets().firstOrNull { it.householdId == householdId && it.period.start == startingOn && isMember(householdId) }

    override suspend fun latestBudget(householdId: String, before: LocalDate) =
        myBudgets().filter { it.householdId == householdId && it.period.start < before && isMember(householdId) }
            .maxByOrNull { it.period.start }

    override suspend fun saveBudget(budget: Budget): Budget {
        creator(budget.householdId)
        budget.issue?.let(::fail)
        if (!budget.limits.keys.all(mine(budget.householdId))) throw AppError.Unknown("categoría de otra persona")
        myBudgets().removeAll { it.householdId == budget.householdId && it.period.start == budget.period.start }
        myBudgets() += budget
        return budget
    }

    /** El calendario de cobros es de cada persona. */
    private val schedules = mutableMapOf<String?, PaySchedule>()
    private val extras = mutableListOf<ExtraBudget>()

    override suspend fun paySchedule() = schedules[me()]

    override suspend fun savePaySchedule(schedule: PaySchedule): PaySchedule {
        schedule.issue?.let(::fail)
        schedules[me()] = schedule
        return schedule
    }

    override suspend fun extraBudgets(householdId: String): List<ExtraBudget> {
        val mine = mine(householdId)
        return extras.filter { it.householdId == householdId && mine(it.id) }
            .sortedWith(compareBy<ExtraBudget> { !it.isFavorite }.thenByDescending { it.startsOn })
    }

    override suspend fun saveExtraBudget(budget: ExtraBudget): ExtraBudget {
        val user = creator(budget.householdId)
        val mine = mine(budget.householdId)
        budget.issue?.let(::fail)
        val stored = extras.firstOrNull { it.id == budget.id }
        if (budget.updatedAt == null) {
            // Alta: repetirla solo vale con el mismo hogar, nombre, límite y primer día.
            replayed(stored, budget.id, mine) {
                it.householdId == budget.householdId && it.name == budget.trimmedName && it.limit == budget.limit && it.startsOn == budget.startsOn
            }?.let { return it }
        } else if (stored == null || !mine(budget.id) || stored.updatedAt != budget.updatedAt) {
            // Cambio: solo de uno propio y sobre la versión leída (el STM05 del servidor).
            throw AppError.MovementChanged
        }
        val saved = budget.copy(name = budget.trimmedName, updatedAt = nextVersion())
        // Un favorito por persona, como el disparador del servidor. El que deja de serlo cambia de versión.
        if (saved.isFavorite) {
            extras.replaceAll { if (it.isFavorite && mine(it.id) && it.id != saved.id) it.copy(isFavorite = false, updatedAt = nextVersion()) else it }
        }
        val index = extras.indexOfFirst { it.id == saved.id }
        if (index >= 0) extras[index] = saved else extras += saved
        creators[saved.id] = user
        return saved
    }

    override suspend fun deleteExtraBudget(id: String) {
        val budget = extras.firstOrNull { it.id == id } ?: return
        if (mine(budget.householdId)(id)) extras.removeAll { it.id == id }
    }

    override suspend fun movements(householdId: String, from: LocalDate, through: LocalDate): List<Movement> {
        val mine = mine(householdId)
        return movements.filter { it.householdId == householdId && it.day in from..through && mine(it.id) }
    }

    private val series = mutableListOf<RecurringSeries>()
    private val goals = mutableListOf<Goal>()
    private val contributions = mutableListOf<GoalContribution>()

    /** Como el RLS: la cuenta y la categoría que se enlazan tienen que ser propias. */
    private fun checkReferences(mine: (String) -> Boolean, accountId: String?, categoryId: String? = null) {
        if (accountId?.let(mine) == false) throw AppError.Unknown("cuenta de otra persona")
        if (categoryId?.let(mine) == false) throw AppError.Unknown("categoría de otra persona")
    }

    override suspend fun recurringSeries(householdId: String): List<RecurringSeries> {
        val mine = mine(householdId)
        return series.filter { it.householdId == householdId && mine(it.id) }.sortedBy { it.name }
    }

    override suspend fun createRecurring(series: RecurringSeries): RecurringSeries {
        val user = creator(series.householdId)
        series.issue?.let(::fail)
        checkReferences(mine(series.householdId), series.accountId, series.categoryId)
        // Repetir el alta solo vale con el mismo hogar, nombre, tipo, importe y primer día.
        replayed(this.series.firstOrNull { it.id == series.id }, series.id, mine(series.householdId)) {
            it.householdId == series.householdId && it.name == series.trimmedName && it.kind == series.kind &&
                it.amountMinor == series.amountMinor && it.startsOn == series.startsOn
        }?.let { return it }
        return series.copy(id = series.id.ifEmpty(::id), name = series.trimmedName, updatedAt = nextVersion()).also {
            this.series += it
            creators[it.id] = user
        }
    }

    override suspend fun updateRecurring(series: RecurringSeries): RecurringSeries {
        series.issue?.let(::fail)
        val stored = requireCurrent(this.series.firstOrNull { it.id == series.id }, series.id, { it.householdId }, { it.updatedAt }, series.updatedAt)
        checkReferences(mine(stored.householdId), series.accountId, series.categoryId)
        val saved = series.copy(name = series.trimmedName, updatedAt = nextVersion())
        this.series.replaceAll { if (it.id == series.id) saved else it }
        return saved
    }

    override suspend fun deleteRecurring(seriesId: String) {
        series.firstOrNull { it.id == seriesId }?.let { if (!mine(it.householdId)(seriesId)) return }
        series.removeAll { it.id == seriesId }
        charges.removeAll { it.seriesId == seriesId }
    }

    private val charges = mutableListOf<RecurringCharge>()

    override suspend fun recurringCharges(householdId: String): List<RecurringCharge> {
        val mine = mine(householdId)
        return charges.filter { it.householdId == householdId && mine(it.id) }.sortedByDescending { it.dueOn }
    }

    override suspend fun createCharges(charges: List<RecurringCharge>): List<RecurringCharge> {
        val users = charges.map { it.householdId }.distinct().associateWith { creator(it) }
        // Como el servidor: solo se crean cargos de series propias.
        for ((householdId, items) in charges.groupBy { it.householdId }) {
            val mine = mine(householdId)
            if (items.any { !mine(it.seriesId) }) throw AppError.Unknown("serie de otra persona")
        }
        return charges.distinctBy { it.seriesId to it.dueOn }
            .filter { new -> this.charges.none { it.seriesId == new.seriesId && it.dueOn == new.dueOn } }
            .map { it.copy(id = id(), status = ChargeStatus.Pending, transactionId = null, updatedAt = nextVersion()) }
            .onEach { creators[it.id] = users.getValue(it.householdId) }
            .also { this.charges += it }
    }

    override suspend fun confirmCharge(chargeId: String, draft: MovementDraft): Movement {
        val i = charges.indexOfFirst { it.id == chargeId }
        // Como el servidor: un cargo ajeno no se ve.
        if (i < 0 || !mine(charges[i].householdId)(chargeId)) fail("El cargo no existe.")
        if (!charges[i].isPending) fail("El cargo ya no está pendiente.")
        val householdId = charges[i].householdId
        val user = creator(householdId)
        val movement = build(draft, householdId, mine(householdId)).also {
            movements += it
            creators[it.id] = user
        }
        // Como el servidor: confirmarlo cambia la fila, y con ella su versión.
        charges[i] = charges[i].copy(
            status = ChargeStatus.Confirmed, transactionId = movement.id, amountMinor = movement.amountMinor, updatedAt = nextVersion(),
        )
        return movement
    }

    override suspend fun updateCharge(charge: RecurringCharge, status: ChargeStatus, transactionId: String?): RecurringCharge {
        val stored = requireCurrent(charges.firstOrNull { it.id == charge.id }, charge.id, { it.householdId }, { it.updatedAt }, charge.updatedAt)
        val saved = stored.copy(status = status, transactionId = if (status == ChargeStatus.Pending) null else transactionId, updatedAt = nextVersion())
        charges.replaceAll { if (it.id == saved.id) saved else it }
        return saved
    }

    override suspend fun goals(householdId: String): List<Goal> {
        val mine = mine(householdId)
        return goals.filter { it.householdId == householdId && mine(it.id) }
    }

    override suspend fun createGoal(goal: Goal): Goal {
        val user = creator(goal.householdId)
        goal.issue?.let(::fail)
        checkReferences(mine(goal.householdId), goal.accountId)
        // Repetir el alta solo vale con el mismo hogar, nombre, tipo y objetivo.
        replayed(goals.firstOrNull { it.id == goal.id }, goal.id, mine(goal.householdId)) {
            it.householdId == goal.householdId && it.name == goal.trimmedName && it.kind == goal.kind && it.targetMinor == goal.targetMinor
        }?.let { return it }
        return goal.copy(id = goal.id.ifEmpty(::id), name = goal.trimmedName, updatedAt = nextVersion()).also {
            goals += it
            creators[it.id] = user
        }
    }

    override suspend fun updateGoal(goal: Goal): Goal {
        goal.issue?.let(::fail)
        val stored = requireCurrent(goals.firstOrNull { it.id == goal.id }, goal.id, { it.householdId }, { it.updatedAt }, goal.updatedAt)
        checkReferences(mine(stored.householdId), goal.accountId)
        val saved = goal.copy(name = goal.trimmedName, updatedAt = nextVersion())
        goals.replaceAll { if (it.id == goal.id) saved else it }
        return saved
    }

    override suspend fun deleteGoal(goalId: String) {
        goals.firstOrNull { it.id == goalId }?.let { if (!mine(it.householdId)(goalId)) return }
        goals.removeAll { it.id == goalId }
        contributions.removeAll { it.goalId == goalId }
    }

    override suspend fun contributions(householdId: String): List<GoalContribution> {
        val mine = mine(householdId)
        return contributions.filter { it.householdId == householdId && mine(it.id) }.sortedByDescending { it.madeOn }
    }

    override suspend fun addContribution(contribution: GoalContribution): GoalContribution {
        val user = creator(contribution.householdId)
        contribution.issue?.let(::fail)
        if (!mine(contribution.householdId)(contribution.goalId)) throw AppError.Unknown("meta de otra persona")
        // Repetir la aportación solo vale con la misma meta, importe y día.
        replayed(contributions.firstOrNull { it.id == contribution.id }, contribution.id, mine(contribution.householdId)) {
            it.goalId == contribution.goalId && it.amountMinor == contribution.amountMinor && it.madeOn == contribution.madeOn
        }?.let { return it }
        return contribution.copy(id = contribution.id.ifEmpty(::id)).also {
            contributions += it
            creators[it.id] = user
        }
    }

    override suspend fun deleteContribution(contributionId: String) {
        val item = contributions.firstOrNull { it.id == contributionId } ?: return
        if (mine(item.householdId)(contributionId)) contributions.removeAll { it.id == contributionId }
    }

    /** Las condiciones de una tarjeta son de quien creó su cuenta (solo se guardan sobre una cuenta propia). */
    private val cards = mutableListOf<CreditCardTerms>()
    private val installments = mutableListOf<CardInstallment>()

    override suspend fun creditCards(householdId: String): List<CreditCardTerms> {
        val mine = mine(householdId)
        return cards.filter { it.householdId == householdId && mine(it.accountId) }
    }

    override suspend fun saveCreditCard(terms: CreditCardTerms): CreditCardTerms {
        creator(terms.householdId)
        val mine = mine(terms.householdId)
        terms.issue?.let(::fail)
        val stored = cards.firstOrNull { it.accountId == terms.accountId }
        // Cambio: solo de unas condiciones propias y sobre la versión leída (el STM05 del servidor).
        if (terms.updatedAt != null && (!mine(terms.accountId) || stored?.updatedAt != terms.updatedAt)) throw AppError.MovementChanged
        if (accounts.none { it.id == terms.accountId && it.kind == AccountKind.CreditCard } || !mine(terms.accountId)) {
            fail("Esa cuenta no es una tarjeta de crédito.")
        }
        checkReferences(mine, terms.payFromAccountId)
        if (terms.updatedAt == null) {
            // Alta: repetirla solo vale con el mismo límite, días y forma de pago.
            replayed(stored, terms.accountId, mine) {
                it.householdId == terms.householdId && it.creditLimit == terms.creditLimit && it.statementDay == terms.statementDay &&
                    it.paymentDay == terms.paymentDay && it.paymentMode == terms.paymentMode
            }?.let { return it }
        }
        val saved = terms.copy(updatedAt = nextVersion())
        cards.removeAll { it.accountId == terms.accountId }
        cards += saved
        return saved
    }

    override suspend fun cardInstallments(householdId: String): List<CardInstallment> {
        val mine = mine(householdId)
        return installments.filter { it.householdId == householdId && mine(it.id) }
    }

    override suspend fun saveInstallment(installment: CardInstallment): CardInstallment {
        val user = creator(installment.householdId)
        val mine = mine(installment.householdId)
        installment.issue?.let(::fail)
        if (installment.updatedAt != null) {
            // Cambio: solo plazo e interés, de un aplazado propio y sobre la versión leída (el STM05 del servidor).
            val stored = requireCurrent(installments.firstOrNull { it.id == installment.id }, installment.id, { it.householdId }, { it.updatedAt }, installment.updatedAt)
            val saved = stored.copy(months = installment.months, rate = installment.rate, updatedAt = nextVersion())
            installments.replaceAll { if (it.id == saved.id) saved else it }
            return saved
        }
        if (movements.none { it.id == installment.movementId && it.accountId == installment.accountId } || !mine(installment.accountId)) {
            fail("Solo se aplazan compras de la tarjeta.")
        }
        // Alta: repetirla solo vale con la misma compra, plazo e interés.
        replayed(installments.firstOrNull { it.id == installment.id }, installment.id, mine) {
            it.movementId == installment.movementId && it.months == installment.months && it.rate == installment.rate
        }?.let { return it }
        // Como el índice único del servidor: un aplazado por compra.
        if (installments.any { it.movementId == installment.movementId }) idUsed()
        return installment.copy(id = installment.id.ifEmpty(::id), updatedAt = nextVersion()).also {
            installments += it
            creators[it.id] = user
        }
    }

    override suspend fun deleteInstallment(installmentId: String) {
        val item = installments.firstOrNull { it.id == installmentId } ?: return
        if (mine(item.householdId)(installmentId)) installments.removeAll { it.id == installmentId }
    }

    private val holdings = mutableListOf<Holding>()
    private val prices = mutableListOf<HoldingPrice>()
    private val trades = mutableListOf<InvestmentTrade>()

    /** El movimiento que apuntó cada operación guardada con cuenta, por el id de la operación. */
    private val tradeMovements = mutableMapOf<String, String>()
    private val plans = mutableListOf<InvestmentPlan>()

    override suspend fun holdings(householdId: String): List<Holding> {
        val mine = mine(householdId)
        return holdings.filter { it.householdId == householdId && mine(it.id) }.sortedBy { it.trimmedName }
    }

    override suspend fun createHolding(holding: Holding): Holding {
        val user = creator(holding.householdId)
        holding.issue?.let(::fail)
        checkReferences(mine(holding.householdId), holding.accountId)
        // Repetir el alta solo vale con el mismo hogar, nombre y tipo.
        replayed(holdings.firstOrNull { it.id == holding.id }, holding.id, mine(holding.householdId)) {
            it.householdId == holding.householdId && it.name == holding.trimmedName && it.kind == holding.kind
        }?.let { return it }
        return holding.copy(id = holding.id.ifEmpty(::id), name = holding.trimmedName, symbol = holding.trimmedSymbol, updatedAt = nextVersion()).also {
            holdings += it
            creators[it.id] = user
        }
    }

    override suspend fun updateHolding(holding: Holding): Holding {
        holding.issue?.let(::fail)
        val stored = requireCurrent(holdings.firstOrNull { it.id == holding.id }, holding.id, { it.householdId }, { it.updatedAt }, holding.updatedAt)
        checkReferences(mine(stored.householdId), holding.accountId)
        val saved = holding.copy(name = holding.trimmedName, symbol = holding.trimmedSymbol, updatedAt = nextVersion())
        holdings.replaceAll { if (it.id == saved.id) saved else it }
        return saved
    }

    override suspend fun deleteHolding(holdingId: String) {
        holdings.firstOrNull { it.id == holdingId }?.let { if (!mine(it.householdId)(holdingId)) return }
        holdings.removeAll { it.id == holdingId }
        prices.removeAll { it.holdingId == holdingId }
        trades.removeAll { it.holdingId == holdingId }
        plans.removeAll { it.holdingId == holdingId }
    }

    override suspend fun holdingPrices(householdId: String): List<HoldingPrice> {
        val mine = mine(householdId)
        return prices.filter { it.householdId == householdId && mine(it.id) }.sortedBy { it.pricedOn }
    }

    override suspend fun recordPrice(price: java.math.BigDecimal, day: LocalDate, holdingId: String): Holding {
        if (price.signum() < 0) fail("El precio no puede ser negativo.")
        val index = holdings.indexOfFirst { it.id == holdingId }
        // Como el servidor: un activo ajeno no se ve.
        if (index < 0 || !mine(holdings[index].householdId)(holdingId)) throw AppError.Unknown("no existe")
        val holding = holdings[index]
        prices.removeAll { it.holdingId == holdingId && it.day == day }
        prices += HoldingPrice(id(), holding.householdId, holdingId, day.toString(), price).also { creators[it.id] = me() }
        if (holding.priceDay?.isAfter(day) == true) return holding
        // Como el servidor: cambiar el precio del activo cambia su versión.
        return holding.copy(price = price, priceOn = day.toString(), updatedAt = nextVersion()).also { holdings[index] = it }
    }

    override suspend fun trades(householdId: String): List<InvestmentTrade> {
        val mine = mine(householdId)
        return trades.filter { it.householdId == householdId && mine(it.id) }.sortedBy { it.tradedOn }
    }

    override suspend fun addTrade(trade: InvestmentTrade, cash: TradeCash?): InvestmentTrade {
        val user = creator(trade.householdId)
        val mine = mine(trade.householdId)
        if (!mine(trade.holdingId)) throw AppError.Unknown("activo de otra persona")
        trades.firstOrNull { trade.id.isNotEmpty() && it.id == trade.id }?.let { stored ->
            // Como el servidor: una operación ajena no se ve, así que ese id ya está usado.
            if (!mine(stored.id)) idUsed()
            // Repetirla solo vale con los mismos datos, también los del movimiento.
            val movement = movements.firstOrNull { it.id == tradeMovements[trade.id] }
            val same = stored.holdingId == trade.holdingId && stored.tradedOn == trade.tradedOn && stored.side == trade.side &&
                stored.quantity.compareTo(trade.quantity) == 0 && stored.price.compareTo(trade.price) == 0 &&
                stored.feeMinor == trade.feeMinor && movement?.accountId == cash?.accountId && movement?.amountMinor == cash?.amountMinor
            if (!same) fail(TransferDraft.STORED_WITH_OTHER_DATA)
            return stored
        }
        trade.issue(trades)?.let(::fail)
        val saved = trade.copy(id = trade.id.ifEmpty { id() })
        // El movimiento se valida antes de guardar nada: o quedan los dos o ninguno.
        cash?.let {
            val movement = build(MovementDraft(it.accountId, it.categoryId, trade.day, it.amountMinor, it.description), trade.householdId, mine)
            movements += movement
            creators[movement.id] = user
            tradeMovements[saved.id] = movement.id
        }
        trades += saved
        creators[saved.id] = user
        return saved
    }

    override suspend fun deleteTrade(tradeId: String) {
        val trade = trades.firstOrNull { it.id == tradeId }
        if (trade != null && !mine(trade.householdId)(tradeId)) return
        trade?.deletionIssue(trades)?.let(::fail)
        trades.removeAll { it.id == tradeId }
    }

    override suspend fun investmentPlans(householdId: String): List<InvestmentPlan> {
        val mine = mine(householdId)
        return plans.filter { it.householdId == householdId && mine(it.id) }.sortedBy { it.startsOn }
    }

    override suspend fun createPlan(plan: InvestmentPlan): InvestmentPlan {
        val user = creator(plan.householdId)
        val mine = mine(plan.householdId)
        plan.issue?.let(::fail)
        if (!mine(plan.holdingId)) throw AppError.Unknown("activo de otra persona")
        checkReferences(mine, plan.accountId)
        // Repetir el alta solo vale con el mismo activo, importe y primer día.
        replayed(plans.firstOrNull { it.id == plan.id }, plan.id, mine) {
            it.holdingId == plan.holdingId && it.amountMinor == plan.amountMinor && it.startsOn == plan.startsOn
        }?.let { return it }
        return plan.copy(id = plan.id.ifEmpty(::id), updatedAt = nextVersion()).also {
            plans += it
            creators[it.id] = user
        }
    }

    override suspend fun updatePlan(plan: InvestmentPlan): InvestmentPlan {
        plan.issue?.let(::fail)
        val stored = requireCurrent(plans.firstOrNull { it.id == plan.id }, plan.id, { it.householdId }, { it.updatedAt }, plan.updatedAt)
        checkReferences(mine(stored.householdId), plan.accountId)
        val saved = plan.copy(updatedAt = nextVersion())
        plans.replaceAll { if (it.id == saved.id) saved else it }
        return saved
    }

    override suspend fun deletePlan(planId: String) {
        val plan = plans.firstOrNull { it.id == planId } ?: return
        if (mine(plan.householdId)(planId)) plans.removeAll { it.id == planId }
    }

    /** Los scores son de cada persona, como con el RLS del servidor. */
    private val scores = mutableListOf<CreditScore>()

    override suspend fun creditScores(): List<CreditScore> {
        val user = me()
        return scores.filter { creators[it.id] == user }.sortedByDescending { it.recordedOn }
    }

    override suspend fun addCreditScore(score: CreditScore): CreditScore {
        score.issue?.let(::fail)
        return score.copy(id = id()).also {
            scores += it
            creators[it.id] = me()
        }
    }

    override suspend fun deleteCreditScore(scoreId: String) {
        val user = me()
        scores.removeAll { it.id == scoreId && creators[it.id] == user }
    }
}
