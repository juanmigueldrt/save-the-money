import Foundation
import Observation
import STMCore

/// Pagos recurrentes y metas del hogar abierto. Al cambiar los pagos se
/// reprograman los avisos del dispositivo.
@Observable
@MainActor
final class PlanningModel: ServerModel {
    let household: Household
    private let recurringService: any RecurringService
    private let goalService: any GoalService
    private let reminders: any ReminderScheduling
    private let today: () -> CalendarDay

    private(set) var series: [RecurringSeries] = []
    private(set) var goals: [Goal] = []
    private(set) var contributions: [GoalContribution] = []
    /// Cargos de los pagos fijos (pendientes, confirmados y saltados).
    private(set) var charges: [RecurringCharge] = []
    /// Los últimos movimientos que se han visto, para emparejar los pendientes al recargar.
    private var knownMovements: [Movement] = []
    var isLoading = false
    var error: String?
    @ObservationIgnored var turns = ReadTurns()

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

    /// Cargos que han llegado y esperan que los confirmes.
    var pending: [PendingCharge] { PendingCharges.pending(charges: charges, series: series) }

    func monthlyTotal(of kind: RecurringKind) -> Money { series.monthlyTotal(of: kind, on: today()) }

    /// Pagos fijos y suscripciones de los próximos 12 meses.
    var yearlyFixedTotal: Money { series.yearlyTotal(of: [.subscription, .essential], from: today()) }

    var progress: [GoalProgress] {
        let day = today()
        return goals.filter { !$0.isArchived }.map { GoalProgress(goal: $0, contributions: contributions, today: day) }
    }

    func progress(of goal: Goal) -> GoalProgress {
        GoalProgress(goal: goal, contributions: contributions, today: today())
    }

    func contributions(of goal: Goal) -> [GoalContribution] { contributions.filter { $0.goalId == goal.id } }

    func load() async {
        beginLoad()
        defer { endLoad() }
        let recurringService = recurringService, goalService = goalService, id = household.id, turn = nextTurn()
        let loaded = await perform(turn: turn) {
            async let series = recurringService.recurringSeries(in: id)
            async let goals = goalService.goals(in: id)
            async let contributions = goalService.contributions(in: id)
            async let charges = recurringService.recurringCharges(in: id)
            let list = try await (series, goals, contributions, charges)
            store(list.0, in: \.series, turn: turn)
            store(list.1, in: \.goals, turn: turn)
            store(list.2, in: \.contributions, turn: turn)
            store(list.3, in: \.charges, turn: turn)
        }
        // Cancelada, no sigue: ni apunta cargos ni toca los avisos.
        guard !Task.isCancelled else { return }
        await syncCharges(movements: knownMovements)
        // Si la carga falla, los avisos ya programados se quedan como estaban.
        if loaded { await reschedule() }
    }

    // MARK: Cargos pendientes

    /// Apunta los cargos que han llegado y empareja los pendientes con movimientos ya apuntados
    /// (del CSV o a mano), para que no se dupliquen.
    func syncCharges(movements: [Movement]) async {
        knownMovements = movements
        guard !series.isEmpty, !Task.isCancelled else { return }
        let missing = PendingCharges.missing(series: series, existing: charges, today: today())
        if !missing.isEmpty, let created = try? await recurringService.createCharges(missing) {
            markChanged(\.charges)
            charges.append(contentsOf: created)
            // Si otro dispositivo los creó a la vez, se vuelven a leer.
            let turn = nextTurn()
            if created.count < missing.count, let all = try? await recurringService.recurringCharges(in: household.id) {
                store(all, in: \.charges, turn: turn)
            }
        }
        var stale = false
        for match in PendingCharges.matches(charges: charges, series: series, movements: movements) {
            guard let charge = charges.first(where: { $0.id == match.charge }) else { continue }
            guard let saved = try? await recurringService.updateCharge(charge, status: .confirmed, transactionId: match.movement),
                  let index = charges.firstIndex(where: { $0.id == saved.id }) else {
                stale = true
                continue
            }
            markChanged(\.charges)
            charges[index] = saved
        }
        // Si alguno no se pudo enlazar (por ejemplo, otro dispositivo lo cambió antes), se vuelven a leer.
        if stale { await reloadCharges() }
    }

    /// Nunca falla: si no se pueden leer, se quedan los que había.
    private func reloadCharges() async {
        let turn = nextTurn()
        guard let all = try? await recurringService.recurringCharges(in: household.id) else { return }
        store(all, in: \.charges, turn: turn)
    }

    /// Crea el movimiento del cargo. Devuelve false si falla (el error queda en `error`).
    @discardableResult
    func confirm(_ item: PendingCharge, with draft: MovementDraft) async -> Bool {
        await perform {
            let movement = try await recurringService.confirmCharge(item.charge.id, with: draft)
            markChanged(\.charges)
            if let index = charges.firstIndex(where: { $0.id == item.charge.id }) {
                charges[index].status = .confirmed
                charges[index].transactionId = movement.id
                charges[index].amount = movement.amount
            }
            // Confirmarlo cambia su versión en el servidor: se vuelven a leer.
            await reloadCharges()
        }
    }

    /// Ese cargo no se ha cobrado (o no se va a cobrar).
    @discardableResult
    func skip(_ item: PendingCharge) async -> Bool {
        let ok = await perform {
            let saved = try await recurringService.updateCharge(item.charge, status: .skipped, transactionId: nil)
            markChanged(\.charges)
            if let index = charges.firstIndex(where: { $0.id == saved.id }) { charges[index] = saved }
        }
        // Si otro dispositivo lo cambió antes, se recarga para que se vea lo nuevo detrás del aviso.
        if !ok { await reloadCharges() }
        return ok
    }

