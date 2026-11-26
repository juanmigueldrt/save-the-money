import Foundation
import Observation
import STMCore

/// Estado de la sesión: quién ha entrado y en qué hogar está.
@Observable
@MainActor
final class SessionModel {
    enum State: Equatable {
        case loading
        case signedOut
        /// Hay sesión guardada pero no se ha podido cargar (sin red o fallo del servidor); el texto es el aviso.
        case offline(String)
        case needsHousehold(Profile)
        case ready(Profile, Household)
    }

    private(set) var state: State = .loading
    /// Código recibido por enlace o QR, pendiente de usar.
    var pendingInvite: InviteCode?

    let services: AppServices
    /// Borra lo que queda en el dispositivo de la cuenta (avisos, preferencias, exportados).
    private let clearLocalData: @Sendable () async -> Void

    init(services: AppServices, clearLocalData: @escaping @Sendable () async -> Void = {}) {
        self.services = services
        self.clearLocalData = clearLocalData
    }

    var isDemo: Bool { services.isDemo }

    /// Tema elegido en el perfil; antes de entrar, el último que se usó en este dispositivo.
    var theme: AppTheme {
        switch state {
        case .ready(let profile, _), .needsHousehold(let profile): profile.theme
        case .loading, .signedOut, .offline: AppTheme(rawValue: UserDefaults.standard.string(forKey: Self.themeKey) ?? "") ?? .system
        }
    }

    static let themeKey = "lastTheme"

    /// Guarda el tema en el perfil (se aplica en todos los dispositivos de esa persona).
    func setTheme(_ theme: AppTheme) async throws {
        guard case .ready(let profile, let household) = state else { return }
        let updated = try await services.households.updateProfile(displayName: profile.displayName, theme: theme)
        UserDefaults.standard.set(updated.theme.rawValue, forKey: Self.themeKey)
        state = .ready(updated, household)
    }

    /// Al abrir la app y en «Reintentar».
    func start() async {
        try? await refresh()
    }

    /// Sólo `AppError.notSignedIn` (no hay sesión o el servidor la rechaza) lleva al login.
    /// Cualquier otro fallo no descarta la sesión guardada: se lanza para avisar y, si aún no
    /// había un hogar abierto, se pasa a «sin conexión» con reintento.
    func refresh() async throws {
        signOutError = nil
        guard await services.auth.currentUserId() != nil else {
            state = .signedOut
            return
        }
        do {
            let profile = try await services.households.myProfile()
            let households = try await services.households.households()
            if let home = households.first(where: { $0.id == profile.defaultHouseholdId }) ?? households.first {
                state = .ready(profile, home)
            } else {
                state = .needsHousehold(profile)
            }
        } catch AppError.notSignedIn {
            state = .signedOut
        } catch let cancelled as CancellationError {
            throw cancelled
        } catch {
            // Con un hogar ya abierto se queda donde estaba; quien llamó enseña el aviso.
            if case .ready = state { throw error }
            state = .offline(((error as? AppError) ?? .unknown("")).errorDescription ?? "")
            throw error
        }
    }

    func signIn(username: String, password: String) async throws {
        let user = try Username(username, forSignIn: true)
        _ = try await services.auth.signIn(username: user, password: password)
        try await refresh()
    }

    func signUp(_ form: SignUpForm) async throws {
        let user = try Username(form.username)
        _ = try await services.auth.signUp(username: user, password: form.password, displayName: form.trimmedDisplayName)
        try await refresh()
    }

    /// La sesión de este dispositivo sigue abierta; el servidor cierra las de los demás.
    func changePassword(_ form: ChangePasswordForm) async throws {
        if let issue = form.firstIssue { throw AppError.invalidInput(issue.message) }
        try await services.auth.changePassword(currentPassword: form.currentPassword, newPassword: form.newPassword)
    }

    /// Si el cierre no llegó al servidor. Este dispositivo ya está desconectado; el aviso se ve en la pantalla de entrar.
    private(set) var signOutError: String?

    func signOut() async {
        signOutError = nil
        do {
            try await services.auth.signOut()
        } catch {
            signOutError = "No se ha podido cerrar la sesión en el servidor. " + ((error as? AppError)?.errorDescription ?? "")
        }
        // Se borra aunque el servidor no haya contestado: el dispositivo ya no es de esa cuenta.
        await clearLocalData()
        state = .signedOut
    }

    func createHousehold(name: String) async throws {
        _ = try await services.households.createHousehold(name: name)
        try await refresh()
    }

    func join(_ code: InviteCode) async throws {
        _ = try await services.households.acceptInvite(code)
        pendingInvite = nil
        try await refresh()
    }

    func renameHousehold(_ household: Household, to name: String) async throws {
        let renamed = try await services.households.renameHousehold(household.id, to: name)
        if case .ready(let profile, let current) = state, current.id == renamed.id {
            state = .ready(profile, renamed)
        }
    }

    func leaveHousehold(_ household: Household) async throws {
        try await services.households.leave(householdId: household.id)
        try await refresh()
    }

    func handle(url: URL) {
        if let action = QuickAction(url: url) {
            QuickActionRouter.shared.open(action)
        } else if let code = InviteCode(url.absoluteString) {
            pendingInvite = code
        }
    }
}
