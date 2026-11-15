import Foundation

/// Errores que la app enseña al usuario, ya en español.
public enum AppError: Error, Equatable, LocalizedError, Sendable {
    case invalidCredentials
    case usernameTaken
    case weakPassword
    case notSignedIn
    case invalidOrExpiredInvite
    case alreadyMember
    case network
    case invalidInput(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Usuario o contraseña incorrectos."
        case .usernameTaken: "Ese nombre de usuario ya existe. Prueba con otro."
        case .weakPassword: "La contraseña es demasiado débil. Usa al menos \(SignUpForm.minimumPasswordLength) caracteres."
        case .notSignedIn: "Tu sesión ha caducado. Vuelve a iniciar sesión."
        case .invalidOrExpiredInvite: "Ese código no es válido o ha caducado. Pide uno nuevo."
        case .alreadyMember: "Ya formas parte de ese hogar."
        case .network: "No hay conexión. Inténtalo de nuevo en un momento."
        case .invalidInput(let message): message
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
    /// Todos los movimientos del hogar, para exportarlos. El servidor los da por páginas.
    func allMovements(in householdId: UUID) async throws -> [Movement]
    func addMovement(_ draft: MovementDraft, in householdId: UUID) async throws -> Movement
    func updateMovement(_ movement: Movement) async throws -> Movement
    func deleteMovement(_ movementId: UUID) async throws
    /// Guarda los movimientos de un CSV. Los que ya estaban (misma huella) se ignoran.
    func importMovements(_ drafts: [MovementDraft], in householdId: UUID) async throws -> ImportResult
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
    func addTrade(_ trade: InvestmentTrade) async throws -> InvestmentTrade
    func deleteTrade(_ tradeId: UUID) async throws

    func investmentPlans(in householdId: UUID) async throws -> [InvestmentPlan]
    func createPlan(_ plan: InvestmentPlan) async throws -> InvestmentPlan
    func updatePlan(_ plan: InvestmentPlan) async throws -> InvestmentPlan
    func deletePlan(_ planId: UUID) async throws
}
