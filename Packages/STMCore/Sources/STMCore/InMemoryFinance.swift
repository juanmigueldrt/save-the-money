import Foundation

/// Cuentas y movimientos en memoria, con las mismas reglas que el RLS del servidor:
/// cada miembro ve y toca solo lo que ha creado, en los hogares de los que es miembro.
extension InMemoryBackend: FinanceService {
    private func requireMember(of householdId: UUID, _ operation: String = #function) throws -> UUID {
        let user = try requireUser(operation)
        guard isMember(user, of: householdId) else { throw AppError.unknown("no es miembro") }
        return user
    }

    public func accounts(in householdId: UUID) async throws -> [Account] {
        let user = try requireMember(of: householdId)
        return financeAccounts.filter { $0.householdId == householdId && isMine($0.id, in: householdId, user: user) }
    }

    public func balances(in householdId: UUID) async throws -> [UUID: Money] {
        let accounts = try await accounts(in: householdId)
        return Dictionary(uniqueKeysWithValues: accounts.map { account in
            let total = financeMovements.filter { $0.accountId == account.id }.reduce(account.openingBalance.minor) { $0 + $1.amount.minor }
            return (account.id, Money(minor: total, currency: account.currency))
        })
    }

    public func createAccount(_ draft: AccountDraft, in householdId: UUID) async throws -> Account {
        let user = try requireMember(of: householdId)
        if let issue = draft.issue { throw AppError.invalidInput(issue) }
        if let owner = draft.ownerId, !isMember(owner, of: householdId) {
            throw AppError.invalidInput("Esa persona no es del hogar.")
        }
        // Repetir el alta solo vale con el mismo hogar, nombre, tipo y saldo inicial.
        if let saved = try replayed(financeAccounts.first(where: { $0.id == draft.id }), by: user, same: {
            $0.householdId == householdId && $0.name == draft.trimmedName && $0.kind == draft.kind
                && $0.openingBalance.minor == draft.openingBalance.minor
        }) { return saved }
        let account = Account(id: draft.id, householdId: householdId, name: draft.trimmedName, kind: draft.kind,
                              openingBalance: draft.openingBalance, ownerId: draft.ownerId, updatedAt: nextVersion())
        financeAccounts.append(account)
        creators[account.id] = user
        return account
    }

    public func updateAccount(_ account: Account) async throws -> Account {
        guard let index = financeAccounts.firstIndex(where: { $0.id == account.id }) else { throw AppError.movementChanged }
        let householdId = financeAccounts[index].householdId
        let user = try requireCurrent(account.id, seen: account.updatedAt, stored: financeAccounts[index].updatedAt, in: householdId)
        var updated = account
        updated.householdId = householdId
        updated.updatedAt = nextVersion()
        if updated.isDefault && !updated.isArchived {
            // Como en la base de datos: sólo una predeterminada por persona. La que deja de serlo cambia de versión.
            for other in financeAccounts.indices
            where financeAccounts[other].id != account.id && creators[financeAccounts[other].id] == user
                && financeAccounts[other].isDefault {
                financeAccounts[other].isDefault = false
                financeAccounts[other].updatedAt = nextVersion()
            }
        }
        financeAccounts[index] = updated
        return updated
    }

    public func deleteAccount(_ accountId: UUID) async throws {
        guard let account = financeAccounts.first(where: { $0.id == accountId }) else { return }
        let user = try requireMember(of: account.householdId)
        guard isMine(accountId, in: account.householdId, user: user) else { return }
        financeAccounts.removeAll { $0.id == accountId }
        let gone = Set(financeMovements.filter { $0.accountId == accountId }.map(\.id))
        financeMovements.removeAll { $0.accountId == accountId }
        creditCardList.removeAll { $0.accountId == accountId }
        installmentList.removeAll { $0.accountId == accountId || gone.contains($0.movementId) }
        // Como `on delete set null` del servidor: lo que la usaba se queda sin cuenta y con versión nueva
        // (el disparador `touch_updated_at` también salta en ese cambio).
        for index in creditCardList.indices where creditCardList[index].payFromAccountId == accountId {
            creditCardList[index].payFromAccountId = nil
            creditCardList[index].updatedAt = nextVersion()
        }
        for index in recurring.indices where recurring[index].accountId == accountId {
            recurring[index].accountId = nil
            recurring[index].updatedAt = nextVersion()
        }
        for index in goalList.indices where goalList[index].accountId == accountId {
            goalList[index].accountId = nil
            goalList[index].updatedAt = nextVersion()
        }
        for index in holdingList.indices where holdingList[index].accountId == accountId {
            holdingList[index].accountId = nil
            holdingList[index].updatedAt = nextVersion()
        }
        for index in planList.indices where planList[index].accountId == accountId {
            planList[index].accountId = nil
            planList[index].updatedAt = nextVersion()
        }
    }

