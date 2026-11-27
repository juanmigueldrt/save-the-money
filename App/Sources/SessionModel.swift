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

    private(set) var state: State = .loading {
        didSet { updateModels() }
    }
    /// Los modelos del hogar abierto. Se crean una vez al entrar en él y siguen mientras esté abierto
    /// (refrescar, cambiar el tema o el nombre no los rehace); fuera de `.ready` no hay ninguno.
    /// Cambiar el día de inicio del mes sí los rehace: los periodos de presupuestos e informes son otros.
    private(set) var models: HouseholdModels?
    /// Los hogares de quien ha entrado, para elegir cuál abrir cuando hay más de uno.
    private(set) var households: [Household] = []
    /// Hogares de los que le han quitado y de los que aún puede exportar sus datos (ORC-56).
    private(set) var removedHouseholds: [RemovedHousehold] = []
    /// Código recibido por enlace o QR, pendiente de usar.
    var pendingInvite: InviteCode?

    let services: AppServices
    /// Borra lo que queda en el dispositivo de la cuenta (avisos, preferencias, exportados).
    private let clearLocalData: @Sendable () async -> Void
    /// Dónde se recuerda el hogar elegido en este dispositivo.
    private let defaults: UserDefaults

    init(services: AppServices, clearLocalData: @escaping @Sendable () async -> Void = {},
         defaults: UserDefaults = .standard) {
        self.services = services
        self.clearLocalData = clearLocalData
        self.defaults = defaults
    }

    var isDemo: Bool { services.isDemo }

    private func updateModels() {
        guard case .ready(_, let household) = state else {
            models = nil
            return
        }
        if models?.householdId != household.id || models?.monthStartDay != household.monthStartDay {
            models = HouseholdModels(household: household, services: services)
        }
    }

    /// Clave del hogar elegido por cada persona en este dispositivo.
    static func openHouseholdKey(_ userId: UUID) -> String { "stm.household.open.\(userId.uuidString)" }

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
            self.households = households
            // Si falla (sin red, o un servidor que aún no tiene la función) no se bloquea la entrada: no se enseña la lista.
            removedHouseholds = (try? await services.households.removedHouseholds()) ?? []
            let chosen = defaults.string(forKey: Self.openHouseholdKey(profile.id)).flatMap(UUID.init(uuidString:))
            if let home = households.first(where: { $0.id == chosen })
                ?? households.first(where: { $0.id == profile.defaultHouseholdId }) ?? households.first {
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
            state = .offline(((error as? AppError) ?? .unknown("")).text ?? "")
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

    /// Borra la cuenta en el servidor y, si ha ido bien, lo que queda de ella en este dispositivo.
    /// Si falla no se borra nada y la sesión sigue como estaba.
    func deleteAccount(currentPassword: String) async throws {
        try await services.auth.deleteAccount(currentPassword: currentPassword)
        await clearLocalData()
        households = []
        removedHouseholds = []
        state = .signedOut
    }

    /// Si el cierre no llegó al servidor. Este dispositivo ya está desconectado; el aviso se ve en la pantalla de entrar.
    private(set) var signOutError: String?

    func signOut() async {
        signOutError = nil
        do {
            try await services.auth.signOut()
        } catch {
            signOutError = String(localized: "No se ha podido cerrar la sesión en el servidor. ") + ((error as? AppError)?.text ?? "")
        }
        // Se borra aunque el servidor no haya contestado: el dispositivo ya no es de esa cuenta.
        await clearLocalData()
        households = []
        removedHouseholds = []
        state = .signedOut
    }

    func createHousehold(name: String) async throws {
        _ = try await services.households.createHousehold(name: name)
        try await refresh()
    }

    /// Tras unirse se abre el hogar nuevo; si ya tenía otro, sigue en los dos y puede volver a él con `open`.
    func join(_ code: InviteCode) async throws {
        let joined = try await services.households.acceptInvite(code)
        pendingInvite = nil
        switch state {
        case .ready(let profile, _), .needsHousehold(let profile):
            defaults.set(joined.id.uuidString, forKey: Self.openHouseholdKey(profile.id))
        case .loading, .signedOut, .offline: break
        }
        try await refresh()
    }

    /// Abre otro de sus hogares y lo recuerda en este dispositivo. Los modelos son nuevos: nada del anterior se ve.
    func open(_ household: Household) {
        guard case .ready(let profile, let current) = state, current.id != household.id,
              let chosen = households.first(where: { $0.id == household.id }) else { return }
        defaults.set(chosen.id.uuidString, forKey: Self.openHouseholdKey(profile.id))
        state = .ready(profile, chosen)
    }

    /// Nombre visible: vacío vuelve al nombre de usuario; como al crear la cuenta, como mucho 60 caracteres.
    func setDisplayName(_ name: String) async throws {
        guard case .ready(let profile, let household) = state else { return }
        let updated = try await services.households.updateProfile(
            displayName: SignUpForm(displayName: name).trimmedDisplayName, theme: profile.theme)
        if case .ready(_, let current) = state, current.id == household.id { state = .ready(updated, current) }
    }

    /// Sólo el dueño. No cambia ningún dato guardado: los modelos se rehacen y todo se recalcula con los meses nuevos.
    func setMonthStartDay(_ day: Int) async throws {
        guard case .ready(_, let household) = state else { return }
        let updated = try await services.households.setMonthStartDay(household.id, to: day)
        if case .ready(let profile, let current) = state, current.id == updated.id {
            replaceHousehold(updated)
            state = .ready(profile, updated)
        }
    }

    private func replaceHousehold(_ updated: Household) {
        households = households.map { $0.id == updated.id ? updated : $0 }
    }

    func renameHousehold(_ household: Household, to name: String) async throws {
        let renamed = try await services.households.renameHousehold(household.id, to: name)
        if case .ready(let profile, let current) = state, current.id == renamed.id {
            replaceHousehold(renamed)
            state = .ready(profile, renamed)
        }
    }

    func handle(url: URL) {
        if let action = QuickAction(url: url) {
            QuickActionRouter.shared.open(action)
        } else if let code = InviteCode(url.absoluteString) {
            pendingInvite = code
        }
    }
}
