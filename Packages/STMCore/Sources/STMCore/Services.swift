import Foundation

/// Errores que la app enseña al usuario, ya en español.
public enum AppError: Error, Equatable, LocalizedError, Sendable {
    case invalidCredentials
    case usernameTaken
    case weakPassword
    case notSignedIn
    case invalidOrExpiredInvite
    /// Demasiados códigos fallidos seguidos: el servidor no deja probar más hasta que pasen estos minutos.
    case tooManyInviteAttempts(minutes: Int)
    case alreadyMember
    case network
    case invalidInput(String)
    /// El movimiento que se quería cambiar ya no es el que se leyó: otro dispositivo lo cambió o lo borró antes.
    case movementChanged
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Usuario o contraseña incorrectos."
        case .usernameTaken: "Ese nombre de usuario ya existe. Prueba con otro."
        case .weakPassword: "La contraseña es demasiado débil. Usa al menos \(SignUpForm.minimumPasswordLength) caracteres."
        case .notSignedIn: "Tu sesión ha caducado. Vuelve a iniciar sesión."
        case .invalidOrExpiredInvite: "Ese código no es válido o ha caducado. Pide uno nuevo."
        case .tooManyInviteAttempts(let minutes):
            "Has probado demasiados códigos. Vuelve a intentarlo dentro de \(minutes == 1 ? "1 minuto" : "\(minutes) minutos")."
        case .alreadyMember: "Ya formas parte de ese hogar."
        case .network: "No hay conexión. Inténtalo de nuevo en un momento."
        case .invalidInput(let message): message
        case .movementChanged:
            "Este movimiento ha cambiado en otro dispositivo y se ha vuelto a cargar. Ciérralo, revísalo y repite el cambio si hace falta."
        case .unknown: "Algo ha fallado. Inténtalo de nuevo."
        }
    }
}

/// Registro e inicio de sesión.
public protocol AuthService: Sendable {
    /// Usuario con sesión abierta, si la hay (la sesión vive en el Llavero).
    func currentUserId() async -> UUID?
    func signUp(username: Username, password: String, displayName: String?) async throws -> UUID
    func signIn(username: Username, password: String) async throws -> UUID
    func signOut() async throws
}

/// Perfil, hogares, miembros e invitaciones.
public protocol HouseholdService: Sendable {
    func myProfile() async throws -> Profile
    func updateProfile(displayName: String?, theme: AppTheme) async throws -> Profile
    func households() async throws -> [Household]
    func createHousehold(name: String) async throws -> Household
    func members(of householdId: UUID) async throws -> [HouseholdMember]
    func pendingInvites(for householdId: UUID) async throws -> [HouseholdInvite]
    func createInvite(for householdId: UUID) async throws -> HouseholdInvite
    func revokeInvite(_ inviteId: UUID) async throws
    func acceptInvite(_ code: InviteCode) async throws -> Household
    func leave(householdId: UUID) async throws
    /// Solo el dueño del hogar: saca a otro miembro.
    func removeMember(_ userId: UUID, from householdId: UUID) async throws
    /// Cambia el nombre del hogar. Sólo puede quien lo creó.
    func renameHousehold(_ householdId: UUID, to name: String) async throws -> Household
}

/// Cuentas, categorías y movimientos de un hogar.
public protocol FinanceService: Sendable {
    func accounts(in householdId: UUID) async throws -> [Account]
    /// Saldo actual de cada cuenta: el inicial más todos sus movimientos.
    func balances(in householdId: UUID) async throws -> [UUID: Money]
    func createAccount(_ draft: AccountDraft, in householdId: UUID) async throws -> Account
    func updateAccount(_ account: Account) async throws -> Account
    func deleteAccount(_ accountId: UUID) async throws

    func categories(in householdId: UUID) async throws -> [BudgetCategory]
    func createCategory(_ category: BudgetCategory) async throws -> BudgetCategory
    /// Cambia nombre, grupo e icono; el tipo de una categoría no se cambia.
    func updateCategory(_ category: BudgetCategory) async throws -> BudgetCategory
    /// Los movimientos de esa categoría se quedan sin categoría; sus límites de presupuesto se borran.
    func deleteCategory(_ categoryId: UUID) async throws

