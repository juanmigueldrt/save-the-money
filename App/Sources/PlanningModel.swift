import Foundation
import Observation
import STMCore

/// Pagos recurrentes y metas del hogar abierto. Al cambiar los pagos se
/// reprograman los avisos del dispositivo.
@Observable
@MainActor
final class PlanningModel {
    let household: Household
    private let recurringService: any RecurringService
    private let goalService: any GoalService
    private let reminders: any ReminderScheduling
    private let today: () -> CalendarDay

    private(set) var series: [RecurringSeries] = []
    private(set) var goals: [Goal] = []
    private(set) var contributions: [GoalContribution] = []
    private(set) var isLoading = false
    var error: String?

    init(household: Household, recurring: any RecurringService, goals: any GoalService,
         reminders: any ReminderScheduling = NoReminders(), today: @escaping () -> CalendarDay = { CalendarDay() }) {
        self.household = household
        recurringService = recurring
        goalService = goals
        self.reminders = reminders
        self.today = today
    }

    var activeSeries: [RecurringSeries] { series.filter { !$0.isArchived } }
    var archivedSeries: [RecurringSeries] { series.filter(\.isArchived) }

    func series(of kind: RecurringKind) -> [RecurringSeries] { activeSeries.filter { $0.kind == kind } }

    /// Hoy (fijo en el modo de capturas).
    var day: CalendarDay { today() }

    var upcoming: [UpcomingCharge] { series.upcoming(from: today(), days: 30) }

    func monthlyTotal(of kind: RecurringKind) -> Money { series.monthlyTotal(of: kind, on: today()) }

    var progress: [GoalProgress] {
        let day = today()
        return goals.filter { !$0.isArchived }.map { GoalProgress(goal: $0, contributions: contributions, today: day) }
    }

    func progress(of goal: Goal) -> GoalProgress {
        GoalProgress(goal: goal, contributions: contributions, today: today())
    }

    func contributions(of goal: Goal) -> [GoalContribution] { contributions.filter { $0.goalId == goal.id } }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let recurringService = recurringService, goalService = goalService, id = household.id
        await perform {
            async let series = recurringService.recurringSeries(in: id)
            async let goals = goalService.goals(in: id)
            async let contributions = goalService.contributions(in: id)
            (self.series, self.goals, self.contributions) = try await (series, goals, contributions)
        }
        await reschedule()
    }

    // MARK: Pagos recurrentes

    @discardableResult
    func save(_ item: RecurringSeries) async -> Bool {
        if let issue = item.issue { error = issue; return false }
        let isNew = !series.contains { $0.id == item.id }
        let ok = await perform {
            let saved = isNew ? try await recurringService.createRecurring(item) : try await recurringService.updateRecurring(item)
            series.removeAll { $0.id == item.id || $0.id == saved.id }
            series.append(saved)
            series.sort { $0.trimmedName.localizedStandardCompare($1.trimmedName) == .orderedAscending }
        }
        if ok { await reschedule() }
        return ok
    }

    @discardableResult
    func delete(_ item: RecurringSeries) async -> Bool {
        let ok = await perform {
            try await recurringService.deleteRecurring(item.id)
            series.removeAll { $0.id == item.id }
        }
        if ok { await reschedule() }
        return ok
    }

    func reschedule() async {
        await reminders.replace(with: ReminderPlanner.plan(series, today: today()), prefix: ReminderPlanner.prefix)
    }

    // MARK: Metas

    @discardableResult
    func save(_ goal: Goal) async -> Bool {
        if let issue = goal.issue { error = issue; return false }
        let isNew = !goals.contains { $0.id == goal.id }
        return await perform {
            let saved = isNew ? try await goalService.createGoal(goal) : try await goalService.updateGoal(goal)
            if let index = goals.firstIndex(where: { $0.id == goal.id || $0.id == saved.id }) {
                goals[index] = saved
            } else {
                goals.append(saved)
            }
        }
    }

    @discardableResult
    func delete(_ goal: Goal) async -> Bool {
        await perform {
            try await goalService.deleteGoal(goal.id)
            goals.removeAll { $0.id == goal.id }
            contributions.removeAll { $0.goalId == goal.id }
        }
    }

    @discardableResult
    func contribute(_ amount: Money, to goal: Goal, on day: CalendarDay, note: String?) async -> Bool {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = GoalContribution(householdId: household.id, goalId: goal.id, amount: amount, madeOn: day,
                                    note: trimmed?.isEmpty == false ? trimmed : nil)
        if let issue = item.issue { error = issue; return false }
        let ok = await perform {
            let saved = try await goalService.addContribution(item)
            contributions.insert(saved, at: 0)
            contributions.sort { $0.madeOn > $1.madeOn }
        }
        // Al llegar al objetivo, se marca como conseguida.
        if ok, progress(of: goal).isReached, goal.completedAt == nil {
            var done = goal
            done.completedAt = Date()
            await save(done)
        }
        return ok
    }

    @discardableResult
    func delete(_ contribution: GoalContribution) async -> Bool {
        await perform {
            try await goalService.deleteContribution(contribution.id)
            contributions.removeAll { $0.id == contribution.id }
        }
    }

    private func perform(_ operation: () async throws -> Void) async -> Bool {
        error = nil
        do {
            try await operation()
            return true
        } catch let appError as AppError {
            error = appError.errorDescription
        } catch {
            self.error = AppError.unknown("").errorDescription
        }
        return false
    }
}