    public func categories(in householdId: UUID) async throws -> [BudgetCategory] {
        let user = try requireMember(of: householdId)
        return financeCategories.filter { $0.householdId == householdId && isMine($0.id, in: householdId, user: user) }
    }

    public func createCategory(_ category: BudgetCategory) async throws -> BudgetCategory {
        let user = try requireMember(of: category.householdId)
        // Como el índice único del servidor: el nombre no se repite entre las categorías propias.
        let own = financeCategories.filter { creators[$0.id] == user }
        if let issue = category.issue(among: own) { throw AppError.invalidInput(issue) }
        // Repetir el alta solo vale con el mismo hogar, nombre y tipo.
        if let stored = try replayed(financeCategories.first(where: { $0.id == category.id }), by: user, same: {
            $0.householdId == category.householdId && $0.name == category.trimmedName && $0.kind == category.kind
        }) { return stored }
        var created = BudgetCategory(id: category.id, householdId: category.householdId, name: category.trimmedName,
                                     kind: category.kind, budgetGroup: category.budgetGroup, icon: category.icon,
                                     updatedAt: nextVersion())
        if created.kind != .expense { created.budgetGroup = nil }
        financeCategories.append(created)
        creators[created.id] = user
        return created
    }

    public func updateCategory(_ category: BudgetCategory) async throws -> BudgetCategory {
        guard let index = financeCategories.firstIndex(where: { $0.id == category.id }) else { throw AppError.movementChanged }
        let current = financeCategories[index]
        let user = try requireCurrent(current.id, seen: category.updatedAt, stored: current.updatedAt, in: current.householdId)
        var updated = current
        updated.updatedAt = nextVersion()
        updated.name = category.trimmedName
        updated.budgetGroup = current.kind == .expense ? category.budgetGroup : nil
        updated.icon = category.icon
        if let issue = updated.issue(among: financeCategories.filter({ creators[$0.id] == user })) { throw AppError.invalidInput(issue) }
        financeCategories[index] = updated
        return updated
    }

    public func deleteCategory(_ categoryId: UUID) async throws {
        guard let category = financeCategories.first(where: { $0.id == categoryId }) else { return }
        let user = try requireMember(of: category.householdId)
        guard isMine(categoryId, in: category.householdId, user: user) else { return }
        financeCategories.removeAll { $0.id == categoryId }
        // Como `on delete set null` del servidor: sin categoría y con versión nueva.
        for index in financeMovements.indices where financeMovements[index].categoryId == categoryId {
            financeMovements[index].categoryId = nil
            financeMovements[index].updatedAt = nextVersion()
        }
        for index in recurring.indices where recurring[index].categoryId == categoryId {
            recurring[index].categoryId = nil
            recurring[index].updatedAt = nextVersion()
        }
        for owner in budgets.keys {
            for index in budgets[owner, default: []].indices {
                budgets[owner]?[index].limits[categoryId] = nil
            }
        }
    }

