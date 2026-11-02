import Foundation
import STMCore
import Supabase

/// Presupuestos sobre Supabase. Se guardan con la función save_budget, que hace
/// presupuesto y límites en una sola transacción con los permisos de quien llama.
extension SupabaseBackend: BudgetService {
    private static let budgetColumns = "id,household_id,month,expected_income_minor,needs_pct,wants_pct,savings_pct,budget_lines(category_id,limit_minor)"
    private static let periodColumns = "id,household_id,account_id,category_id,booked_on,amount_minor,description,notes,import_hash"

    public func budget(for month: MonthKey, in householdId: UUID) async throws -> Budget? {
        let rows: [BudgetRow] = try await mapped {
            try await client.from("budgets")
                .select(Self.budgetColumns)
                .eq("household_id", value: householdId.uuidString)
                .eq("month", value: month.firstDay.iso)
                .limit(1)
                .execute()
                .value
        }
        return rows.first?.budget
    }

    public func latestBudget(before month: MonthKey, in householdId: UUID) async throws -> Budget? {
        let rows: [BudgetRow] = try await mapped {
            try await client.from("budgets")
                .select(Self.budgetColumns)
                .eq("household_id", value: householdId.uuidString)
                .lt("month", value: month.firstDay.iso)
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
            try await client.rpc("save_budget", params: params).execute()
        }
        return try await self.budget(for: budget.month, in: budget.householdId) ?? budget
    }

    public func movements(in householdId: UUID, from: CalendarDay, through: CalendarDay) async throws -> [Movement] {
        // El servidor devuelve como mucho 1000 filas por petición (max_rows): se pide por páginas.
        let pageSize = 1000
        var all: [Movement] = []
        while true {
            let start = all.count
            let page: [Movement] = try await mapped {
                try await client.from("transactions")
                    .select(Self.periodColumns)
                    .eq("household_id", value: householdId.uuidString)
                    .gte("booked_on", value: from.iso)
                    .lte("booked_on", value: through.iso)
                    .order("booked_on", ascending: false)
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
    var expectedIncomeMinor: Int
    var needsPct: Int
    var wantsPct: Int
    var savingsPct: Int
    var budgetLines: [Line]

    enum CodingKeys: String, CodingKey {
        case month
        case householdId = "household_id"
        case expectedIncomeMinor = "expected_income_minor"
        case needsPct = "needs_pct"
        case wantsPct = "wants_pct"
        case savingsPct = "savings_pct"
        case budgetLines = "budget_lines"
    }

    var budget: Budget? {
        guard needsPct + wantsPct + savingsPct == 100 else { return nil }
        return Budget(householdId: householdId, month: MonthKey(month), expectedIncome: Money(minor: expectedIncomeMinor),
                      template: BudgetTemplate(needs: needsPct, wants: wantsPct, savings: savingsPct),
                      limits: Dictionary(budgetLines.map { ($0.categoryId, Money(minor: $0.limitMinor)) }, uniquingKeysWith: { a, _ in a }))
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
    var targetMonth: String
    var expectedIncome: Int
    var needs: Int
    var wants: Int
    var savings: Int
    var lines: [Line]

    init(_ budget: Budget) {
        targetHousehold = budget.householdId
        targetMonth = budget.month.firstDay.iso
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
        case needs, wants, savings, lines
        case targetHousehold = "target_household"
        case targetMonth = "target_month"
        case expectedIncome = "expected_income"
    }
}
