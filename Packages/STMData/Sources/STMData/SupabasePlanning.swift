import Foundation
import STMCore
import Supabase

/// Pagos recurrentes y metas sobre Supabase. El RLS decide qué se ve; las
/// claves foráneas compuestas impiden mezclar filas de hogares distintos.
extension SupabaseBackend: RecurringService, GoalService {
    private static let seriesColumns = "id,household_id,name,kind,amount_minor,account_id,category_id,every,unit,starts_on,ends_on,remind_days_before,archived_at,intro_amount_minor,intro_charges,creates_pending,pending_from,updated_at"
    private static let chargeColumns = "id,household_id,series_id,due_on,amount_minor,status,transaction_id,updated_at"
    private static let goalColumns = "id,household_id,name,kind,target_minor,starting_minor,monthly_plan_minor,target_on,account_id,icon,completed_at,archived_at,updated_at"
    private static let contributionColumns = "id,household_id,goal_id,amount_minor,made_on,note"

    // MARK: RecurringService

    public func recurringSeries(in householdId: UUID) async throws -> [RecurringSeries] {
        try await allRows {
            client.from("recurring_series")
                .select(Self.seriesColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("name")
                .order("id")
        }
    }

    public func createRecurring(_ series: RecurringSeries) async throws -> RecurringSeries {
        if let issue = series.issue { throw AppError.invalidInput(issue) }
        var params = Self.seriesParams(series)
        params["household"] = .uuid(series.householdId)
        return try await saved("create_recurring_series", columns: Self.seriesColumns, params)
    }

    public func updateRecurring(_ series: RecurringSeries) async throws -> RecurringSeries {
        if let issue = series.issue { throw AppError.invalidInput(issue) }
        var params = Self.seriesParams(series)
        params["seen"] = .text(series.updatedAt)
        return try await saved("update_recurring_series", columns: Self.seriesColumns, params)
    }

    /// Lo que comparten `create_recurring_series` y `update_recurring_series`. Sin `pendingFrom`, el servidor pone
    /// hoy al crear y deja el que había al cambiar.
    private static func seriesParams(_ series: RecurringSeries) -> [String: AnyJSON] {
        ["series": .uuid(series.id), "label": .string(series.trimmedName), "series_kind": .string(series.kind.rawValue),
         "amount": .integer(series.amount.minor), "account": .uuid(series.accountId), "category": .uuid(series.categoryId),
         "step": .integer(series.recurrence.every), "step_unit": .string(series.recurrence.unit.rawValue),
         "starts": .day(series.startsOn), "ends": .day(series.endsOn), "remind_days": .int(series.remindDaysBefore),
         "archived": .timestamp(series.archivedAt), "intro_amount": .int(series.introAmount?.minor),
         "intro_count": .int(series.introCharges), "pending": .bool(series.createsPending),
         "pending_start": .day(series.pendingFrom)]
    }

    public func deleteRecurring(_ seriesId: UUID) async throws {
        try await mapped {
            try await client.from("recurring_series").delete().eq("id", value: seriesId.uuidString).execute()
        }
    }

    // MARK: Cargos pendientes

    public func recurringCharges(in householdId: UUID) async throws -> [RecurringCharge] {
        try await allRows {
            client.from("recurring_charges")
                .select(Self.chargeColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("due_on", ascending: false)
                .order("id")
        }
    }

    public func createCharges(_ charges: [RecurringCharge]) async throws -> [RecurringCharge] {
        guard !charges.isEmpty else { return [] }
        return try await mapped {
            try await client.from("recurring_charges")
                .upsert(charges, onConflict: "series_id,due_on", ignoreDuplicates: true)
                .select(Self.chargeColumns)
                .execute()
                .value
        }
    }

    public func confirmCharge(_ chargeId: UUID, with draft: MovementDraft) async throws -> Movement {
        let params = ConfirmChargeParams(charge: chargeId, account: draft.accountId, booked: draft.bookedOn,
                                         amount: draft.amount.minor, category: draft.categoryId,
                                         label: draft.description.trimmingCharacters(in: .whitespacesAndNewlines))
        let movementId: UUID = try await mapped {
            try await client.rpc("confirm_recurring_charge", params: params).execute().value
        }
        return try await mapped {
            try await client.from("transactions")
                .select(Self.movementColumns)
                .eq("id", value: movementId.uuidString)
                .single()
                .execute()
                .value
        }
    }

    public func updateCharge(_ charge: RecurringCharge, status: ChargeStatus,
                             transactionId: UUID?) async throws -> RecurringCharge {
        // `update_recurring_charge` compara la versión y cambia la fila en la misma sentencia; si no coincide falla con STM05.
        try await saved("update_recurring_charge", columns: Self.chargeColumns, [
            "charge": .uuid(charge.id), "seen": .text(charge.updatedAt), "new_status": .string(status.rawValue),
            "movement": .uuid(status == .pending ? nil : transactionId)
        ])
    }

    public func deleteCharge(_ chargeId: UUID) async throws {
        try await mapped {
            try await client.from("recurring_charges").delete().eq("id", value: chargeId.uuidString).execute()
        }
    }

    // MARK: GoalService

    public func goals(in householdId: UUID) async throws -> [Goal] {
        try await allRows {
            client.from("goals")
                .select(Self.goalColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("created_at")
                .order("id")
        }
    }

    public func createGoal(_ goal: Goal) async throws -> Goal {
        if let issue = goal.issue { throw AppError.invalidInput(issue) }
        var params = Self.goalParams(goal)
        params["household"] = .uuid(goal.householdId)
        return try await saved("create_goal", columns: Self.goalColumns, params)
    }

    public func updateGoal(_ goal: Goal) async throws -> Goal {
        if let issue = goal.issue { throw AppError.invalidInput(issue) }
        var params = Self.goalParams(goal)
        params["seen"] = .text(goal.updatedAt)
        return try await saved("update_goal", columns: Self.goalColumns, params)
    }

    /// Lo que comparten `create_goal` y `update_goal`.
    private static func goalParams(_ goal: Goal) -> [String: AnyJSON] {
        ["goal": .uuid(goal.id), "label": .string(goal.trimmedName), "goal_kind": .string(goal.kind.rawValue),
         "target": .integer(goal.target.minor), "starting": .integer(goal.starting.minor),
         "monthly_plan": .int(goal.monthlyPlan?.minor), "due": .day(goal.targetOn), "account": .uuid(goal.accountId),
         "icon_name": .text(goal.icon), "completed": .timestamp(goal.completedAt), "archived": .timestamp(goal.archivedAt)]
    }

    public func deleteGoal(_ goalId: UUID) async throws {
        try await mapped {
            try await client.from("goals").delete().eq("id", value: goalId.uuidString).execute()
        }
    }

    public func contributions(in householdId: UUID) async throws -> [GoalContribution] {
        try await allRows {
            client.from("goal_contributions")
                .select(Self.contributionColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("made_on", ascending: false)
                .order("id")
        }
    }

    public func addContribution(_ contribution: GoalContribution) async throws -> GoalContribution {
        if let issue = contribution.issue { throw AppError.invalidInput(issue) }
        return try await saved("create_goal_contribution", columns: Self.contributionColumns, [
            "contribution": .uuid(contribution.id), "household": .uuid(contribution.householdId),
            "goal": .uuid(contribution.goalId), "amount": .integer(contribution.amount.minor),
            "made": .day(contribution.madeOn), "remark": .text(contribution.note)
        ])
    }

    public func deleteContribution(_ contributionId: UUID) async throws {
        try await mapped {
            try await client.from("goal_contributions").delete().eq("id", value: contributionId.uuidString).execute()
        }
    }
}

private struct ConfirmChargeParams: Encodable, Sendable {
    var charge: UUID
    var account: UUID
    var booked: CalendarDay
    var amount: Int
    var category: UUID?
    var label: String

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(charge, forKey: .charge)
        try c.encode(account, forKey: .account)
        try c.encode(booked, forKey: .booked)
        try c.encode(amount, forKey: .amount)
        try c.encode(category, forKey: .category)
        try c.encode(label, forKey: .label)
    }

    private enum CodingKeys: String, CodingKey { case charge, account, booked, amount, category, label }
}