    /// Como el servidor: borra solo lo tuyo de ese hogar y te repone tus categorías de partida.
    public func resetHousehold(_ householdId: UUID) async throws {
        let user = try requireMember(of: householdId)
        let mine = { (id: UUID) in self.creators[id] == user }
        let holdingIds = Set(holdingList.filter { $0.householdId == householdId && mine($0.id) }.map(\.id))
        holdingPriceList.removeAll { holdingIds.contains($0.holdingId) }
        tradeList.removeAll { holdingIds.contains($0.holdingId) }
        planList.removeAll { holdingIds.contains($0.holdingId) }
        holdingList.removeAll { holdingIds.contains($0.id) }
        // Las condiciones de una tarjeta son de quien creó su cuenta.
        creditCardList.removeAll { $0.householdId == householdId && mine($0.accountId) }
        installmentList.removeAll { $0.householdId == householdId && mine($0.id) }
        let goalIds = Set(goalList.filter { $0.householdId == householdId && mine($0.id) }.map(\.id))
        goalContributions.removeAll { goalIds.contains($0.goalId) }
        goalList.removeAll { goalIds.contains($0.id) }
        recurring.removeAll { $0.householdId == householdId && mine($0.id) }
        chargeList.removeAll { $0.householdId == householdId && mine($0.id) }
        budgets[user]?.removeAll { $0.householdId == householdId }
        extraBudgetList.removeAll { $0.householdId == householdId && mine($0.id) }
        financeMovements.removeAll { $0.householdId == householdId && mine($0.id) }
        financeAccounts.removeAll { $0.householdId == householdId && mine($0.id) }
        financeCategories.removeAll { $0.householdId == householdId && mine($0.id) }
        seedCategories(in: householdId, for: user)
    }

    public func movements(in householdId: UUID, accountId: UUID?, limit: Int) async throws -> [Movement] {
        let user = try requireMember(of: householdId)
        return financeMovements
            .filter { $0.householdId == householdId && (accountId == nil || $0.accountId == accountId) && creators[$0.id] == user }
            .sorted { $0.bookedOn > $1.bookedOn }
            .prefix(limit)
            .map { $0 }
    }

    public func movements(in householdId: UUID, accountId: UUID?, search: MovementSearch?, after: Movement?,
                          limit: Int) async throws -> [Movement] {
        let user = try requireMember(of: householdId)
        // El mismo orden que el servidor: día y, dentro del día, id (como uuid de Postgres), de mayor a menor.
        func key(_ movement: Movement) -> (CalendarDay, String) { (movement.bookedOn, movement.id.uuidString.lowercased()) }
        return financeMovements
            .filter { $0.householdId == householdId && (accountId == nil || $0.accountId == accountId) && creators[$0.id] == user }
            .filter { search?.matches($0) ?? true }
            .filter { movement in after.map { key(movement) < key($0) } ?? true }
            .sorted { key($0) > key($1) }
            .prefix(limit)
            .map { $0 }
    }

    public func movements(in householdId: UUID, ids: [UUID]) async throws -> [Movement] {
        let user = try requireMember(of: householdId)
        return financeMovements.filter { $0.householdId == householdId && ids.contains($0.id) && creators[$0.id] == user }
    }

    public func movements(in householdId: UUID, accountId: UUID, since: CalendarDay, limit: Int) async throws -> [Movement] {
        let user = try requireMember(of: householdId)
        return financeMovements
            .filter { $0.householdId == householdId && $0.accountId == accountId && $0.bookedOn >= since && creators[$0.id] == user }
            .sorted { $0.bookedOn > $1.bookedOn }
            .prefix(limit)
            .map { $0 }
    }

    public func allMovements(in householdId: UUID) async throws -> [Movement] {
        let user = try requireMember(of: householdId)
        return financeMovements.filter { $0.householdId == householdId && creators[$0.id] == user }
    }

