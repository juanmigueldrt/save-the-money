import Foundation

extension InMemoryBackend: RecurringService, GoalService {
    private func requirePlanningMember(of householdId: UUID) throws {
        let user = try requireUser()
        guard isMember(user, of: householdId) else { throw AppError.unknown("no es miembro") }
    }

    /// Imita las claves foráneas compuestas: cuenta y categoría tienen que ser del mismo hogar.
    private func checkReferences(account: UUID?, category: UUID?, in householdId: UUID) throws {
        if let account, !financeAccounts.contains(where: { $0.id == account && $0.householdId == householdId }) {
            throw AppError.unknown("cuenta de otro hogar")
        }
        if let category, !financeCategories.contains(where: { $0.id == category && $0.householdId == householdId }) {
            throw AppError.unknown("categoría de otro hogar")
        }
    }

    // MARK: RecurringService

    public func recurringSeries(in householdId: UUID) async throws -> [RecurringSeries] {
        try requirePlanningMember(of: householdId)
        return recurring.filter { $0.householdId == householdId }
            .sorted { $0.trimmedName.localizedStandardCompare($1.trimmedName) == .orderedAscending }
    }

    public func createRecurring(_ series: RecurringSeries) async throws -> RecurringSeries {
        try requirePlanningMember(of: series.householdId)
        if let issue = series.issue { throw AppError.invalidInput(issue) }
        try checkReferences(account: series.accountId, category: series.categoryId, in: series.householdId)
        var saved = series
        saved.name = series.trimmedName
        recurring.append(saved)
        return saved
    }

    public func updateRecurring(_ series: RecurringSeries) async throws -> RecurringSeries {
        guard let index = recurring.firstIndex(where: { $0.id == series.id }) else { throw AppError.unknown("no existe") }
        let householdId = recurring[index].householdId
        try requirePlanningMember(of: householdId)
        if let issue = series.issue { throw AppError.invalidInput(issue) }
        try checkReferences(account: series.accountId, category: series.categoryId, in: householdId)
        var saved = series
        saved.householdId = householdId
        saved.name = series.trimmedName
        recurring[index] = saved
        return saved
    }

    public func deleteRecurring(_ seriesId: UUID) async throws {
        guard let series = recurring.first(where: { $0.id == seriesId }) else { return }
        try requirePlanningMember(of: series.householdId)
        recurring.removeAll { $0.id == seriesId }
    }

    // MARK: GoalService

    public func goals(in householdId: UUID) async throws -> [Goal] {
        try requirePlanningMember(of: householdId)
        return goalList.filter { $0.householdId == householdId }
    }

    public func createGoal(_ goal: Goal) async throws -> Goal {
        try requirePlanningMember(of: goal.householdId)
        if let issue = goal.issue { throw AppError.invalidInput(issue) }
        try checkReferences(account: goal.accountId, category: nil, in: goal.householdId)
        var saved = goal
        saved.name = goal.trimmedName
        goalList.append(saved)
        return saved
    }

    public func updateGoal(_ goal: Goal) async throws -> Goal {
        guard let index = goalList.firstIndex(where: { $0.id == goal.id }) else { throw AppError.unknown("no existe") }
        let householdId = goalList[index].householdId
        try requirePlanningMember(of: householdId)
        if let issue = goal.issue { throw AppError.invalidInput(issue) }
        try checkReferences(account: goal.accountId, category: nil, in: householdId)
        var saved = goal
        saved.householdId = householdId
        saved.name = goal.trimmedName
        goalList[index] = saved
        return saved
    }

    public func deleteGoal(_ goalId: UUID) async throws {
        guard let goal = goalList.first(where: { $0.id == goalId }) else { return }
        try requirePlanningMember(of: goal.householdId)
        goalList.removeAll { $0.id == goalId }
        goalContributions.removeAll { $0.goalId == goalId }
    }

    public func contributions(in householdId: UUID) async throws -> [GoalContribution] {
        try requirePlanningMember(of: householdId)
        return goalContributions.filter { $0.householdId == householdId }.sorted { $0.madeOn > $1.madeOn }
    }

    public func addContribution(_ contribution: GoalContribution) async throws -> GoalContribution {
        try requirePlanningMember(of: contribution.householdId)
        if let issue = contribution.issue { throw AppError.invalidInput(issue) }
        guard goalList.contains(where: { $0.id == contribution.goalId && $0.householdId == contribution.householdId }) else {
            throw AppError.unknown("meta de otro hogar")
        }
        goalContributions.append(contribution)
        return contribution
    }

    public func deleteContribution(_ contributionId: UUID) async throws {
        guard let item = goalContributions.first(where: { $0.id == contributionId }) else { return }
        try requirePlanningMember(of: item.householdId)
        goalContributions.removeAll { $0.id == contributionId }
    }
}
