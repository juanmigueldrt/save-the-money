import Foundation

extension InMemoryBackend: RecurringService, GoalService {
    @discardableResult
    private func requirePlanningMember(of householdId: UUID, _ operation: String = #function) throws -> UUID {
        let user = try requireUser(operation)
        guard isMember(user, of: householdId) else { throw AppError.unknown("no es miembro") }
        return user
    }

    /// Imita las claves foráneas compuestas y el RLS: cuenta y categoría tienen que ser del mismo hogar y propias.
    private func checkReferences(account: UUID?, category: UUID?, in householdId: UUID, by user: UUID) throws {
        if let account, !financeAccounts.contains(where: { $0.id == account && $0.householdId == householdId })
            || !isMine(account, in: householdId, user: user) {
            throw AppError.unknown("cuenta de otro hogar")
        }
        if let category, !financeCategories.contains(where: { $0.id == category && $0.householdId == householdId })
            || !isMine(category, in: householdId, user: user) {
            throw AppError.unknown("categoría de otro hogar")
        }
    }

    // MARK: RecurringService

    public func recurringSeries(in householdId: UUID) async throws -> [RecurringSeries] {
        let user = try requirePlanningMember(of: householdId)
        return recurring.filter { $0.householdId == householdId && isMine($0.id, in: householdId, user: user) }
            .sorted { $0.trimmedName.localizedStandardCompare($1.trimmedName) == .orderedAscending }
    }

    public func createRecurring(_ series: RecurringSeries) async throws -> RecurringSeries {
        let user = try requirePlanningMember(of: series.householdId)
        if let issue = series.issue { throw AppError.invalidInput(issue) }
        try checkReferences(account: series.accountId, category: series.categoryId, in: series.householdId, by: user)
        // Repetir el alta solo vale con el mismo hogar, nombre, tipo, importe y primer día.
        if let stored = try replayed(recurring.first(where: { $0.id == series.id }), by: user, same: {
            $0.householdId == series.householdId && $0.name == series.trimmedName && $0.kind == series.kind
                && $0.amount.minor == series.amount.minor && $0.startsOn == series.startsOn
        }) { return stored }
        var saved = series
        saved.name = series.trimmedName
        saved.updatedAt = nextVersion()
        recurring.append(saved)
        creators[saved.id] = user
        return saved
    }

    public func updateRecurring(_ series: RecurringSeries) async throws -> RecurringSeries {
        if let issue = series.issue { throw AppError.invalidInput(issue) }
        guard let index = recurring.firstIndex(where: { $0.id == series.id }) else { throw AppError.movementChanged }
        let householdId = recurring[index].householdId
        let user = try requireCurrent(series.id, seen: series.updatedAt, stored: recurring[index].updatedAt, in: householdId)
        try checkReferences(account: series.accountId, category: series.categoryId, in: householdId, by: user)
        var saved = series
        saved.householdId = householdId
        saved.name = series.trimmedName
        saved.updatedAt = nextVersion()
        recurring[index] = saved
        return saved
    }

    public func deleteRecurring(_ seriesId: UUID) async throws {
        guard let series = recurring.first(where: { $0.id == seriesId }) else { return }
        let user = try requirePlanningMember(of: series.householdId)
        guard isMine(seriesId, in: series.householdId, user: user) else { return }
        recurring.removeAll { $0.id == seriesId }
        chargeList.removeAll { $0.seriesId == seriesId }
    }

    public func recurringCharges(in householdId: UUID) async throws -> [RecurringCharge] {
        let user = try requirePlanningMember(of: householdId)
        return chargeList.filter { $0.householdId == householdId && isMine($0.id, in: householdId, user: user) }
    }

    public func createCharges(_ charges: [RecurringCharge]) async throws -> [RecurringCharge] {
        var created: [RecurringCharge] = []
        for charge in charges {
            let user = try requirePlanningMember(of: charge.householdId)
            guard recurring.contains(where: { $0.id == charge.seriesId && $0.householdId == charge.householdId }),
                  isMine(charge.seriesId, in: charge.householdId, user: user) else {
                throw AppError.unknown("serie de otro hogar")
            }
            if chargeList.contains(where: { $0.seriesId == charge.seriesId && $0.dueOn == charge.dueOn }) { continue }
            var saved = charge
            saved.updatedAt = nextVersion()
            chargeList.append(saved)
            creators[saved.id] = user
            created.append(saved)
        }
        return created
    }

    public func confirmCharge(_ chargeId: UUID, with draft: MovementDraft) async throws -> Movement {
        guard let index = chargeList.firstIndex(where: { $0.id == chargeId }) else { throw AppError.unknown("no existe") }
        // Como el servidor: un cargo ajeno no se ve. Sin pasar por `requireUser`: los fallos
        // pedidos siguen saltando en `addMovement`, como antes.
        guard let user = currentUser, isMine(chargeId, in: chargeList[index].householdId, user: user) else {
            throw AppError.unknown("no existe")
        }
        guard chargeList[index].isPending else { throw AppError.invalidInput("Ese cargo ya no está pendiente.") }
        let movement = try await addMovement(draft, in: chargeList[index].householdId)
        chargeList[index].status = .confirmed
        chargeList[index].transactionId = movement.id
        chargeList[index].amount = movement.amount
        // Como el servidor: confirmarlo cambia la fila, y con ella su versión.
        chargeList[index].updatedAt = nextVersion()
        return movement
    }