    /// Borra todo lo apuntado en el hogar (cuentas, movimientos, categorías, presupuestos,
    /// pagos fijos y metas) y deja las categorías de partida. Miembros e invitaciones no se tocan.
    func resetHousehold(_ householdId: UUID) async throws

    /// Movimientos más recientes primero. Con `accountId`, sólo los de esa cuenta.
    func movements(in householdId: UUID, accountId: UUID?, limit: Int) async throws -> [Movement]
    /// Movimientos por id, sean o no de los más recientes. Los que ya no existen no vienen.
    func movements(in householdId: UUID, ids: [UUID]) async throws -> [Movement]
    /// Movimientos de la cuenta desde ese día (incluido), más recientes primero, como mucho `limit`.
    func movements(in householdId: UUID, accountId: UUID, since: CalendarDay, limit: Int) async throws -> [Movement]
    /// Todos los movimientos del hogar, para exportarlos. El servidor los da por páginas.
    func allMovements(in householdId: UUID) async throws -> [Movement]
    /// Repetir la llamada con el mismo `draft.id` devuelve el movimiento ya guardado y no apunta nada nuevo; si se
    /// repite con otra cuenta, otro importe u otro día falla con `TransferDraft.storedWithOtherData`.
    func addMovement(_ draft: MovementDraft, in householdId: UUID) async throws -> Movement
    /// Guarda las dos patas de una transferencia (primero la salida), o ninguna si algo falla.
    /// Repetir la llamada con el mismo `id` devuelve las ya guardadas y no apunta nada nuevo; si se repite
    /// con otra cuenta, otro importe u otro día falla con `TransferDraft.storedWithOtherData`.
    func addTransfer(_ transfer: TransferDraft, in householdId: UUID) async throws -> [Movement]
    /// Solo cambia el movimiento si sigue en la versión leída (`movement.updatedAt`). Si otro dispositivo lo cambió
    /// o lo borró antes, no guarda nada y falla con `AppError.movementChanged`. Devuelve la versión nueva.
    /// En una pata de transferencia, el importe y el día cambian también en la otra pata (en el servidor, en la
    /// misma transacción); la salida tiene que seguir siendo negativa y la entrada positiva.
    func updateMovement(_ movement: Movement) async throws -> Movement
    func deleteMovement(_ movementId: UUID) async throws
    /// Borra las dos patas de una transferencia (`Movement.transferId`) en una sola llamada, o ninguna.
    /// Si la otra pata ya no existe borra la que queda; si ya no queda ninguna no hace nada.
    func deleteTransfer(_ transferId: UUID) async throws
    /// Guarda los movimientos de un CSV. Los que ya estaban (misma huella) se ignoran.
    func importMovements(_ drafts: [MovementDraft], in householdId: UUID) async throws -> ImportResult
}

/// Una transferencia entre dos cuentas, antes de guardarla: sale `amount` de una y entra en la otra.
/// Por ejemplo el pago de una tarjeta. `id` lo genera la app una vez por formulario, para que
/// reintentar tras un fallo de red no apunte el dinero dos veces.
public struct TransferDraft: Hashable, Sendable {
    public var id: UUID
    public var fromAccountId: UUID
    public var toAccountId: UUID
    public var categoryId: UUID?
    public var bookedOn: CalendarDay
    /// Lo que se mueve, siempre positivo.
    public var amount: Money
    public var fromDescription: String
    public var toDescription: String

    public init(id: UUID = UUID(), fromAccountId: UUID, toAccountId: UUID, categoryId: UUID? = nil,
                bookedOn: CalendarDay, amount: Money, fromDescription: String, toDescription: String) {
        self.id = id
        self.fromAccountId = fromAccountId
        self.toAccountId = toAccountId
        self.categoryId = categoryId
        self.bookedOn = bookedOn
        self.amount = amount
        self.fromDescription = fromDescription
        self.toDescription = toDescription
    }

