import Foundation

extension InMemoryBackend: BudgetService {
    private func requireBudgetMember(of householdId: UUID) throws {
        let user = try requireUser()
        guard isMember(user, of: householdId) else { throw AppError.unknown("no es miembro") }
    }

    public func budget(for month: MonthKey, in householdId: UUID) async throws -> Budget? {
        try requireBudgetMember(of: householdId)
        return budgets.first { $0.householdId == householdId && $0.month == month }
    }

    public func latestBudget(before month: MonthKey, in householdId: UUID) async throws -> Budget? {
        try requireBudgetMember(of: householdId)
        return budgets.filter { $0.householdId == householdId && $0.month < month }.max { $0.month < $1.month }
    }

    public func saveBudget(_ budget: Budget) async throws -> Budget {
        try requireBudgetMember(of: budget.householdId)
        if let issue = budget.issue { throw AppError.invalidInput(issue) }
        let ownCategories = Set(financeCategories.filter { $0.householdId == budget.householdId }.map(\.id))
        guard budget.limits.keys.allSatisfy(ownCategories.contains) else { throw AppError.unknown("categoría de otro hogar") }
        budgets.removeAll { $0.householdId == budget.householdId && $0.month == budget.month }
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
