import Foundation
import STMCore
import Supabase

/// Presupuestos sobre Supabase. Se guardan con la función save_budget, que hace
/// presupuesto y límites en una sola transacción con los permisos de quien llama.
extension SupabaseBackend: BudgetService {
    private static let budgetColumns = "id,household_id,month,ends_on,expected_income_minor,needs_pct,wants_pct,savings_pct,carry_over,warn_pct,budget_lines(category_id,limit_minor)"
    private static let extraColumns = "id,household_id,name,limit_minor,starts_on,ends_on,category_ids,account_ids,is_favorite,updated_at"
    private static let periodColumns = "id,household_id,account_id,category_id,booked_on,amount_minor,description,notes,import_hash,excluded,reviewed_at,payee,tags"

    public func budget(startingOn day: CalendarDay, in householdId: UUID) async throws -> Budget? {
        let rows: [BudgetRow] = try await mapped {
            try await client.from("budgets")
                .select(Self.budgetColumns)
                .eq("household_id", value: householdId.uuidString)
                .eq("month", value: day.iso)
                .limit(1)
                .execute()
                .value
        }
        return rows.first?.budget
    }

    public func latestBudget(before day: CalendarDay, in householdId: UUID) async throws -> Budget? {
        let rows: [BudgetRow] = try await mapped {
            try await client.from("budgets")
                .select(Self.budgetColumns)
                .eq("household_id", value: householdId.uuidString)
                .lt("month", value: day.iso)
                .order("month", ascending: false)
                .limit(1)
                .execute()
                .value
        }
        return rows.first?.budget
    }

    public func saveBudget(_ budget: Budget) async throws -> Budget {
        if let issue = budget.issue { throw AppError.invalidInput(issue) }
        let params = SaveBudgetParams(budget)
        try await mapped {
            try await client.rpc("save_period_budget", params: params).execute()
        }
        return try await self.budget(startingOn: budget.period.start, in: budget.householdId) ?? budget
    }

    public func paySchedule() async throws -> PaySchedule? {
        let rows: [PayScheduleRow] = try await mapped {
            try await client.from("pay_schedules")
                .select("frequency,day1,day2,anchor_on")
                .limit(1)
                .execute()
                .value
        }
        return rows.first?.schedule
    }

    public func savePaySchedule(_ schedule: PaySchedule) async throws -> PaySchedule {
        if let issue = schedule.issue { throw AppError.invalidInput(issue) }
        let row = PayScheduleRow(schedule)
        try await mapped {
            // La fila es de quien llama (user_id por defecto = auth.uid()).
            try await client.from("pay_schedules")
                .upsert(row, onConflict: "user_id")
                .execute()
        }
        return schedule
    }

    public func extraBudgets(in householdId: UUID) async throws -> [ExtraBudget] {
        try await allRows {
            client.from("extra_budgets")
                .select(Self.extraColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("is_favorite", ascending: false)
                .order("starts_on", ascending: false)
                .order("id")
        }
    }

    public func saveExtraBudget(_ budget: ExtraBudget) async throws -> ExtraBudget {
        if let issue = budget.issue { throw AppError.invalidInput(issue) }
        var params: [String: AnyJSON] = [
            "budget": .uuid(budget.id), "label": .string(budget.trimmedName), "cap": .integer(budget.limit.minor),
            "starts": .day(budget.startsOn), "ends": .day(budget.endsOn),
            "category_list": .array(budget.categoryIds.map { .string($0.uuidString) }),
            "account_list": .array(budget.accountIds.map { .string($0.uuidString) }),
            "favorite": .bool(budget.isFavorite)
        ]
        // Sin versión es uno nuevo: `create_extra_budget` no lo repite si ya estaba guardado.
        guard let seen = budget.updatedAt else {
            params["household"] = .uuid(budget.householdId)
            return try await saved("create_extra_budget", columns: Self.extraColumns, params)
        }
        // `update_extra_budget` compara la versión y cambia la fila en la misma sentencia; si no coincide falla con STM05.
        params["seen"] = .string(seen)
        return try await saved("update_extra_budget", columns: Self.extraColumns, params)
    }

    public func deleteExtraBudget(_ id: UUID) async throws {
        try await mapped {
            try await client.from("extra_budgets")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        }
    }

    public func movements(in householdId: UUID, from: CalendarDay, through: CalendarDay) async throws -> [Movement] {
        try await allRows {
            client.from("transactions")
                .select(Self.periodColumns)
                .eq("household_id", value: householdId.uuidString)
                .gte("booked_on", value: from.iso)
                .lte("booked_on", value: through.iso)
                .order("booked_on", ascending: false)
                .order("id")
        }
    }
}

private struct BudgetRow: Decodable {
    struct Line: Decodable {
        var categoryId: UUID
        var limitMinor: Int