    /// Lo que ve quien repite una transferencia ya guardada después de cambiar cuenta, importe o día.
    public static let storedWithOtherData = "Este pago ya se guardó con otros datos. Revísalo en los movimientos."
    /// Lo que ve quien cambia o borra una pata cuando la otra no se puede cambiar con ella.
    public static let otherLegLocked = "No se puede cambiar la otra parte de la transferencia. Recarga e inténtalo de nuevo."
    /// Lo que se avisa antes de borrar una pata: se borran las dos.
    public static let deleteWarning = "Se borran los dos movimientos, la salida de una cuenta y la entrada en la otra. No se puede deshacer."
    /// Lo que se avisa al editar una pata.
    public static let editNote = "Es una transferencia: el importe y la fecha cambian también en el movimiento de la otra cuenta."

    /// Las dos patas: la salida de una cuenta y la entrada en la otra.
    public var legs: [MovementDraft] {
        [MovementDraft(accountId: fromAccountId, categoryId: categoryId, bookedOn: bookedOn, amount: -amount,
                       description: fromDescription),
         MovementDraft(accountId: toAccountId, categoryId: categoryId, bookedOn: bookedOn, amount: amount,
                       description: toDescription)]
    }

    /// Problema que impide guardarla, en español, o nil si es válida.
    public var issue: String? {
        if fromAccountId == toAccountId { return "Elige dos cuentas distintas." }
        if amount.minor <= 0 { return "El importe tiene que ser mayor que cero." }
        return legs.lazy.compactMap(\.issue).first
    }
}

/// Presupuesto mensual y los movimientos de un periodo para calcularlo.
public protocol BudgetService: Sendable {
    /// El presupuesto propio que empieza ese día, o nil si aún no se ha hecho.
    func budget(startingOn day: CalendarDay, in householdId: UUID) async throws -> Budget?
    /// El último presupuesto propio que empieza antes de ese día, para proponerlo como punto de partida.
    func latestBudget(before day: CalendarDay, in householdId: UUID) async throws -> Budget?
    func saveBudget(_ budget: Budget) async throws -> Budget
    /// Cuándo cobra quien ha entrado (nil si aún no lo ha dicho). Es privado de cada persona.
    func paySchedule() async throws -> PaySchedule?
    func savePaySchedule(_ schedule: PaySchedule) async throws -> PaySchedule
    /// Presupuestos extra propios del hogar.
    func extraBudgets(in householdId: UUID) async throws -> [ExtraBudget]
    func saveExtraBudget(_ budget: ExtraBudget) async throws -> ExtraBudget
    func deleteExtraBudget(_ id: UUID) async throws
    /// Todos los movimientos del hogar entre dos días, ambos incluidos.
    func movements(in householdId: UUID, from: CalendarDay, through: CalendarDay) async throws -> [Movement]
}

extension BudgetService {
    /// El presupuesto del mes natural (compatibilidad con lo de antes de los periodos).
    public func budget(for month: MonthKey, in householdId: UUID) async throws -> Budget? {
        try await budget(startingOn: month.firstDay, in: householdId)
    }

    public func latestBudget(before month: MonthKey, in householdId: UUID) async throws -> Budget? {
        try await latestBudget(before: month.firstDay, in: householdId)
    }
}

/// Pagos recurrentes del hogar: suscripciones, gastos esenciales e ingresos fijos.
public protocol RecurringService: Sendable {
    func recurringSeries(in householdId: UUID) async throws -> [RecurringSeries]
    func createRecurring(_ series: RecurringSeries) async throws -> RecurringSeries
    func updateRecurring(_ series: RecurringSeries) async throws -> RecurringSeries
    func deleteRecurring(_ seriesId: UUID) async throws

    /// Cargos propios de los pagos fijos (pendientes, confirmados y saltados).
    func recurringCharges(in householdId: UUID) async throws -> [RecurringCharge]
    /// Apunta cargos pendientes; los que ya existen (misma serie y día) se ignoran.
    func createCharges(_ charges: [RecurringCharge]) async throws -> [RecurringCharge]
    /// Crea el movimiento del cargo y lo marca como confirmado. Devuelve el movimiento.
    func confirmCharge(_ chargeId: UUID, with draft: MovementDraft) async throws -> Movement
    /// Enlaza el cargo con un movimiento que ya existe (confirmado) o lo salta.
    func updateCharge(_ chargeId: UUID, status: ChargeStatus, transactionId: UUID?) async throws
    func deleteCharge(_ chargeId: UUID) async throws
}

