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

    /// Movimientos más recientes primero. Con `accountId`, sólo los de esa cuenta.
    func movements(in householdId: UUID, accountId: UUID?, limit: Int) async throws -> [Movement]
    func addMovement(_ draft: MovementDraft, in householdId: UUID) async throws -> Movement
    func updateMovement(_ movement: Movement) async throws -> Movement
    func deleteMovement(_ movementId: UUID) async throws
    /// Guarda los movimientos de un CSV. Los que ya estaban (misma huella) se ignoran.
    func importMovements(_ drafts: [MovementDraft], in householdId: UUID) async throws -> ImportResult
}
