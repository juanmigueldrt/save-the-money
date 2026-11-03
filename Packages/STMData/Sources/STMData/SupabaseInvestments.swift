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

    public func recordPrice(_ price: Decimal, on day: CalendarDay, for holdingId: UUID) async throws -> Holding {
        if price < 0 { throw AppError.invalidInput("El precio no puede ser negativo.") }
        let holding: Holding = try await mapped {
            try await client.from("holdings")
                .select(Self.holdingColumns)
                .eq("id", value: holdingId.uuidString)
                .single()
                .execute()
                .value
        }
        // No se usa upsert: haría UPDATE de columnas que no se pueden cambiar (hogar, activo, día).
        let updated: [HoldingPrice] = try await mapped {
            try await client.from("holding_prices")
                .update(PriceUpdate(price: price))
                .eq("holding_id", value: holdingId.uuidString)
                .eq("priced_on", value: day.iso)
                .select(Self.priceColumns)
                .execute()
                .value
        }
        if updated.isEmpty {
            let row = HoldingPrice(householdId: holding.householdId, holdingId: holdingId, pricedOn: day, price: price)
            try await mapped {
                try await client.from("holding_prices").insert(row).execute()
            }
        }
        guard holding.priceOn.map({ day >= $0 }) ?? true else { return holding }
        return try await mapped {
            try await client.from("holdings")
                .update(CurrentPrice(price: price, priceOn: day))
                .eq("id", value: holdingId.uuidString)
                .select(Self.holdingColumns)
                .single()
                .execute()
                .value
        }
    }

    // MARK: Operaciones

    public func trades(in householdId: UUID) async throws -> [InvestmentTrade] {
        try await allRows(of: "investment_trades", columns: Self.tradeColumns, householdId: householdId, orderedBy: "traded_on")
    }

    public func addTrade(_ trade: InvestmentTrade) async throws -> InvestmentTrade {
        if trade.side == .sell {
            let others: [InvestmentTrade] = try await mapped {
                try await client.from("investment_trades")
                    .select(Self.tradeColumns)
                    .eq("holding_id", value: trade.holdingId.uuidString)
                    .execute()
                    .value
            }
            if let issue = trade.issue(given: others) { throw AppError.invalidInput(issue) }
        } else if let issue = trade.issue {
            throw AppError.invalidInput(issue)
        }
        return try await mapped {
            try await client.from("investment_trades")
                .insert(trade)
                .select(Self.tradeColumns)
                .single()
                .execute()
                .value
        }
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

private struct PriceUpdate: Encodable, Sendable {
    var price: Decimal
}

private struct CurrentPrice: Encodable, Sendable {
    var price: Decimal
    var priceOn: CalendarDay

    private enum CodingKeys: String, CodingKey {
        case price
        case priceOn = "price_on"
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
