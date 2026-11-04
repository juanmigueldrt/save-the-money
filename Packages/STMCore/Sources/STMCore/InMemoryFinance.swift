import Foundation

/// Cuentas y movimientos en memoria, con las mismas reglas que el RLS del servidor:
/// sólo se ve y se toca lo de los hogares de los que uno es miembro.
extension InMemoryBackend: FinanceService {
    private func requireMember(of householdId: UUID) throws -> UUID {
        let user = try requireUser()
        guard isMember(user, of: householdId) else { throw AppError.unknown("no es miembro") }
        return user
    }

    public func accounts(in householdId: UUID) async throws -> [Account] {
        _ = try requireMember(of: householdId)
        return financeAccounts.filter { $0.householdId == householdId }
    }

    public func balances(in householdId: UUID) async throws -> [UUID: Money] {
        let accounts = try await accounts(in: householdId)
        return Dictionary(uniqueKeysWithValues: accounts.map { account in
            let total = financeMovements.filter { $0.accountId == account.id }.reduce(account.openingBalance.minor) { $0 + $1.amount.minor }
            return (account.id, Money(minor: total, currency: account.currency))
        })
    }

    public func createAccount(_ draft: AccountDraft, in householdId: UUID) async throws -> Account {
        _ = try requireMember(of: householdId)
        if let issue = draft.issue { throw AppError.invalidInput(issue) }
        if let owner = draft.ownerId, !isMember(owner, of: householdId) {
            throw AppError.invalidInput("Esa persona no es del hogar.")
        }
        let account = Account(householdId: householdId, name: draft.trimmedName, kind: draft.kind,
                              openingBalance: draft.openingBalance, ownerId: draft.ownerId)
        financeAccounts.append(account)
        return account
    }

    public func updateAccount(_ account: Account) async throws -> Account {
        guard let index = financeAccounts.firstIndex(where: { $0.id == account.id }) else { throw AppError.unknown("cuenta") }
        let householdId = financeAccounts[index].householdId
        _ = try requireMember(of: householdId)
        var updated = account
        updated.householdId = householdId
        financeAccounts[index] = updated
        return updated
    }

    public func deleteAccount(_ accountId: UUID) async throws {
        guard let account = financeAccounts.first(where: { $0.id == accountId }) else { return }
        _ = try requireMember(of: account.householdId)
        financeAccounts.removeAll { $0.id == accountId }
        let gone = Set(financeMovements.filter { $0.accountId == accountId }.map(\.id))
        financeMovements.removeAll { $0.accountId == accountId }
        creditCardList.removeAll { $0.accountId == accountId }
        installmentList.removeAll { $0.accountId == accountId || gone.contains($0.movementId) }
        for index in creditCardList.indices where creditCardList[index].payFromAccountId == accountId {
            creditCardList[index].payFromAccountId = nil
        }
    }

    public func categories(in householdId: UUID) async throws -> [BudgetCategory] {
        _ = try requireMember(of: householdId)
        return financeCategories.filter { $0.householdId == householdId }
    }

    public func createCategory(_ category: BudgetCategory) async throws -> BudgetCategory {
        _ = try requireMember(of: category.householdId)
        if let issue = category.issue(among: financeCategories) { throw AppError.invalidInput(issue) }
        var created = BudgetCategory(householdId: category.householdId, name: category.trimmedName, kind: category.kind,
                                     budgetGroup: category.budgetGroup, icon: category.icon)
        if created.kind != .expense { created.budgetGroup = nil }
        financeCategories.append(created)
        return created
    }

    public func updateCategory(_ category: BudgetCategory) async throws -> BudgetCategory {
        guard let index = financeCategories.firstIndex(where: { $0.id == category.id }) else { throw AppError.unknown("categoría") }
        let current = financeCategories[index]
        _ = try requireMember(of: current.householdId)
        var updated = current
        updated.name = category.trimmedName
        updated.budgetGroup = current.kind == .expense ? category.budgetGroup : nil
        updated.icon = category.icon
        if let issue = updated.issue(among: financeCategories) { throw AppError.invalidInput(issue) }
        financeCategories[index] = updated
        return updated
    }

    public func deleteCategory(_ categoryId: UUID) async throws {
        guard let category = financeCategories.first(where: { $0.id == categoryId }) else { return }
        _ = try requireMember(of: category.householdId)
        financeCategories.removeAll { $0.id == categoryId }
        for index in financeMovements.indices where financeMovements[index].categoryId == categoryId {
            financeMovements[index].categoryId = nil
        }
        for index in recurring.indices where recurring[index].categoryId == categoryId {
            recurring[index].categoryId = nil
        }
        for index in budgets.indices {
            budgets[index].limits[categoryId] = nil
        }
    }

