import Foundation

/// Inversiones en memoria, con las mismas reglas que el servidor: cada miembro ve y toca solo
/// lo suyo, cuentas propias y dueños del mismo hogar, y borrar un activo borra lo suyo.
extension InMemoryBackend: InvestmentService {
    @discardableResult
    private func requireInvestmentMember(of householdId: UUID, _ operation: String = #function) throws -> UUID {
        let user = try requireUser(operation)
        guard isMember(user, of: householdId) else { throw AppError.unknown("no es miembro") }
        return user
    }

    private func checkHoldingReferences(_ holding: Holding, in householdId: UUID, by user: UUID) throws {
        if let account = holding.accountId,
           !financeAccounts.contains(where: { $0.id == account && $0.householdId == householdId })
            || !isMine(account, in: householdId, user: user) {
            throw AppError.unknown("cuenta de otro hogar")
        }
        if let owner = holding.ownerId, !isMember(owner, of: householdId) {
            throw AppError.unknown("el dueño no es del hogar")
        }
    }

    private func holding(_ holdingId: UUID, in householdId: UUID, by user: UUID) throws -> Holding {
        guard let holding = holdingList.first(where: { $0.id == holdingId && $0.householdId == householdId }),
              isMine(holdingId, in: householdId, user: user) else {
            throw AppError.unknown("activo de otro hogar")
        }
        return holding
    }

    // MARK: Activos

    public func holdings(in householdId: UUID) async throws -> [Holding] {
        let user = try requireInvestmentMember(of: householdId)
        return holdingList.filter { $0.householdId == householdId && isMine($0.id, in: householdId, user: user) }
            .sorted { $0.trimmedName.localizedStandardCompare($1.trimmedName) == .orderedAscending }
    }

    public func createHolding(_ holding: Holding) async throws -> Holding {
        let user = try requireInvestmentMember(of: holding.householdId)
        if let issue = holding.issue { throw AppError.invalidInput(issue) }
        try checkHoldingReferences(holding, in: holding.householdId, by: user)
        // Repetir el alta solo vale con el mismo hogar, nombre y tipo.
        if let stored = try replayed(holdingList.first(where: { $0.id == holding.id }), by: user, same: {
            $0.householdId == holding.householdId && $0.name == holding.trimmedName && $0.kind == holding.kind
        }) { return stored }
        var saved = holding
        saved.name = holding.trimmedName
        saved.symbol = holding.trimmedSymbol
        saved.updatedAt = nextVersion()
        holdingList.append(saved)
        creators[saved.id] = user
        return saved
    }

    public func updateHolding(_ holding: Holding) async throws -> Holding {
        if let issue = holding.issue { throw AppError.invalidInput(issue) }
        guard let index = holdingList.firstIndex(where: { $0.id == holding.id }) else { throw AppError.movementChanged }
        let householdId = holdingList[index].householdId
        let user = try requireCurrent(holding.id, seen: holding.updatedAt, stored: holdingList[index].updatedAt, in: householdId)
        try checkHoldingReferences(holding, in: householdId, by: user)
        var saved = holding
        saved.householdId = householdId
        saved.currency = holdingList[index].currency
        saved.name = holding.trimmedName
        saved.symbol = holding.trimmedSymbol
        saved.updatedAt = nextVersion()
        holdingList[index] = saved
        return saved
    }

    public func deleteHolding(_ holdingId: UUID) async throws {
        guard let holding = holdingList.first(where: { $0.id == holdingId }) else { return }
        let user = try requireInvestmentMember(of: holding.householdId)
        guard isMine(holdingId, in: holding.householdId, user: user) else { return }
        holdingPriceList.removeAll { $0.holdingId == holdingId }
        tradeList.removeAll { $0.holdingId == holdingId }
        planList.removeAll { $0.holdingId == holdingId }
        holdingList.removeAll { $0.id == holdingId }
    }

    // MARK: Precios

    public func holdingPrices(in householdId: UUID) async throws -> [HoldingPrice] {
        let user = try requireInvestmentMember(of: householdId)
        return holdingPriceList.filter { $0.householdId == householdId && isMine($0.id, in: householdId, user: user) }.sorted { $0.pricedOn < $1.pricedOn }
    }

    public func recordPrice(_ price: Decimal, on day: CalendarDay, for holdingId: UUID) async throws -> Holding {
        guard let index = holdingList.firstIndex(where: { $0.id == holdingId }) else { throw AppError.unknown("no existe") }
        let holding = holdingList[index]
        let user = try requireInvestmentMember(of: holding.householdId)
        // Como el servidor: un activo ajeno no se ve.
        guard isMine(holdingId, in: holding.householdId, user: user) else { throw AppError.unknown("no existe") }
        if price < 0 { throw AppError.invalidInput("El precio no puede ser negativo.") }
        if let existing = holdingPriceList.firstIndex(where: { $0.holdingId == holdingId && $0.pricedOn == day }) {
            holdingPriceList[existing].price = price
        } else {
            let saved = HoldingPrice(householdId: holding.householdId, holdingId: holdingId, pricedOn: day, price: price)
            holdingPriceList.append(saved)
            creators[saved.id] = user
        }
        if holding.priceOn.map({ day >= $0 }) ?? true {
            holdingList[index].price = price
            holdingList[index].priceOn = day
            // Como el servidor: cambiar el precio del activo cambia su versión.
            holdingList[index].updatedAt = nextVersion()
        }
        return holdingList[index]
    }

