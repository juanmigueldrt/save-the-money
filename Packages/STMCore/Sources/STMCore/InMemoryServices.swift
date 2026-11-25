import Foundation

/// Servicios en memoria para el modo demo, las previews y las pruebas.
/// Imitan las reglas del servidor (códigos de 48 horas, un solo uso, etc.).
public actor InMemoryBackend: AuthService, HouseholdService {
    private struct UserRecord { var profile: Profile; var password: String }

    private var users: [UUID: UserRecord] = [:]
    private var householdsById: [UUID: Household] = [:]
    private var memberships: [Membership] = []
    private var invites: [HouseholdInvite] = []
    private var currentUser: UUID?
    let now: @Sendable () -> Date

    // Finanzas (InMemoryFinance.swift).
    var financeAccounts: [Account] = []
    var financeCategories: [BudgetCategory] = []
    var financeMovements: [Movement] = []
    var budgets: [Budget] = []
    var paySchedules: [UUID: PaySchedule] = [:]
    var extraBudgetList: [ExtraBudget] = []
    var recurring: [RecurringSeries] = []
    var chargeList: [RecurringCharge] = []
    var goalList: [Goal] = []
    var goalContributions: [GoalContribution] = []
    var scoresByUser: [UUID: [CreditScore]] = [:]
    var holdingList: [Holding] = []
    var holdingPriceList: [HoldingPrice] = []
    var tradeList: [InvestmentTrade] = []
    var planList: [InvestmentPlan] = []
    var creditCardList: [CreditCardTerms] = []
    var installmentList: [CardInstallment] = []

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: AuthService

    public func currentUserId() async -> UUID? { currentUser }

    public func signUp(username: Username, password: String, displayName: String?) async throws -> UUID {
        try throwIfInjected(#function)
        guard !users.values.contains(where: { $0.profile.username == username.value }) else {
            throw AppError.usernameTaken
        }
        guard password.count >= SignUpForm.minimumPasswordLength else { throw AppError.weakPassword }
        let profile = Profile(username: username.value, displayName: displayName)
        users[profile.id] = UserRecord(profile: profile, password: password)
        currentUser = profile.id
        return profile.id
    }

    public func signIn(username: Username, password: String) async throws -> UUID {
        try throwIfInjected(#function)
        guard let account = users.values.first(where: { $0.profile.username == username.value }),
              account.password == password else { throw AppError.invalidCredentials }
        currentUser = account.profile.id
        return account.profile.id
    }

    public func signOut() async throws {
        try throwIfInjected(#function)
        currentUser = nil
    }

    // MARK: Fallos a propósito (sólo pruebas)

    /// Un fallo pedido por una prueba: la llamada `operation` (nil: cualquiera) lanza `error`
    /// después de dejar pasar `remaining` llamadas que coinciden, y sigue fallando hasta `clearFailures()`.
    private struct InjectedFailure { var operation: String?; var remaining: Int; var error: any Error }
    private var injectedFailures: [InjectedFailure] = []

    /// Hace fallar las llamadas, como si se cortara la red o se cancelara la tarea.
    /// `operation` es el nombre del método, p. ej. "addMovement(_:in:)". `after: 1` deja pasar
    /// la primera llamada y falla desde la segunda (el segundo paso de un flujo).
    /// Sin llamar a esto (el modo demo nunca lo hace) nada cambia.
    public func failCalls(_ operation: String? = nil, after successes: Int = 0, with error: any Error = AppError.network) {
        injectedFailures.append(InjectedFailure(operation: operation, remaining: successes, error: error))
    }

    public func clearFailures() { injectedFailures = [] }

    func throwIfInjected(_ operation: String) throws {
        guard let index = injectedFailures.firstIndex(where: { $0.operation == nil || $0.operation == operation }) else { return }
        if injectedFailures[index].remaining > 0 {
            injectedFailures[index].remaining -= 1
            return
        }
        throw injectedFailures[index].error
    }

    // MARK: HouseholdService

    /// Toda llamada con datos pasa por aquí, así que también es donde saltan los fallos pedidos.
    func requireUser(_ operation: String = #function) throws -> UUID {
        try throwIfInjected(operation)
        guard let currentUser else { throw AppError.notSignedIn }
        return currentUser
    }

    func isMember(_ user: UUID, of household: UUID) -> Bool {
        memberships.contains { $0.userId == user && $0.householdId == household }
    }

    public func myProfile() async throws -> Profile {
        let user = try requireUser()
        guard let account = users[user] else { throw AppError.notSignedIn }
        return account.profile
    }

    public func updateProfile(displayName: String?, theme: AppTheme) async throws -> Profile {
        let user = try requireUser()
        users[user]?.profile.displayName = displayName
        users[user]?.profile.theme = theme
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
        financeCategories += BudgetCategory.defaults(for: household.id)
        if users[user]?.profile.defaultHouseholdId == nil {
            users[user]?.profile.defaultHouseholdId = household.id
        }
        return household
    }

    public func members(of householdId: UUID) async throws -> [HouseholdMember] {
        let user = try requireUser()
        guard isMember(user, of: householdId) else { return [] }
        return memberships.filter { $0.householdId == householdId }.compactMap { membership in
            users[membership.userId].map { HouseholdMember(profile: $0.profile, role: membership.role) }
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
        if users[user]?.profile.defaultHouseholdId == nil {
            users[user]?.profile.defaultHouseholdId = household.id
        }
        return household
    }

    public func leave(householdId: UUID) async throws {
        let user = try requireUser()
        memberships.removeAll { $0.userId == user && $0.householdId == householdId }
        if users[user]?.profile.defaultHouseholdId == householdId {
            users[user]?.profile.defaultHouseholdId = nil
        }
    }

    public func renameHousehold(_ householdId: UUID, to name: String) async throws -> Household {
        let user = try requireUser()
        guard memberships.contains(where: { $0.userId == user && $0.householdId == householdId && $0.role == .owner }) else {
            throw AppError.invalidInput("Solo quien creó el hogar puede cambiarle el nombre.")
        }
        guard let valid = HouseholdName.validated(name) else {
            throw AppError.invalidInput("El nombre del hogar tiene que tener entre 1 y 80 letras.")
        }
        guard var household = householdsById[householdId] else { throw AppError.unknown("hogar") }
        household.name = valid
        householdsById[householdId] = household
        return household
    }

    public func removeMember(_ userId: UUID, from householdId: UUID) async throws {
        let user = try requireUser()
        guard memberships.contains(where: { $0.userId == user && $0.householdId == householdId && $0.role == .owner }) else {
            throw AppError.invalidInput("Solo quien creó el hogar puede quitar a un miembro.")
        }
        guard userId != user else { throw AppError.invalidInput("No puedes quitarte a ti mismo.") }
        memberships.removeAll { $0.userId == userId && $0.householdId == householdId }
        if users[userId]?.profile.defaultHouseholdId == householdId {
            users[userId]?.profile.defaultHouseholdId = nil
        }
    }
}
