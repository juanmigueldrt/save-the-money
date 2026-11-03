import Foundation

/// Inversiones en memoria, con las mismas reglas que el servidor: sólo los miembros
/// del hogar, cuentas y dueños del mismo hogar, y borrar un activo borra lo suyo.
extension InMemoryBackend: InvestmentService {
    private func requireInvestmentMember(of householdId: UUID) throws {
        let user = try requireUser()
        guard isMember(user, of: householdId) else { throw AppError.unknown("no es miembro") }
    }

    private func checkHoldingReferences(_ holding: Holding, in householdId: UUID) throws {
        if let account = holding.accountId,
           !financeAccounts.contains(where: { $0.id == account && $0.householdId == householdId }) {
            throw AppError.unknown("cuenta de otro hogar")
        }
        if let owner = holding.ownerId, !isMember(owner, of: householdId) {
            throw AppError.unknown("el dueño no es del hogar")
        }
    }

    private func holding(_ holdingId: UUID, in householdId: UUID) throws -> Holding {
        guard let holding = holdingList.first(where: { $0.id == holdingId && $0.householdId == householdId }) else {
            throw AppError.unknown("activo de otro hogar")
        }
        return holding
    }

    // MARK: Activos

    public func holdings(in householdId: UUID) async throws -> [Holding] {
        try requireInvestmentMember(of: householdId)
        return holdingList.filter { $0.householdId == householdId }
            .sorted { $0.trimmedName.localizedStandardCompare($1.trimmedName) == .orderedAscending }
    }

    public func createHolding(_ holding: Holding) async throws -> Holding {
        try requireInvestmentMember(of: holding.householdId)
        if let issue = holding.issue { throw AppError.invalidInput(issue) }
        try checkHoldingReferences(holding, in: holding.householdId)
        var saved = holding
        saved.name = holding.trimmedName
        saved.symbol = holding.trimmedSymbol
        holdingList.append(saved)
        return saved
    }

    public func updateHolding(_ holding: Holding) async throws -> Holding {
        guard let index = holdingList.firstIndex(where: { $0.id == holding.id }) else { throw AppError.unknown("no existe") }
        let householdId = holdingList[index].householdId
        try requireInvestmentMember(of: householdId)
        if let issue = holding.issue { throw AppError.invalidInput(issue) }
        try checkHoldingReferences(holding, in: householdId)
        var saved = holding
        saved.householdId = householdId
        saved.currency = holdingList[index].currency
        saved.name = holding.trimmedName
        saved.symbol = holding.trimmedSymbol
        holdingList[index] = saved
        return saved
    }

    public func deleteHolding(_ holdingId: UUID) async throws {
        guard let holding = holdingList.first(where: { $0.id == holdingId }) else { return }
        try requireInvestmentMember(of: holding.householdId)
        holdingPriceList.removeAll { $0.holdingId == holdingId }
        tradeList.removeAll { $0.holdingId == holdingId }
        planList.removeAll { $0.holdingId == holdingId }
        holdingList.removeAll { $0.id == holdingId }
    }

    // MARK: Precios

    public func holdingPrices(in householdId: UUID) async throws -> [HoldingPrice] {
        try requireInvestmentMember(of: householdId)
        return holdingPriceList.filter { $0.householdId == householdId }.sorted { $0.pricedOn < $1.pricedOn }
    }

    public func recordPrice(_ price: Decimal, on day: CalendarDay, for holdingId: UUID) async throws -> Holding {
        guard let index = holdingList.firstIndex(where: { $0.id == holdingId }) else { throw AppError.unknown("no existe") }
        let holding = holdingList[index]
        try requireInvestmentMember(of: holding.householdId)
        if price < 0 { throw AppError.invalidInput("El precio no puede ser negativo.") }
        if let existing = holdingPriceList.firstIndex(where: { $0.holdingId == holdingId && $0.pricedOn == day }) {
            holdingPriceList[existing].price = price
        } else {
            holdingPriceList.append(HoldingPrice(householdId: holding.householdId, holdingId: holdingId,
                                                 pricedOn: day, price: price))
        }
        if holding.priceOn.map({ day >= $0 }) ?? true {
            holdingList[index].price = price
            holdingList[index].priceOn = day
        }
        return holdingList[index]
    }

    // MARK: Operaciones

    public func trades(in householdId: UUID) async throws -> [InvestmentTrade] {
        try requireInvestmentMember(of: householdId)
        return tradeList.filter { $0.householdId == householdId }.sorted { $0.tradedOn < $1.tradedOn }
    }

    public func addTrade(_ trade: InvestmentTrade) async throws -> InvestmentTrade {
        try requireInvestmentMember(of: trade.householdId)
        _ = try holding(trade.holdingId, in: trade.householdId)
        if let issue = trade.issue(given: tradeList) { throw AppError.invalidInput(issue) }
        tradeList.append(trade)
        return trade
    }

    public func deleteTrade(_ tradeId: UUID) async throws {
        guard let trade = tradeList.first(where: { $0.id == tradeId }) else { return }
        try requireInvestmentMember(of: trade.householdId)
        tradeList.removeAll { $0.id == tradeId }
    }

    // MARK: Planes

    public func investmentPlans(in householdId: UUID) async throws -> [InvestmentPlan] {
        try requireInvestmentMember(of: householdId)
        return planList.filter { $0.householdId == householdId }.sorted { $0.startsOn < $1.startsOn }
    }

    public func createPlan(_ plan: InvestmentPlan) async throws -> InvestmentPlan {
        try requireInvestmentMember(of: plan.householdId)
        if let issue = plan.issue { throw AppError.invalidInput(issue) }
        _ = try holding(plan.holdingId, in: plan.householdId)
        if let account = plan.accountId,
           !financeAccounts.contains(where: { $0.id == account && $0.householdId == plan.householdId }) {
            throw AppError.unknown("cuenta de otro hogar")
        }
        planList.append(plan)
        return plan
    }

    public func updatePlan(_ plan: InvestmentPlan) async throws -> InvestmentPlan {
        guard let index = planList.firstIndex(where: { $0.id == plan.id }) else { throw AppError.unknown("no existe") }
        let original = planList[index]
        try requireInvestmentMember(of: original.householdId)
        if let issue = plan.issue { throw AppError.invalidInput(issue) }
        if let account = plan.accountId,
           !financeAccounts.contains(where: { $0.id == account && $0.householdId == original.householdId }) {
            throw AppError.unknown("cuenta de otro hogar")
        }
        var saved = plan
        saved.householdId = original.householdId
        saved.holdingId = original.holdingId
        planList[index] = saved
        return saved
    }

    public func deletePlan(_ planId: UUID) async throws {
        guard let plan = planList.first(where: { $0.id == planId }) else { return }
        try requireInvestmentMember(of: plan.householdId)
        planList.removeAll { $0.id == planId }
    }
}