/// Metas de ahorro y de deudas, con sus aportaciones.
public protocol GoalService: Sendable {
    func goals(in householdId: UUID) async throws -> [Goal]
    func createGoal(_ goal: Goal) async throws -> Goal
    func updateGoal(_ goal: Goal) async throws -> Goal
    func deleteGoal(_ goalId: UUID) async throws
    /// Todas las aportaciones a las metas del hogar, las más recientes primero.
    func contributions(in householdId: UUID) async throws -> [GoalContribution]
    func addContribution(_ contribution: GoalContribution) async throws -> GoalContribution
    func deleteContribution(_ contributionId: UUID) async throws
}

public extension InvestmentService {
    /// Solo la operación, sin movimiento en ninguna cuenta.
    func addTrade(_ trade: InvestmentTrade) async throws -> InvestmentTrade {
        try await addTrade(trade, cash: nil)
    }
}

/// El movimiento en la cuenta que acompaña a una compra o venta; se guarda el mismo día que la operación.
public struct TradeCash: Hashable, Sendable {
    public var accountId: UUID
    public var categoryId: UUID?
    /// Lo que entra en la cuenta (venta) o sale (compra, en negativo).
    public var amount: Money
    public var description: String

    public init(accountId: UUID, categoryId: UUID? = nil, amount: Money, description: String) {
        self.accountId = accountId
        self.categoryId = categoryId
        self.amount = amount
        self.description = description
    }
}

/// Score crediticio de quien tiene la sesión abierta. No se comparte con el hogar.
public protocol CreditScoreService: Sendable {
    /// Los más recientes primero.
    func creditScores() async throws -> [CreditScore]
    func addCreditScore(_ score: CreditScore) async throws -> CreditScore
    func deleteCreditScore(_ scoreId: UUID) async throws
}

/// Inversiones del hogar. Los precios se apuntan a mano; no hay cotizaciones de terceros.
public protocol InvestmentService: Sendable {
    func holdings(in householdId: UUID) async throws -> [Holding]
    func createHolding(_ holding: Holding) async throws -> Holding
    func updateHolding(_ holding: Holding) async throws -> Holding
    /// Borra el activo con sus precios, operaciones y planes.
    func deleteHolding(_ holdingId: UUID) async throws

    /// Precios apuntados de todos los activos del hogar, por fecha.
    func holdingPrices(in householdId: UUID) async throws -> [HoldingPrice]
    /// Apunta el precio de un día (sustituye el de ese día si ya había) y, si es el
    /// más reciente, lo pone como precio actual del activo.
    func recordPrice(_ price: Decimal, on day: CalendarDay, for holdingId: UUID) async throws -> Holding

    /// Compras y ventas de todos los activos del hogar, por fecha.
    func trades(in householdId: UUID) async throws -> [InvestmentTrade]
    /// Guarda una compra o venta y, con `cash`, su movimiento en la cuenta: los dos o ninguno.
    /// Repetir la llamada con el mismo `trade.id` devuelve la operación ya guardada y no apunta nada nuevo;
    /// con otros datos falla con `TransferDraft.storedWithOtherData`. Una venta que deje la posición
    /// en negativo en cualquier fecha falla con `InvestmentTrade.notEnoughShares`.
    func addTrade(_ trade: InvestmentTrade, cash: TradeCash?) async throws -> InvestmentTrade
    /// Borrar una compra de la que depende una venta posterior falla con `InvestmentTrade.neededByLaterSale`.
    func deleteTrade(_ tradeId: UUID) async throws

    func investmentPlans(in householdId: UUID) async throws -> [InvestmentPlan]
    func createPlan(_ plan: InvestmentPlan) async throws -> InvestmentPlan
    func updatePlan(_ plan: InvestmentPlan) async throws -> InvestmentPlan
    func deletePlan(_ planId: UUID) async throws
}
