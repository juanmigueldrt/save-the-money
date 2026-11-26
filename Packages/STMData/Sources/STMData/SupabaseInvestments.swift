import Foundation
import STMCore
import Supabase

/// Inversiones sobre Supabase. El RLS sólo deja ver y tocar las del hogar; las claves
/// foráneas compuestas impiden enlazar cuentas o activos de otro hogar.
extension SupabaseBackend: InvestmentService {
    private static let holdingColumns = "id,household_id,name,symbol,kind,asset_class,currency,account_id,owner_id,price,price_on,fee_rate,note,archived_at,updated_at"
    private static let priceColumns = "id,household_id,holding_id,priced_on,price"
    private static let tradeColumns = "id,household_id,holding_id,traded_on,side,quantity,price,fee_minor,note"
    private static let planColumns = "id,household_id,holding_id,account_id,amount_minor,every,unit,starts_on,ends_on,expected_annual_return,remind_days_before,paused_at,archived_at,updated_at"

    // MARK: Activos

    public func holdings(in householdId: UUID) async throws -> [Holding] {
        try await allRows {
            client.from("holdings")
                .select(Self.holdingColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("name")
                .order("id")
        }
    }

    public func createHolding(_ holding: Holding) async throws -> Holding {
        if let issue = holding.issue { throw AppError.validation(.holding(issue)) }
        return try await saved(Self.createHoldingCall(holding), columns: Self.holdingColumns)
    }

    public func updateHolding(_ holding: Holding) async throws -> Holding {
        if let issue = holding.issue { throw AppError.validation(.holding(issue)) }
        return try await saved(Self.updateHoldingCall(holding), columns: Self.holdingColumns)
    }

    static func createHoldingCall(_ holding: Holding) -> RpcCall {
        var params = holdingParams(holding)
        params["household"] = .uuid(holding.householdId)
        return RpcCall(function: "create_holding", params: params)
    }

    static func updateHoldingCall(_ holding: Holding) -> RpcCall {
        var params = holdingParams(holding)
        params["seen"] = .text(holding.updatedAt)
        return RpcCall(function: "update_holding", params: params)
    }

    /// Lo que comparten `create_holding` y `update_holding`. La moneda no va: la pone el servidor al crear.
    private static func holdingParams(_ holding: Holding) -> [String: AnyJSON] {
        ["holding": .uuid(holding.id), "label": .string(holding.trimmedName), "ticker": .text(holding.trimmedSymbol),
         "holding_kind": .string(holding.kind.rawValue), "asset": .string(holding.assetClass.rawValue),
         "account": .uuid(holding.accountId), "owner": .uuid(holding.ownerId), "unit_price": .decimal(holding.price),
         "priced": .day(holding.priceOn), "fee": .decimal(holding.feeRate), "remark": .text(holding.note),
         "archived": .timestamp(holding.archivedAt)]
    }

    public func deleteHolding(_ holdingId: UUID) async throws {
        try await mapped {
            try await client.from("holdings").delete().eq("id", value: holdingId.uuidString).execute()
        }
    }

    // MARK: Precios

    public func holdingPrices(in householdId: UUID) async throws -> [HoldingPrice] {
        try await allRows {
            client.from("holding_prices")
                .select(Self.priceColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("priced_on")
                .order("id")
        }
    }

    /// `record_holding_price` apunta el precio del día y el precio actual del activo en una sola transacción.
    public func recordPrice(_ price: Decimal, on day: CalendarDay, for holdingId: UUID) async throws -> Holding {
        if price < 0 { throw AppError.invalidInput("El precio no puede ser negativo.") }
        let rows: [Holding] = try await mapped {
            try await client.rpc("record_holding_price", params: PriceParams(holding: holdingId, priced: day, newPrice: price))
                .select(Self.holdingColumns)
                .execute()
                .value
        }
        guard let saved = rows.first else { throw AppError.unknown("record_holding_price") }
        return saved
    }

    // MARK: Operaciones

    public func trades(in householdId: UUID) async throws -> [InvestmentTrade] {
        try await allRows {
            client.from("investment_trades")
                .select(Self.tradeColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("traded_on")
                .order("id")
        }
    }

    /// `create_trade` guarda la operación y su movimiento en una sola transacción y no repite una ya guardada.
    /// Que haya participaciones para vender lo comprueba el servidor, con todas las operaciones del activo.
    public func addTrade(_ trade: InvestmentTrade, cash: TradeCash?) async throws -> InvestmentTrade {
        if let issue = trade.issue { throw AppError.validation(.trade(issue)) }
        if let cash, let issue = MovementDraft(accountId: cash.accountId, bookedOn: trade.tradedOn, amount: cash.amount,
                                               description: cash.description).issue {
            throw AppError.validation(.movement(issue))
        }
        let rows: [InvestmentTrade] = try await mapped {
            try await client.rpc("create_trade", params: TradeParams(trade: trade, cash: cash))
                .select(Self.tradeColumns)
                .execute()
                .value
        }
        guard let saved = rows.first else { throw AppError.unknown("create_trade") }
        return saved
    }

    public func deleteTrade(_ tradeId: UUID) async throws {
        try await mapped {
            try await client.from("investment_trades").delete().eq("id", value: tradeId.uuidString).execute()
        }
    }

    // MARK: Planes

    public func investmentPlans(in householdId: UUID) async throws -> [InvestmentPlan] {
        try await allRows {
            client.from("investment_plans")
                .select(Self.planColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("starts_on")
                .order("id")
        }
    }

    public func createPlan(_ plan: InvestmentPlan) async throws -> InvestmentPlan {
        if let issue = plan.issue { throw AppError.validation(.plan(issue)) }
        return try await saved(Self.createPlanCall(plan), columns: Self.planColumns)
    }

    public func updatePlan(_ plan: InvestmentPlan) async throws -> InvestmentPlan {
        if let issue = plan.issue { throw AppError.validation(.plan(issue)) }
        return try await saved(Self.updatePlanCall(plan), columns: Self.planColumns)
    }

    static func createPlanCall(_ plan: InvestmentPlan) -> RpcCall {
        var params = planParams(plan)
        params["household"] = .uuid(plan.householdId)
        params["holding"] = .uuid(plan.holdingId)
        return RpcCall(function: "create_investment_plan", params: params)
    }

    static func updatePlanCall(_ plan: InvestmentPlan) -> RpcCall {
        var params = planParams(plan)
        params["seen"] = .text(plan.updatedAt)
        return RpcCall(function: "update_investment_plan", params: params)
    }

    /// Lo que comparten `create_investment_plan` y `update_investment_plan`. El activo de un plan no se cambia.
    private static func planParams(_ plan: InvestmentPlan) -> [String: AnyJSON] {
        ["plan": .uuid(plan.id), "account": .uuid(plan.accountId), "amount": .integer(plan.amount.minor),
         "step": .integer(plan.recurrence.every), "step_unit": .string(plan.recurrence.unit.rawValue),
         "starts": .day(plan.startsOn), "ends": .day(plan.endsOn), "annual_return": .decimal(plan.expectedAnnualReturn),
         "remind_days": .int(plan.remindDaysBefore), "paused": .timestamp(plan.pausedAt),
         "archived": .timestamp(plan.archivedAt)]
    }

    public func deletePlan(_ planId: UUID) async throws {
        try await mapped {
            try await client.from("investment_plans").delete().eq("id", value: planId.uuidString).execute()
        }
    }
}

/// Parámetros de `record_holding_price`.
private struct PriceParams: Encodable, Sendable {
    var holding: UUID
    var priced: CalendarDay
    var newPrice: Decimal

    private enum CodingKeys: String, CodingKey {
        case holding, priced
        case newPrice = "new_price"
    }
}

/// Parámetros de `create_trade`. Sin `cash` van nulos los cuatro del movimiento.
private struct TradeParams: Encodable, Sendable {
    var trade: InvestmentTrade
    var cash: TradeCash?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(trade.id, forKey: .trade)
        try c.encode(trade.householdId, forKey: .household)
        try c.encode(trade.holdingId, forKey: .holding)
        try c.encode(trade.tradedOn, forKey: .traded)
        try c.encode(trade.side, forKey: .tradeSide)
        try c.encode(trade.quantity, forKey: .shares)
        try c.encode(trade.price, forKey: .unitPrice)
        try c.encode(trade.fee.minor, forKey: .fee)
        try c.encode(trade.note, forKey: .tradeNote)
        try c.encode(cash?.accountId, forKey: .account)
        try c.encode(cash?.categoryId, forKey: .category)
        try c.encode(cash?.amount.minor, forKey: .cash)
        try c.encode(cash?.description.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .label)
    }

    private enum CodingKeys: String, CodingKey {
        case trade, household, holding, traded, shares, fee, account, category, cash, label
        case tradeSide = "trade_side"
        case unitPrice = "unit_price"
        case tradeNote = "trade_note"
    }
}