        enum CodingKeys: String, CodingKey {
            case categoryId = "category_id"
            case limitMinor = "limit_minor"
        }
    }

    var householdId: UUID
    var month: CalendarDay
    var endsOn: CalendarDay?
    var carryOver: Bool?
    var warnPct: Int?
    var expectedIncomeMinor: Int
    var needsPct: Int
    var wantsPct: Int
    var savingsPct: Int
    var budgetLines: [Line]

    enum CodingKeys: String, CodingKey {
        case month
        case householdId = "household_id"
        case endsOn = "ends_on"
        case carryOver = "carry_over"
        case warnPct = "warn_pct"
        case expectedIncomeMinor = "expected_income_minor"
        case needsPct = "needs_pct"
        case wantsPct = "wants_pct"
        case savingsPct = "savings_pct"
        case budgetLines = "budget_lines"
    }

    var budget: Budget? {
        guard needsPct + wantsPct + savingsPct == 100 else { return nil }
        let period = endsOn.map { BudgetPeriod(start: month, end: $0) } ?? BudgetPeriod(month: MonthKey(month))
        return Budget(householdId: householdId, period: period, expectedIncome: Money(minor: expectedIncomeMinor),
                      template: BudgetTemplate(needs: needsPct, wants: wantsPct, savings: savingsPct),
                      limits: Dictionary(budgetLines.map { ($0.categoryId, Money(minor: $0.limitMinor)) }, uniquingKeysWith: { a, _ in a }),
                      carryOver: carryOver ?? false, warnPercent: warnPct ?? 80)
    }
}

private struct SaveBudgetParams: Encodable, Sendable {
    struct Line: Encodable, Sendable {
        var categoryId: UUID
        var limitMinor: Int

        enum CodingKeys: String, CodingKey {
            case categoryId = "category_id"
            case limitMinor = "limit_minor"
        }
    }

    var targetHousehold: UUID
    var startsOn: String
    var endsOn: String
    var carry: Bool
    var warn: Int
    var expectedIncome: Int
    var needs: Int
    var wants: Int
    var savings: Int
    var lines: [Line]

    init(_ budget: Budget) {
        targetHousehold = budget.householdId
        startsOn = budget.period.start.iso
        endsOn = budget.period.end.iso
        carry = budget.carryOver
        warn = budget.warnPercent
        expectedIncome = budget.expectedIncome.minor
        needs = budget.template.needs
        wants = budget.template.wants
        savings = budget.template.savings
        lines = budget.limits
            .filter { $0.value.minor > 0 }
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .map { Line(categoryId: $0.key, limitMinor: $0.value.minor) }
    }

    enum CodingKeys: String, CodingKey {
        case needs, wants, savings, lines, carry, warn
        case targetHousehold = "target_household"
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case expectedIncome = "expected_income"
    }
}

private struct PayScheduleRow: Codable, Sendable {
    var frequency: String
    var day1: Int
    var day2: Int?
    var anchorOn: CalendarDay?

    init(_ schedule: PaySchedule) {
        frequency = schedule.frequency.rawValue
        day1 = schedule.day1
        day2 = schedule.frequency == .twiceMonthly ? schedule.day2 : nil
        anchorOn = schedule.frequency.usesAnchor ? schedule.anchor : nil
    }

    var schedule: PaySchedule? {
        guard let kind = PayFrequency(rawValue: frequency) else { return nil }
        return PaySchedule(frequency: kind, day1: day1, day2: day2, anchor: anchorOn)
    }

    enum CodingKeys: String, CodingKey {
        case frequency, day1, day2
        case anchorOn = "anchor_on"
    }

    // null explícito para poder quitar el segundo día o la fecha al cambiar de frecuencia.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(frequency, forKey: .frequency)
        try c.encode(day1, forKey: .day1)
        try c.encode(day2, forKey: .day2)
        try c.encode(anchorOn, forKey: .anchorOn)
    }
}
