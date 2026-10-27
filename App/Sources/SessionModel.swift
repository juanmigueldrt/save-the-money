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
        case needsHousehold(Profile)
        case ready(Profile, Household)
    }

    private(set) var state: State = .loading
    /// Código recibido por enlace o QR, pendiente de usar.
    var pendingInvite: InviteCode?

    let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    var isDemo: Bool { services.isDemo }

    func start() async {
        await refresh()
    }

    func refresh() async {
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
        } catch {
            // Sin conexión con sesión abierta: se queda donde estaba si ya había cargado.
            if state == .loading { state = .signedOut }
        }
    }

    func signIn(username: String, password: String) async throws {
        let user = try Username(username)
        _ = try await services.auth.signIn(username: user, password: password)
        await refresh()
    }

    func signUp(_ form: SignUpForm) async throws {
        let user = try Username(form.username)
        _ = try await services.auth.signUp(username: user, password: form.password, displayName: form.trimmedDisplayName)
        await refresh()
    }

    func signOut() async {
        try? await services.auth.signOut()
        state = .signedOut
    }

    func createHousehold(name: String) async throws {
        _ = try await services.households.createHousehold(name: name)
        await refresh()
    }

    func join(_ code: InviteCode) async throws {
        _ = try await services.households.acceptInvite(code)
        pendingInvite = nil
        await refresh()
    }

    func leaveHousehold(_ household: Household) async throws {
        try await services.households.leave(householdId: household.id)
        await refresh()
    }

    func handle(url: URL) {
        if let code = InviteCode(url.absoluteString) {
            pendingInvite = code
        }
    }
}
