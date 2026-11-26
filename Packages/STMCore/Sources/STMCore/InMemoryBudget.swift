import Foundation

/// Presupuestos en memoria, como el servidor: uno por persona, hogar y periodo, y cada uno ve solo los suyos.
extension InMemoryBackend: BudgetService {
    @discardableResult
    private func requireBudgetMember(of householdId: UUID, _ operation: String = #function) throws -> UUID {
        let user = try requireUser(operation)
        guard isMember(user, of: householdId) else { throw AppError.unknown("no es miembro") }
        return user
    }

    public func budget(startingOn day: CalendarDay, in householdId: UUID) async throws -> Budget? {
        let user = try requireBudgetMember(of: householdId)
        return budgets[user, default: []].first { $0.householdId == householdId && $0.period.start == day }
    }

    public func latestBudget(before day: CalendarDay, in householdId: UUID) async throws -> Budget? {
        let user = try requireBudgetMember(of: householdId)
        return budgets[user, default: []].filter { $0.householdId == householdId && $0.period.start < day }
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
        let user = try requireBudgetMember(of: householdId)
        return extraBudgetList.filter { $0.householdId == householdId && isMine($0.id, in: householdId, user: user) }
            .sorted { $0.isFavorite != $1.isFavorite ? $0.isFavorite : $0.startsOn > $1.startsOn }
    }

    public func saveExtraBudget(_ budget: ExtraBudget) async throws -> ExtraBudget {
        let user = try requireBudgetMember(of: budget.householdId)
        if let issue = budget.issue { throw AppError.invalidInput(issue) }
        // Uno ajeno no se ve: no se cambia.
        if let stored = creators[budget.id], stored != user { throw AppError.unknown("no existe") }
        var saved = budget
        saved.name = budget.trimmedName
        if saved.isFavorite {
            // Un favorito por persona, como el disparador del servidor.
            for index in extraBudgetList.indices where creators[extraBudgetList[index].id] == user {
                extraBudgetList[index].isFavorite = false
            }
        }
        extraBudgetList.removeAll { $0.id == budget.id }
        extraBudgetList.append(saved)
        creators[saved.id] = user
        return saved
    }

    public func deleteExtraBudget(_ id: UUID) async throws {
        guard let budget = extraBudgetList.first(where: { $0.id == id }) else { return }
        let user = try requireBudgetMember(of: budget.householdId)
        guard isMine(id, in: budget.householdId, user: user) else { return }
        extraBudgetList.removeAll { $0.id == id }
    }

    public func saveBudget(_ budget: Budget) async throws -> Budget {
        let user = try requireBudgetMember(of: budget.householdId)
        if let issue = budget.issue { throw AppError.invalidInput(issue) }
        let ownCategories = Set(financeCategories.filter {
            $0.householdId == budget.householdId && isMine($0.id, in: budget.householdId, user: user)
        }.map(\.id))
        guard budget.limits.keys.allSatisfy(ownCategories.contains) else { throw AppError.unknown("categoría de otro hogar") }
        budgets[user, default: []].removeAll { $0.householdId == budget.householdId && $0.period.start == budget.period.start }
        budgets[user, default: []].append(budget)
        return budget
    }

    public func movements(in householdId: UUID, from: CalendarDay, through: CalendarDay) async throws -> [Movement] {
        let user = try requireBudgetMember(of: householdId)
        return financeMovements
            .filter { $0.householdId == householdId && $0.bookedOn >= from && $0.bookedOn <= through && creators[$0.id] == user }
            .sorted { $0.bookedOn > $1.bookedOn }
    }
}
