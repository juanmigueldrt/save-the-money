import Foundation
import STMCore
import Supabase

/// Inversiones sobre Supabase. El RLS sólo deja ver y tocar las del hogar; las claves
/// foráneas compuestas impiden enlazar cuentas o activos de otro hogar.
extension SupabaseBackend: InvestmentService {
    private static let holdingColumns = "id,household_id,name,symbol,kind,asset_class,currency,account_id,owner_id,price,price_on,fee_rate,note,archived_at"
    private static let priceColumns = "id,household_id,holding_id,priced_on,price"
    private static let tradeColumns = "id,household_id,holding_id,traded_on,side,quantity,price,fee_minor,note"
    private static let planColumns = "id,household_id,holding_id,account_id,amount_minor,every,unit,starts_on,ends_on,expected_annual_return,remind_days_before,paused_at,archived_at"

    // MARK: Activos

    public func holdings(in householdId: UUID) async throws -> [Holding] {
        try await mapped {
            try await client.from("holdings")
                .select(Self.holdingColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("name")
                .execute()
                .value
        }
    }

    public func createHolding(_ holding: Holding) async throws -> Holding {
        if let issue = holding.issue { throw AppError.invalidInput(issue) }
        let row = NewRow(householdId: holding.householdId, fields: holding)
        return try await mapped {
            try await client.from("holdings")
                .insert(row)
                .select(Self.holdingColumns)
                .single()
                .execute()
                .value
        }
    }

    public func updateHolding(_ holding: Holding) async throws -> Holding {
        if let issue = holding.issue { throw AppError.invalidInput(issue) }
        return try await mapped {
            try await client.from("holdings")
                .update(holding)
                .eq("id", value: holding.id.uuidString)
                .select(Self.holdingColumns)
                .single()
                .execute()
                .value
        }
    }

    public func deleteHolding(_ holdingId: UUID) async throws {
        try await mapped {
            try await client.from("holdings").delete().eq("id", value: holdingId.uuidString).execute()
        }
    }

    // MARK: Precios

    public func holdingPrices(in householdId: UUID) async throws -> [HoldingPrice] {
        try await allRows(of: "holding_prices", columns: Self.priceColumns, householdId: householdId, orderedBy: "priced_on")
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
        try await allRows(of: "investment_trades", columns: Self.tradeColumns, householdId: householdId, orderedBy: "traded_on")
    }

    /// `create_trade` guarda la operación y su movimiento en una sola transacción y no repite una ya guardada.
    /// Que haya participaciones para vender lo comprueba el servidor, con todas las operaciones del activo.
    public func addTrade(_ trade: InvestmentTrade, cash: TradeCash?) async throws -> InvestmentTrade {
        if let issue = trade.issue { throw AppError.invalidInput(issue) }
        if let cash, let issue = MovementDraft(accountId: cash.accountId, bookedOn: trade.tradedOn, amount: cash.amount,
                                               description: cash.description).issue {
            throw AppError.invalidInput(issue)
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
        try await mapped {
            try await client.from("investment_plans")
                .select(Self.planColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("starts_on")
                .execute()
                .value
        }
    }

    public func createPlan(_ plan: InvestmentPlan) async throws -> InvestmentPlan {
        if let issue = plan.issue { throw AppError.invalidInput(issue) }
        let row = NewRow(householdId: plan.householdId, fields: NewPlan(holdingId: plan.holdingId, plan: plan))
        return try await mapped {
            try await client.from("investment_plans")
                .insert(row)
                .select(Self.planColumns)
                .single()
                .execute()
                .value
        }
    }

    public func updatePlan(_ plan: InvestmentPlan) async throws -> InvestmentPlan {
        if let issue = plan.issue { throw AppError.invalidInput(issue) }
        return try await mapped {
            try await client.from("investment_plans")
                .update(plan)
                .eq("id", value: plan.id.uuidString)
                .select(Self.planColumns)
                .single()
                .execute()
                .value
        }
    }

    public func deletePlan(_ planId: UUID) async throws {
        try await mapped {
            try await client.from("investment_plans").delete().eq("id", value: planId.uuidString).execute()
        }
    }

    // MARK: Paginación

    /// Todas las filas del hogar, de 1000 en 1000 (el máximo que devuelve el servidor por petición).
    private func allRows<Row: Decodable & Sendable>(of table: String, columns: String, householdId: UUID,
                                                    orderedBy column: String) async throws -> [Row] {
        let pageSize = 1000
        var all: [Row] = []
        while true {
            let start = all.count
            let page: [Row] = try await mapped {
                try await client.from(table)
                    .select(columns)
                    .eq("household_id", value: householdId.uuidString)
                    .order(column)
                    .order("id")
                    .range(from: start, to: start + pageSize - 1)
                    .execute()
                    .value
            }
            all += page
            if page.count < pageSize { return all }
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

/// Un plan nuevo: sus columnas editables más el activo, que ya no se puede cambiar.
private struct NewPlan: Encodable, Sendable {
    var holdingId: UUID
    var plan: InvestmentPlan

    private enum CodingKeys: String, CodingKey { case holdingId = "holding_id" }

    func encode(to encoder: Encoder) throws {
        try plan.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(holdingId, forKey: .holdingId)
    }
}