    // MARK: Operaciones

    public func trades(in householdId: UUID) async throws -> [InvestmentTrade] {
        let user = try requireInvestmentMember(of: householdId)
        return tradeList.filter { $0.householdId == householdId && isMine($0.id, in: householdId, user: user) }.sorted { $0.tradedOn < $1.tradedOn }
    }

    public func addTrade(_ trade: InvestmentTrade, cash: TradeCash?) async throws -> InvestmentTrade {
        let user = try requireInvestmentMember(of: trade.householdId)
        _ = try holding(trade.holdingId, in: trade.householdId, by: user)
        if let stored = tradeList.first(where: { $0.id == trade.id }) {
            // Como el servidor: una operación ajena no se ve, así que ese id ya está usado.
            guard creators[stored.id] == user else { throw AppError.idUsedBySomeoneElse }
            // Como el servidor: repetirla solo vale con los mismos datos, también los del movimiento.
            let movement = tradeMovements[trade.id].flatMap { id in financeMovements.first { $0.id == id } }
            guard stored.holdingId == trade.holdingId, stored.tradedOn == trade.tradedOn, stored.side == trade.side,
                  stored.quantity == trade.quantity, stored.price == trade.price, stored.fee == trade.fee,
                  movement?.accountId == cash?.accountId, movement?.amount == cash?.amount else {
                throw AppError.invalidInput(TransferDraft.storedWithOtherData)
            }
            return stored
        }
        if let issue = trade.issue(given: tradeList) { throw AppError.invalidInput(issue) }
        if let cash {
            let movement = try validated(MovementDraft(accountId: cash.accountId, categoryId: cash.categoryId,
                                                       bookedOn: trade.tradedOn, amount: cash.amount,
                                                       description: cash.description), in: trade.householdId, by: user)
            // El movimiento pasa por el mismo punto de fallo que `addMovement`: si falla, tampoco
            // queda la operación, como la transacción del servidor.
            try throwIfInjected("addMovement(_:in:)")
            financeMovements.append(movement)
            creators[movement.id] = user
            tradeMovements[trade.id] = movement.id
        }
        tradeList.append(trade)
        creators[trade.id] = user
        return trade
    }

    public func deleteTrade(_ tradeId: UUID) async throws {
        guard let trade = tradeList.first(where: { $0.id == tradeId }) else { return }
        let user = try requireInvestmentMember(of: trade.householdId)
        guard isMine(tradeId, in: trade.householdId, user: user) else { return }
        if let issue = trade.deletionIssue(given: tradeList) { throw AppError.invalidInput(issue) }
        tradeList.removeAll { $0.id == tradeId }
    }

    // MARK: Planes

    public func investmentPlans(in householdId: UUID) async throws -> [InvestmentPlan] {
        let user = try requireInvestmentMember(of: householdId)
        return planList.filter { $0.householdId == householdId && isMine($0.id, in: householdId, user: user) }.sorted { $0.startsOn < $1.startsOn }
    }

    public func createPlan(_ plan: InvestmentPlan) async throws -> InvestmentPlan {
        let user = try requireInvestmentMember(of: plan.householdId)
        if let issue = plan.issue { throw AppError.invalidInput(issue) }
        _ = try holding(plan.holdingId, in: plan.householdId, by: user)
        if let account = plan.accountId,
           !financeAccounts.contains(where: { $0.id == account && $0.householdId == plan.householdId })
            || !isMine(account, in: plan.householdId, user: user) {
            throw AppError.unknown("cuenta de otro hogar")
        }
        // Repetir el alta solo vale con el mismo activo, importe y primer día.
        if let stored = try replayed(planList.first(where: { $0.id == plan.id }), by: user, same: {
            $0.holdingId == plan.holdingId && $0.amount.minor == plan.amount.minor && $0.startsOn == plan.startsOn
        }) { return stored }
        var saved = plan
        saved.updatedAt = nextVersion()
        planList.append(saved)
        creators[saved.id] = user
        return saved
    }

    public func updatePlan(_ plan: InvestmentPlan) async throws -> InvestmentPlan {
        if let issue = plan.issue { throw AppError.invalidInput(issue) }
        guard let index = planList.firstIndex(where: { $0.id == plan.id }) else { throw AppError.movementChanged }
        let original = planList[index]
        let user = try requireCurrent(plan.id, seen: plan.updatedAt, stored: original.updatedAt, in: original.householdId)
        if let account = plan.accountId,
           !financeAccounts.contains(where: { $0.id == account && $0.householdId == original.householdId })
            || !isMine(account, in: original.householdId, user: user) {
            throw AppError.unknown("cuenta de otro hogar")
        }
        var saved = plan
        saved.householdId = original.householdId
        saved.holdingId = original.holdingId
        saved.updatedAt = nextVersion()
        planList[index] = saved
        return saved
    }

    public func deletePlan(_ planId: UUID) async throws {
        guard let plan = planList.first(where: { $0.id == planId }) else { return }
        let user = try requireInvestmentMember(of: plan.householdId)
        guard isMine(planId, in: plan.householdId, user: user) else { return }
        planList.removeAll { $0.id == planId }
    }
}
