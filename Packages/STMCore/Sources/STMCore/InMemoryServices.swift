import Foundation

/// Servicios en memoria para el modo demo, las previews y las pruebas.
/// Imitan las reglas del servidor (códigos de 48 horas, un solo uso, etc.).
public actor InMemoryBackend: AuthService, HouseholdService {
    private struct Account { var profile: Profile; var password: String }

    private var accounts: [UUID: Account] = [:]
    private var householdsById: [UUID: Household] = [:]
    private var memberships: [Membership] = []
    private var invites: [HouseholdInvite] = []
    private var currentUser: UUID?
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: AuthService

    public func currentUserId() async -> UUID? { currentUser }

    public func signUp(username: Username, password: String, displayName: String?) async throws -> UUID {
        guard !accounts.values.contains(where: { $0.profile.username == username.value }) else {
            throw AppError.usernameTaken
        }
        guard password.count >= SignUpForm.minimumPasswordLength else { throw AppError.weakPassword }
        let profile = Profile(username: username.value, displayName: displayName)
        accounts[profile.id] = Account(profile: profile, password: password)
        currentUser = profile.id
        return profile.id
    }

    public func signIn(username: Username, password: String) async throws -> UUID {
        guard let account = accounts.values.first(where: { $0.profile.username == username.value }),
              account.password == password else { throw AppError.invalidCredentials }
        currentUser = account.profile.id
        return account.profile.id
    }

    public func signOut() async throws { currentUser = nil }

    // MARK: HouseholdService

    private func requireUser() throws -> UUID {
        guard let currentUser else { throw AppError.notSignedIn }
        return currentUser
    }

    private func isMember(_ user: UUID, of household: UUID) -> Bool {
        memberships.contains { $0.userId == user && $0.householdId == household }
    }

    public func myProfile() async throws -> Profile {
        let user = try requireUser()
        guard let account = accounts[user] else { throw AppError.notSignedIn }
        return account.profile
    }

    public func updateProfile(displayName: String?, theme: AppTheme) async throws -> Profile {
        let user = try requireUser()
        accounts[user]?.profile.displayName = displayName
        accounts[user]?.profile.theme = theme
        return try await myProfile()
    }

    public func households() async throws -> [Household] {
        let user = try requireUser()
        return memberships.filter { $0.userId == user }.compactMap { householdsById[$0.householdId] }
    }

    public func createHousehold(name: String) async throws -> Household {
        let user = try requireUser()
        guard let valid = HouseholdName.validated(name) else { throw AppError.unknown("nombre") }
        let household = Household(name: valid)
        householdsById[household.id] = household
        memberships.append(Membership(householdId: household.id, userId: user, role: .owner))
        if accounts[user]?.profile.defaultHouseholdId == nil {
            accounts[user]?.profile.defaultHouseholdId = household.id
        }
        return household
    }

    public func members(of householdId: UUID) async throws -> [HouseholdMember] {
        let user = try requireUser()
        guard isMember(user, of: householdId) else { return [] }
        return memberships.filter { $0.householdId == householdId }.compactMap { membership in
            accounts[membership.userId].map { HouseholdMember(profile: $0.profile, role: membership.role) }
        }
    }

    public func pendingInvites(for householdId: UUID) async throws -> [HouseholdInvite] {
        let user = try requireUser()
        guard isMember(user, of: householdId) else { return [] }
        return invites.filter { $0.householdId == householdId && $0.isUsable(at: now()) }
    }

    public func createInvite(for householdId: UUID) async throws -> HouseholdInvite {
        let user = try requireUser()
        guard isMember(user, of: householdId) else { throw AppError.unknown("no es miembro") }
        var code: String
        repeat {
            code = String((0..<InviteCode.length).map { _ in InviteCode.alphabet.randomElement()! })
        } while invites.contains { $0.code == code }
        let invite = HouseholdInvite(householdId: householdId, code: code,
                                     expiresAt: now().addingTimeInterval(48 * 3600))
        invites.append(invite)
        return invite
    }

    public func revokeInvite(_ inviteId: UUID) async throws {
        let user = try requireUser()
        guard let index = invites.firstIndex(where: { $0.id == inviteId }),
              isMember(user, of: invites[index].householdId),
              invites[index].status == .pending else { return }
        invites[index].status = .revoked
    }

    public func acceptInvite(_ code: InviteCode) async throws -> Household {
        let user = try requireUser()
        guard let index = invites.firstIndex(where: { $0.code == code.value }),
              invites[index].isUsable(at: now()),
              let household = householdsById[invites[index].householdId] else {
            throw AppError.invalidOrExpiredInvite
        }
        guard !isMember(user, of: household.id) else { throw AppError.alreadyMember }
        memberships.append(Membership(householdId: household.id, userId: user, role: .member))
        invites[index].status = .accepted
        if accounts[user]?.profile.defaultHouseholdId == nil {
            accounts[user]?.profile.defaultHouseholdId = household.id
        }
        return household
    }

    public func leave(householdId: UUID) async throws {
        let user = try requireUser()
        memberships.removeAll { $0.userId == user && $0.householdId == householdId }
        if accounts[user]?.profile.defaultHouseholdId == householdId {
            accounts[user]?.profile.defaultHouseholdId = nil
        }
    }
}