    // MARK: Pagos recurrentes

    /// Un pago fijo sin versión (`updatedAt`) aún no se ha leído del servidor: es un alta, con el id que le dio el
    /// formulario, y guardarlo otra vez con el mismo no crea otro. Con versión es un cambio sobre esa versión.
    @discardableResult
    func save(_ item: RecurringSeries) async -> Bool {
        if let issue = item.issue { error = issue.text; return false }
        let isNew = item.updatedAt == nil
        let ok = await perform {
            let saved = isNew ? try await recurringService.createRecurring(item) : try await recurringService.updateRecurring(item)
            markChanged(\.series)
            series.removeAll { $0.id == item.id || $0.id == saved.id }
            series.append(saved)
            series.sort { $0.trimmedName.localizedStandardCompare($1.trimmedName) == .orderedAscending }
        }
        // Si otro dispositivo lo cambió antes, se recarga para que se vea lo nuevo detrás del aviso.
        if !ok {
            await reloadAfterSave {
                let turn = nextTurn()
                store(try await recurringService.recurringSeries(in: household.id), in: \.series, turn: turn)
            }
        }
        await reschedule()
        return ok
    }

    @discardableResult
    func delete(_ item: RecurringSeries) async -> Bool {
        let ok = await perform {
            try await recurringService.deleteRecurring(item.id)
            markChanged(\.series)
            markChanged(\.charges)
            series.removeAll { $0.id == item.id }
            charges.removeAll { $0.seriesId == item.id }
        }
        if ok { await reschedule() }
        return ok
    }

    func reschedule() async {
        await reminders.replace(with: ReminderPlanner.plan(series, today: today()), prefix: ReminderPlanner.prefix)
        await rescheduleHabits()
    }

    /// Recordatorio para apuntar gastos y aviso del resumen semanal, según Más opciones.
    func rescheduleHabits() async {
        let settings = HabitSettings.current
        var plan: [PlannedReminder] = []
        if settings.logReminder != .off {
            plan += HabitReminderPlanner.logReminders(today: today(), hour: settings.logHour,
                                                      weekly: settings.logReminder == .weekly)
        }
        if settings.weeklySummary {
            plan += HabitReminderPlanner.weeklySummary(today: today())
        }
        await reminders.replace(with: plan, prefix: HabitReminderPlanner.prefix)
    }

    // MARK: Metas

    /// Una meta sin versión (`updatedAt`) aún no se ha leído del servidor: es un alta, con el id que le dio el
    /// formulario, y guardarla otra vez con el mismo no crea otra. Con versión es un cambio sobre esa versión.
    @discardableResult
    func save(_ goal: Goal) async -> Bool {
        if let issue = goal.issue { error = issue.text; return false }
        let isNew = goal.updatedAt == nil
        let ok = await perform {
            let saved = isNew ? try await goalService.createGoal(goal) : try await goalService.updateGoal(goal)
            markChanged(\.goals)
            if let index = goals.firstIndex(where: { $0.id == goal.id || $0.id == saved.id }) {
                goals[index] = saved
            } else {
                goals.append(saved)
            }
        }
        // Si otro dispositivo la cambió antes, se recarga para que se vea lo nuevo detrás del aviso.
        if !ok { await reloadAfterSave(reloadGoals) }
        return ok
    }

    private func reloadGoals() async throws {
        let turn = nextTurn()
        async let goals = goalService.goals(in: household.id)
        async let contributions = goalService.contributions(in: household.id)
        let loaded = try await (goals, contributions)
        store(loaded.0, in: \.goals, turn: turn)
        store(loaded.1, in: \.contributions, turn: turn)
    }

    @discardableResult
    func delete(_ goal: Goal) async -> Bool {
        await perform {
            try await goalService.deleteGoal(goal.id)
            markChanged(\.goals)
            markChanged(\.contributions)
            goals.removeAll { $0.id == goal.id }
            contributions.removeAll { $0.goalId == goal.id }
        }
    }

    /// `id` lo da el formulario, uno por formulario: apuntarla otra vez con el mismo no la duplica.
    @discardableResult
    func contribute(_ amount: Money, to goal: Goal, on day: CalendarDay, note: String?, id: UUID = UUID()) async -> Bool {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = GoalContribution(id: id, householdId: household.id, goalId: goal.id, amount: amount, madeOn: day,
                                    note: trimmed?.isEmpty == false ? trimmed : nil)
        if let issue = item.issue { error = issue.text; return false }
        let ok = await perform {
            let saved = try await goalService.addContribution(item)
            markChanged(\.contributions)
            contributions.removeAll { $0.id == saved.id }
            contributions.insert(saved, at: 0)
            contributions.sort { $0.madeOn > $1.madeOn }
        }
        // Puede que ya estuviera guardada con otros datos: se recarga para que se vea detrás del aviso.
        if !ok { await reloadAfterSave(reloadGoals) }
        // Al llegar al objetivo, se marca como conseguida. Sobre la meta que hay cargada ahora, no la del formulario:
        // solo se le pone la fecha, así que no pisa nada de lo que otro dispositivo haya cambiado.
        if ok, let current = goals.first(where: { $0.id == goal.id }) ?? Optional(goal),
           progress(of: current).isReached, current.completedAt == nil {
            var done = current
            done.completedAt = Date()
            await save(done)
        }
        return ok
    }

    @discardableResult
    func delete(_ contribution: GoalContribution) async -> Bool {
        await perform {
            try await goalService.deleteContribution(contribution.id)
            markChanged(\.contributions)
            contributions.removeAll { $0.id == contribution.id }
        }
    }
}
