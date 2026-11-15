import Foundation

extension InMemoryBackend: BudgetService {
    private func requireBudgetMember(of householdId: UUID) throws {
        let user = try requireUser()
        guard isMember(user, of: householdId) else { throw AppError.unknown("no es miembro") }
    }

    public func budget(startingOn day: CalendarDay, in householdId: UUID) async throws -> Budget? {
        try requireBudgetMember(of: householdId)
        return budgets.first { $0.householdId == householdId && $0.period.start == day }
    }

    public func latestBudget(before day: CalendarDay, in householdId: UUID) async throws -> Budget? {
        try requireBudgetMember(of: householdId)
        return budgets.filter { $0.householdId == householdId && $0.period.start < day }
            .max { $0.period.start < $1.period.start }
    }

    public func paySchedule() async throws -> PaySchedule? {
        let user = try requireUser()
        return paySchedules[user]
    }

    public func savePaySchedule(_ schedule: PaySchedule) async throws -> PaySchedule {
        let user = try requireUser()
        if let issue = schedule.issue { throw AppError.invalidInput(issue) }
        paySchedules[user] = schedule
        return schedule
    }

    public func extraBudgets(in householdId: UUID) async throws -> [ExtraBudget] {
        try requireBudgetMember(of: householdId)
        return extraBudgetList.filter { $0.householdId == householdId }
            .sorted { $0.isFavorite != $1.isFavorite ? $0.isFavorite : $0.startsOn > $1.startsOn }
    }

    public func saveExtraBudget(_ budget: ExtraBudget) async throws -> ExtraBudget {
        try requireBudgetMember(of: budget.householdId)
        if let issue = budget.issue { throw AppError.invalidInput(issue) }
        var saved = budget
        saved.name = budget.trimmedName
        if saved.isFavorite {
            for index in extraBudgetList.indices { extraBudgetList[index].isFavorite = false }
        }
        extraBudgetList.removeAll { $0.id == budget.id }
        extraBudgetList.append(saved)
        return saved
    }

    public func deleteExtraBudget(_ id: UUID) async throws {
        guard let budget = extraBudgetList.first(where: { $0.id == id }) else { return }
        try requireBudgetMember(of: budget.householdId)
        extraBudgetList.removeAll { $0.id == id }
    }

    public func saveBudget(_ budget: Budget) async throws -> Budget {
        try requireBudgetMember(of: budget.householdId)
        if let issue = budget.issue { throw AppError.invalidInput(issue) }
        let ownCategories = Set(financeCategories.filter { $0.householdId == budget.householdId }.map(\.id))
        guard budget.limits.keys.allSatisfy(ownCategories.contains) else { throw AppError.unknown("categoría de otro hogar") }
        budgets.removeAll { $0.householdId == budget.householdId && $0.period.start == budget.period.start }
        budgets.append(budget)
        return budget
    }

    public func movements(in householdId: UUID, from: CalendarDay, through: CalendarDay) async throws -> [Movement] {
        try requireBudgetMember(of: householdId)
        return financeMovements
            .filter { $0.householdId == householdId && $0.bookedOn >= from && $0.bookedOn <= through }
            .sorted { $0.bookedOn > $1.bookedOn }
    }
}
