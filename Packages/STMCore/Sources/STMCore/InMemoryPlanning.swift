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
        var saved = series
        saved.name = series.trimmedName
        recurring.append(saved)
        creators[saved.id] = user
        return saved
    }

    public func updateRecurring(_ series: RecurringSeries) async throws -> RecurringSeries {
        guard let index = recurring.firstIndex(where: { $0.id == series.id }) else { throw AppError.unknown("no existe") }
        let householdId = recurring[index].householdId
        let user = try requirePlanningMember(of: householdId)
        guard isMine(series.id, in: householdId, user: user) else { throw AppError.unknown("no existe") }
        if let issue = series.issue { throw AppError.invalidInput(issue) }
        try checkReferences(account: series.accountId, category: series.categoryId, in: householdId, by: user)
        var saved = series
        saved.householdId = householdId
        saved.name = series.trimmedName
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
            chargeList.append(charge)
            creators[charge.id] = user
            created.append(charge)
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
        return movement
    }

    public func updateCharge(_ chargeId: UUID, status: ChargeStatus, transactionId: UUID?) async throws {
        guard let index = chargeList.firstIndex(where: { $0.id == chargeId }) else { throw AppError.unknown("no existe") }
        let user = try requirePlanningMember(of: chargeList[index].householdId)
        guard isMine(chargeId, in: chargeList[index].householdId, user: user) else { throw AppError.unknown("no existe") }
        chargeList[index].status = status
        chargeList[index].transactionId = status == .pending ? nil : transactionId
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
        var saved = goal
        saved.name = goal.trimmedName
        goalList.append(saved)
        creators[saved.id] = user
        return saved
    }

    public func updateGoal(_ goal: Goal) async throws -> Goal {
        guard let index = goalList.firstIndex(where: { $0.id == goal.id }) else { throw AppError.unknown("no existe") }
        let householdId = goalList[index].householdId
        let user = try requirePlanningMember(of: householdId)
        guard isMine(goal.id, in: householdId, user: user) else { throw AppError.unknown("no existe") }
        if let issue = goal.issue { throw AppError.invalidInput(issue) }
        try checkReferences(account: goal.accountId, category: nil, in: householdId, by: user)
        var saved = goal
        saved.householdId = householdId
        saved.name = goal.trimmedName
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
