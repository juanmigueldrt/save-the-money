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