    /// La cuenta y la categoría tienen que ser de `user` y de ese hogar, como pide el RLS al apuntar.
    func validated(_ draft: MovementDraft, in householdId: UUID, by user: UUID) throws -> Movement {
        if let issue = draft.issue { throw AppError.invalidInput(issue) }
        guard financeAccounts.contains(where: { $0.id == draft.accountId && $0.householdId == householdId }),
              isMine(draft.accountId, in: householdId, user: user) else {
            throw AppError.unknown("cuenta de otro hogar")
        }
        if let category = draft.categoryId,
           !financeCategories.contains(where: { $0.id == category && $0.householdId == householdId })
            || !isMine(category, in: householdId, user: user) {
            throw AppError.unknown("categoría de otro hogar")
        }
        movementVersion += 1
        return Movement(id: draft.id, householdId: householdId, accountId: draft.accountId, categoryId: draft.categoryId,
                        bookedOn: draft.bookedOn, amount: draft.amount,
                        description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes: draft.notes, importHash: draft.importHash, excluded: draft.excluded,
                        payee: Payee.clean(draft.payee), tags: draft.tags, updatedAt: "v\(movementVersion)")
    }

    public func addMovement(_ draft: MovementDraft, in householdId: UUID) async throws -> Movement {
        let user = try requireMember(of: householdId)
        let movement = try validated(draft, in: householdId, by: user)
        if let stored = financeMovements.first(where: { $0.id == draft.id }) {
            // Como el servidor: un id que ya usó otra persona no se ve, así que no vale.
            guard creators[stored.id] == user else { throw AppError.idUsedBySomeoneElse }
            // Repetirlo solo vale con la misma cuenta, importe y día.
            guard stored.householdId == householdId, stored.accountId == movement.accountId,
                  stored.amount == movement.amount, stored.bookedOn == movement.bookedOn else {
                throw AppError.invalidInput(TransferDraft.storedWithOtherData)
            }
            return stored
        }
        financeMovements.append(movement)
        creators[movement.id] = user
        return movement
    }

    public func addTransfer(_ transfer: TransferDraft, in householdId: UUID) async throws -> [Movement] {
        let user = try requireMember(of: householdId)
        if let issue = transfer.issue { throw AppError.invalidInput(issue) }
        if let stored = transferLegs[transfer.id] {
            // Como el servidor: si las patas son de otra persona, ese id ya está usado.
            guard stored.allSatisfy({ creators[$0] == user }) else { throw AppError.idUsedBySomeoneElse }
            let legs = financeMovements.filter { stored.contains($0.id) }
            // Repetirla solo vale con las mismas cuentas, importe y día.
            guard legs.map(\.accountId) == [transfer.fromAccountId, transfer.toAccountId],
                  legs.map(\.amount) == [-transfer.amount, transfer.amount],
                  legs.allSatisfy({ $0.bookedOn == transfer.bookedOn }) else {
                throw AppError.invalidInput(TransferDraft.storedWithOtherData)
            }
            return legs
        }
        let legs = try transfer.legs.map {
            var leg = try validated($0, in: householdId, by: user)
            leg.transferId = transfer.id
            return leg
        }
        // Cada pata pasa por el mismo punto de fallo que `addMovement`: si falla la segunda,
        // se deshace la primera, como la transacción del servidor.
        let before = financeMovements
        do {
            for leg in legs {
                try throwIfInjected("addMovement(_:in:)")
                financeMovements.append(leg)
            }
        } catch {
            financeMovements = before
            throw error
        }
        for leg in legs { creators[leg.id] = user }
        transferLegs[transfer.id] = legs.map(\.id)
        return legs
    }

    public func updateMovement(_ movement: Movement) async throws -> Movement {
        // Como el servidor: un movimiento borrado, ajeno o en otra versión que la leída no se cambia.
        guard let index = financeMovements.firstIndex(where: { $0.id == movement.id }) else { throw AppError.movementChanged }
        let householdId = financeMovements[index].householdId
        let user = try requireMember(of: householdId)
        guard isMine(movement.id, in: householdId, user: user),
              movement.updatedAt == financeMovements[index].updatedAt else { throw AppError.movementChanged }
        let draft = MovementDraft(accountId: movement.accountId, categoryId: movement.categoryId, bookedOn: movement.bookedOn,
                                  amount: movement.amount, description: movement.description, notes: movement.notes,
                                  excluded: movement.excluded, payee: movement.payee, tags: movement.tags)
        var updated = try validated(draft, in: householdId, by: user)
        updated = Movement(id: movement.id, householdId: householdId, accountId: updated.accountId,
                           categoryId: updated.categoryId, bookedOn: updated.bookedOn, amount: updated.amount,
                           description: updated.description, notes: updated.notes,
                           importHash: financeMovements[index].importHash, excluded: updated.excluded,
                           reviewedAt: movement.reviewedAt, payee: updated.payee, tags: updated.tags,
                           updatedAt: updated.updatedAt, transferId: financeMovements[index].transferId)
        if let transferId = updated.transferId {
            try keepTransferLegsTogether(updated, transferId: transferId, before: financeMovements[index], user: user)
        }
        financeMovements[index] = updated
        return updated
    }

