import Foundation
import STMCore
import Supabase

/// Pagos recurrentes y metas sobre Supabase. El RLS decide qué se ve; las
/// claves foráneas compuestas impiden mezclar filas de hogares distintos.
extension SupabaseBackend: RecurringService, GoalService {
    private static let seriesColumns = "id,household_id,name,kind,amount_minor,account_id,category_id,every,unit,starts_on,ends_on,remind_days_before,archived_at"
    private static let goalColumns = "id,household_id,name,kind,target_minor,starting_minor,monthly_plan_minor,target_on,account_id,icon,completed_at,archived_at"
    private static let contributionColumns = "id,household_id,goal_id,amount_minor,made_on,note"

    // MARK: RecurringService

    public func recurringSeries(in householdId: UUID) async throws -> [RecurringSeries] {
        try await mapped {
            try await client.from("recurring_series")
                .select(Self.seriesColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("name")
                .execute()
                .value
        }
    }

    public func createRecurring(_ series: RecurringSeries) async throws -> RecurringSeries {
        if let issue = series.issue { throw AppError.invalidInput(issue) }
        let row = NewRow(householdId: series.householdId, fields: series)
        return try await mapped {
            try await client.from("recurring_series")
                .insert(row)
                .select(Self.seriesColumns)
                .single()
                .execute()
                .value
        }
    }

    public func updateRecurring(_ series: RecurringSeries) async throws -> RecurringSeries {
        if let issue = series.issue { throw AppError.invalidInput(issue) }
        return try await mapped {
            try await client.from("recurring_series")
                .update(series)
                .eq("id", value: series.id.uuidString)
                .select(Self.seriesColumns)
                .single()
                .execute()
                .value
        }
    }

    public func deleteRecurring(_ seriesId: UUID) async throws {
        try await mapped {
            try await client.from("recurring_series").delete().eq("id", value: seriesId.uuidString).execute()
        }
    }

    // MARK: GoalService

    public func goals(in householdId: UUID) async throws -> [Goal] {
        try await mapped {
            try await client.from("goals")
                .select(Self.goalColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("created_at")
                .execute()
                .value
        }
    }

    public func createGoal(_ goal: Goal) async throws -> Goal {
        if let issue = goal.issue { throw AppError.invalidInput(issue) }
        let row = NewRow(householdId: goal.householdId, fields: goal)
        return try await mapped {
            try await client.from("goals")
                .insert(row)
                .select(Self.goalColumns)
                .single()
                .execute()
                .value
        }
    }

    public func updateGoal(_ goal: Goal) async throws -> Goal {
        if let issue = goal.issue { throw AppError.invalidInput(issue) }
        return try await mapped {
            try await client.from("goals")
                .update(goal)
                .eq("id", value: goal.id.uuidString)
                .select(Self.goalColumns)
                .single()
                .execute()
                .value
        }
    }

    public func deleteGoal(_ goalId: UUID) async throws {
        try await mapped {
            try await client.from("goals").delete().eq("id", value: goalId.uuidString).execute()
        }
    }

    public func contributions(in householdId: UUID) async throws -> [GoalContribution] {
        try await mapped {
            try await client.from("goal_contributions")
                .select(Self.contributionColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("made_on", ascending: false)
                .execute()
                .value
        }
    }

    public func addContribution(_ contribution: GoalContribution) async throws -> GoalContribution {
        if let issue = contribution.issue { throw AppError.invalidInput(issue) }
        return try await mapped {
            try await client.from("goal_contributions")
                .insert(contribution)
                .select(Self.contributionColumns)
                .single()
                .execute()
                .value
        }
    }

    public func deleteContribution(_ contributionId: UUID) async throws {
        try await mapped {
            try await client.from("goal_contributions").delete().eq("id", value: contributionId.uuidString).execute()
        }
    }
}

/// Las columnas editables de una fila más su hogar, para insertarla.
struct NewRow<Fields: Encodable & Sendable>: Encodable, Sendable {
    var householdId: UUID
    var fields: Fields

    private enum CodingKeys: String, CodingKey { case householdId = "household_id" }

    func encode(to encoder: Encoder) throws {
        try fields.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(householdId, forKey: .householdId)
    }
}