    public func updateCharge(_ charge: RecurringCharge, status: ChargeStatus,
                             transactionId: UUID?) async throws -> RecurringCharge {
        guard let index = chargeList.firstIndex(where: { $0.id == charge.id }) else { throw AppError.movementChanged }
        _ = try requireCurrent(charge.id, seen: charge.updatedAt, stored: chargeList[index].updatedAt,
                               in: chargeList[index].householdId)
        chargeList[index].status = status
        chargeList[index].transactionId = status == .pending ? nil : transactionId
        chargeList[index].updatedAt = nextVersion()
        return chargeList[index]
    }

    public func deleteCharge(_ chargeId: UUID) async throws {
        guard let charge = chargeList.first(where: { $0.id == chargeId }) else { return }
        let user = try requirePlanningMember(of: charge.householdId)
        guard isMine(chargeId, in: charge.householdId, user: user) else { return }
        chargeList.removeAll { $0.id == chargeId }
    }

    // MARK: GoalService

    public func goals(in householdId: UUID) async throws -> [Goal] {
        let user = try requirePlanningMember(of: householdId)
        return goalList.filter { $0.householdId == householdId && isMine($0.id, in: householdId, user: user) }
    }

    public func createGoal(_ goal: Goal) async throws -> Goal {
        let user = try requirePlanningMember(of: goal.householdId)
        if let issue = goal.issue { throw AppError.invalidInput(issue) }
        try checkReferences(account: goal.accountId, category: nil, in: goal.householdId, by: user)
        // Repetir el alta solo vale con el mismo hogar, nombre, tipo y objetivo.
        if let stored = try replayed(goalList.first(where: { $0.id == goal.id }), by: user, same: {
            $0.householdId == goal.householdId && $0.name == goal.trimmedName && $0.kind == goal.kind
                && $0.target.minor == goal.target.minor
        }) { return stored }
        var saved = goal
        saved.name = goal.trimmedName
        saved.updatedAt = nextVersion()
        goalList.append(saved)
        creators[saved.id] = user
        return saved
    }

    public func updateGoal(_ goal: Goal) async throws -> Goal {
        if let issue = goal.issue { throw AppError.invalidInput(issue) }
        guard let index = goalList.firstIndex(where: { $0.id == goal.id }) else { throw AppError.movementChanged }
        let householdId = goalList[index].householdId
        let user = try requireCurrent(goal.id, seen: goal.updatedAt, stored: goalList[index].updatedAt, in: householdId)
        try checkReferences(account: goal.accountId, category: nil, in: householdId, by: user)
        var saved = goal
        saved.householdId = householdId
        saved.name = goal.trimmedName
        saved.updatedAt = nextVersion()
        goalList[index] = saved
        return saved
    }

    public func deleteGoal(_ goalId: UUID) async throws {
        guard let goal = goalList.first(where: { $0.id == goalId }) else { return }
        let user = try requirePlanningMember(of: goal.householdId)
        guard isMine(goalId, in: goal.householdId, user: user) else { return }
        goalList.removeAll { $0.id == goalId }
        goalContributions.removeAll { $0.goalId == goalId }
    }

    public func contributions(in householdId: UUID) async throws -> [GoalContribution] {
        let user = try requirePlanningMember(of: householdId)
        return goalContributions.filter { $0.householdId == householdId && isMine($0.id, in: householdId, user: user) }.sorted { $0.madeOn > $1.madeOn }
    }

    public func addContribution(_ contribution: GoalContribution) async throws -> GoalContribution {
        let user = try requirePlanningMember(of: contribution.householdId)
        if let issue = contribution.issue { throw AppError.invalidInput(issue) }
        guard goalList.contains(where: { $0.id == contribution.goalId && $0.householdId == contribution.householdId }),
              isMine(contribution.goalId, in: contribution.householdId, user: user) else {
            throw AppError.unknown("meta de otro hogar")
        }
        // Repetir la aportación solo vale con la misma meta, importe y día.
        if let stored = try replayed(goalContributions.first(where: { $0.id == contribution.id }), by: user, same: {
            $0.goalId == contribution.goalId && $0.amount.minor == contribution.amount.minor && $0.madeOn == contribution.madeOn
        }) { return stored }
        goalContributions.append(contribution)
        creators[contribution.id] = user
        return contribution
    }

    public func deleteContribution(_ contributionId: UUID) async throws {
        guard let item = goalContributions.first(where: { $0.id == contributionId }) else { return }
        let user = try requirePlanningMember(of: item.householdId)
        guard isMine(contributionId, in: item.householdId, user: user) else { return }
        goalContributions.removeAll { $0.id == contributionId }
    }
}