    /// Como el trigger del servidor: el importe y el día de una pata cambian también en la otra.
    private func keepTransferLegsTogether(_ updated: Movement, transferId: UUID, before: Movement, user: UUID) throws {
        let invalid = AppError.invalidInput("Algún dato no es válido. Revisa el formulario.")
        // La salida sigue siendo negativa y la entrada positiva.
        guard updated.amount.isNegative == before.amount.isNegative else { throw invalid }
        // Si la otra pata ya no existe, la que queda es un movimiento normal.
        guard let pair = financeMovements.firstIndex(where: { $0.transferId == transferId && $0.id != updated.id }) else { return }
        guard financeMovements[pair].accountId != updated.accountId else { throw invalid }
        guard financeMovements[pair].amount != -updated.amount || financeMovements[pair].bookedOn != updated.bookedOn else { return }
        guard isMine(financeMovements[pair].id, in: updated.householdId, user: user) else {
            throw AppError.invalidInput(TransferDraft.otherLegLocked)
        }
        movementVersion += 1
        financeMovements[pair].amount = -updated.amount
        financeMovements[pair].bookedOn = updated.bookedOn
        financeMovements[pair].updatedAt = "v\(movementVersion)"
    }

    public func deleteMovement(_ movementId: UUID) async throws {
        guard let movement = financeMovements.first(where: { $0.id == movementId }) else { return }
        let user = try requireMember(of: movement.householdId)
        guard isMine(movementId, in: movement.householdId, user: user) else { return }
        financeMovements.removeAll { $0.id == movementId }
        installmentList.removeAll { $0.movementId == movementId }
        for index in chargeList.indices where chargeList[index].transactionId == movementId {
            chargeList[index].transactionId = nil
        }
    }

    public func deleteTransfer(_ transferId: UUID) async throws {
        let user = try requireUser()
        let legs = Set(financeMovements.filter { $0.transferId == transferId }.map(\.id))
        // Como el servidor: o se borran todas las patas o ninguna.
        for leg in financeMovements where legs.contains(leg.id) {
            guard isMine(leg.id, in: leg.householdId, user: user) else { throw AppError.invalidInput(TransferDraft.otherLegLocked) }
        }
        financeMovements.removeAll { legs.contains($0.id) }
        installmentList.removeAll { legs.contains($0.movementId) }
        for index in chargeList.indices where chargeList[index].transactionId.map(legs.contains) == true {
            chargeList[index].transactionId = nil
        }
    }

    public func importMovements(_ drafts: [MovementDraft], in householdId: UUID) async throws -> ImportResult {
        let user = try requireMember(of: householdId)
        var inserted = 0
        var duplicates = 0
        for draft in drafts {
            let movement = try validated(draft, in: householdId, by: user)
            if let hash = movement.importHash,
               financeMovements.contains(where: { $0.accountId == movement.accountId && $0.importHash == hash }) {
                duplicates += 1
                continue
            }
            financeMovements.append(movement)
            creators[movement.id] = user
            inserted += 1
        }
        return ImportResult(inserted: inserted, duplicates: duplicates)
    }
}

extension AppError {
    /// Lo que devuelve la app ante el 23505 del servidor: ese id ya lo usó otra persona.
    static let idUsedBySomeoneElse = AppError.invalidInput("Ya hay un registro igual guardado. Revisa el formulario.")
}
