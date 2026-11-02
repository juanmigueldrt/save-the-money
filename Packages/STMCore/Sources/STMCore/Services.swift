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
    /// El presupuesto de ese mes, o nil si aún no se ha hecho.
    func budget(for month: MonthKey, in householdId: UUID) async throws -> Budget?
    /// El último presupuesto anterior a ese mes, para proponerlo como punto de partida.
    func latestBudget(before month: MonthKey, in householdId: UUID) async throws -> Budget?
    func saveBudget(_ budget: Budget) async throws -> Budget
    /// Todos los movimientos del hogar entre dos días, ambos incluidos.
    func movements(in householdId: UUID, from: CalendarDay, through: CalendarDay) async throws -> [Movement]
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
