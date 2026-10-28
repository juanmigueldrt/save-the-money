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
        financeMovements.removeAll { $0.accountId == accountId }
    }

    public func categories(in householdId: UUID) async throws -> [BudgetCategory] {
        _ = try requireMember(of: householdId)
        return financeCategories.filter { $0.householdId == householdId }
    }

    public func movements(in householdId: UUID, accountId: UUID?, limit: Int) async throws -> [Movement] {
        _ = try requireMember(of: householdId)
        return financeMovements
            .filter { $0.householdId == householdId && (accountId == nil || $0.accountId == accountId) }
            .sorted { $0.bookedOn > $1.bookedOn }
            .prefix(limit)
            .map { $0 }
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