    public func resetHousehold(_ householdId: UUID) async throws {
        _ = try requireMember(of: householdId)
        let holdingIds = Set(holdingList.filter { $0.householdId == householdId }.map(\.id))
        holdingPriceList.removeAll { holdingIds.contains($0.holdingId) }
        tradeList.removeAll { holdingIds.contains($0.holdingId) }
        planList.removeAll { holdingIds.contains($0.holdingId) }
        holdingList.removeAll { $0.householdId == householdId }
        creditCardList.removeAll { $0.householdId == householdId }
        installmentList.removeAll { $0.householdId == householdId }
        let goalIds = Set(goalList.filter { $0.householdId == householdId }.map(\.id))
        goalContributions.removeAll { goalIds.contains($0.goalId) }
        goalList.removeAll { $0.householdId == householdId }
        recurring.removeAll { $0.householdId == householdId }
        budgets.removeAll { $0.householdId == householdId }
        financeMovements.removeAll { $0.householdId == householdId }
        financeAccounts.removeAll { $0.householdId == householdId }
        financeCategories.removeAll { $0.householdId == householdId }
        financeCategories += BudgetCategory.defaults(for: householdId)
    }

    public func movements(in householdId: UUID, accountId: UUID?, limit: Int) async throws -> [Movement] {
        _ = try requireMember(of: householdId)
        return financeMovements
            .filter { $0.householdId == householdId && (accountId == nil || $0.accountId == accountId) }
            .sorted { $0.bookedOn > $1.bookedOn }
            .prefix(limit)
            .map { $0 }
    }

    public func allMovements(in householdId: UUID) async throws -> [Movement] {
        _ = try requireMember(of: householdId)
        return financeMovements.filter { $0.householdId == householdId }
    }

    private func validated(_ draft: MovementDraft, in householdId: UUID) throws -> Movement {
        if let issue = draft.issue { throw AppError.invalidInput(issue) }
        guard financeAccounts.contains(where: { $0.id == draft.accountId && $0.householdId == householdId }) else {
            throw AppError.unknown("cuenta de otro hogar")
        }
        if let category = draft.categoryId,
           !financeCategories.contains(where: { $0.id == category && $0.householdId == householdId }) {
            throw AppError.unknown("categoría de otro hogar")
        }
        return Movement(householdId: householdId, accountId: draft.accountId, categoryId: draft.categoryId,
                        bookedOn: draft.bookedOn, amount: draft.amount,
                        description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes: draft.notes, importHash: draft.importHash)
    }

    public func addMovement(_ draft: MovementDraft, in householdId: UUID) async throws -> Movement {
        _ = try requireMember(of: householdId)
        let movement = try validated(draft, in: householdId)
        financeMovements.append(movement)
        return movement
    }

    public func updateMovement(_ movement: Movement) async throws -> Movement {
        guard let index = financeMovements.firstIndex(where: { $0.id == movement.id }) else { throw AppError.unknown("movimiento") }
        let householdId = financeMovements[index].householdId
        _ = try requireMember(of: householdId)
        let draft = MovementDraft(accountId: movement.accountId, categoryId: movement.categoryId, bookedOn: movement.bookedOn,
                                  amount: movement.amount, description: movement.description, notes: movement.notes)
        var updated = try validated(draft, in: householdId)
        updated = Movement(id: movement.id, householdId: householdId, accountId: updated.accountId,
                           categoryId: updated.categoryId, bookedOn: updated.bookedOn, amount: updated.amount,
                           description: updated.description, notes: updated.notes,
                           importHash: financeMovements[index].importHash)
        financeMovements[index] = updated
        return updated
    }

    public func deleteMovement(_ movementId: UUID) async throws {
        guard let movement = financeMovements.first(where: { $0.id == movementId }) else { return }
        _ = try requireMember(of: movement.householdId)
        financeMovements.removeAll { $0.id == movementId }
        installmentList.removeAll { $0.movementId == movementId }
    }

    public func importMovements(_ drafts: [MovementDraft], in householdId: UUID) async throws -> ImportResult {
        _ = try requireMember(of: householdId)
        var inserted = 0
        var duplicates = 0
        for draft in drafts {
            let movement = try validated(draft, in: householdId)
            if let hash = movement.importHash,
               financeMovements.contains(where: { $0.accountId == movement.accountId && $0.importHash == hash }) {
                duplicates += 1
                continue
            }
            financeMovements.append(movement)
            inserted += 1
        }
        return ImportResult(inserted: inserted, duplicates: duplicates)
    }
}
