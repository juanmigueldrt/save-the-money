import Foundation
import Observation
import STMCore

/// Presupuesto y flujo de caja del periodo elegido (de un cobro al siguiente). Lo comparten
/// la pantalla de presupuesto, la de flujo y el Resumen, para que todas miren el mismo periodo.
@Observable
@MainActor
final class BudgetModel: ServerModel {
    let household: Household
    private let service: any BudgetService
    private let alerts: any BudgetAlerting
    private let today: () -> CalendarDay

    /// Cuándo cobra quien ha entrado. Sin guardar: cada mes desde el día de inicio del hogar.
    private(set) var schedule: PaySchedule
    /// true si la persona ya ha dicho cuándo cobra.
    private(set) var hasOwnSchedule = false
    private(set) var period: BudgetPeriod
    /// El presupuesto guardado de este periodo.
    private(set) var budget: Budget?
    /// Si no hay presupuesto en este periodo, el último que haya, para proponerlo.
    private(set) var proposal: Budget?
    /// Presupuesto y movimientos del periodo anterior, para el arrastre.
    private(set) var previousBudget: Budget?
    /// Movimientos de este periodo y de los 3 anteriores (para arrastre y presupuesto inteligente).
    private(set) var movements: [Movement] = []
    private(set) var extraBudgets: [ExtraBudget] = []
    var isLoading = false
    var error: String?
    @ObservationIgnored var turns = ReadTurns()

    init(household: Household, service: any BudgetService, alerts: any BudgetAlerting = NoBudgetAlerts(),
         today: @escaping () -> CalendarDay = { CalendarDay() }) {
        self.household = household
        self.service = service
        self.alerts = alerts
        self.today = today
        let fallback = PaySchedule.monthly(startDay: household.monthStartDay)
        schedule = fallback
        period = fallback.period(containing: today())
    }

    /// El mes del periodo (para lo que aún va por meses).
    var month: MonthKey { period.month }

    /// Los 3 periodos anteriores, del más reciente al más antiguo.
    var previousPeriods: [BudgetPeriod] {
        var list: [BudgetPeriod] = []
        var current = period
        for _ in 0..<3 {
            current = schedule.period(before: current)
            list.append(current)
        }
        return list
    }

    /// Avisa de los límites del periodo en curso que se acercan o se pasan.
    func checkAlerts(categories: [BudgetCategory]) async {
        guard budget != nil, period.contains(today()), !Task.isCancelled else { return }
        await alerts.notify(BudgetAlertPlanner.alerts(for: report(categories: categories)))
    }

    func flex(categories: [BudgetCategory], series: [RecurringSeries]) -> FlexBudget {
        FlexBudget(report: report(categories: categories), series: series, today: today())
    }

    /// Arrastre que llega del periodo anterior (vacío si este presupuesto no arrastra).
    func carried(categories: [BudgetCategory]) -> [UUID: Money] {
        guard budget?.carryOver == true, let previousBudget,
              let before = previousPeriods.first, previousBudget.period == before else { return [:] }
        // Lo arrastrado al anterior no se encadena aquí: basta con un periodo hacia atrás.
        let previous = BudgetReport(budget: previousBudget, period: before, categories: categories, movements: movements)
        return BudgetCarryOver.amounts(previous: previous)
    }

    func report(categories: [BudgetCategory]) -> BudgetReport {
        BudgetReport(budget: budget, period: period, categories: categories, movements: movements,
                     carried: carried(categories: categories))
    }

    func insights(categories: [BudgetCategory]) -> PeriodInsights {
        PeriodInsights(report: report(categories: categories), budget: budget, today: today())
    }

    /// Límites propuestos con la media de los 3 periodos anteriores.
    func suggestedLimits(categories: [BudgetCategory]) -> [UUID: Money] {
        SmartBudget.suggestedLimits(movements: movements, categories: categories, periods: previousPeriods)
    }

    /// Punto de partida del formulario: el de este periodo, el último o uno vacío 50/30/20.
    var draft: Budget {
        budget ?? proposal?.copied(to: period) ?? Budget(householdId: household.id, period: period)
    }

    var isCurrentPeriod: Bool { period.contains(today()) }

    func showPrevious() async { await show(schedule.period(before: period)) }
    func showNext() async { await show(schedule.period(after: period)) }
    func showCurrent() async { await show(schedule.period(containing: today())) }

    func show(_ period: BudgetPeriod) async {
        self.period = period
        await load()
    }

    /// Lo de antes de los periodos: el mes que contiene ese mes.
    func show(_ month: MonthKey) async {
        await show(schedule.period(containing: month.period(startDay: household.monthStartDay).upperBound))
    }

    func load() async {
        let service = service, id = household.id, turn = nextTurn()
        beginLoad()
        defer { endLoad() }
        await perform(turn: turn) {
            if let saved = try await service.paySchedule(), saved != schedule || !hasOwnSchedule,
               mayStore(\.schedule, turn: turn) {
                let wasCurrent = period.contains(today())
                schedule = saved
                hasOwnSchedule = true
                // Con otro día de cobro, el periodo en pantalla se recalcula.
                period = wasCurrent ? saved.period(containing: today()) : saved.period(containing: period.end)
            }
            let period = period, previous = previousPeriods
            let from = previous.last?.start ?? period.start
            async let budget = service.budget(startingOn: period.start, in: id)
            async let last = service.latestBudget(before: period.start, in: id)
            async let movements = service.movements(in: id, from: from, through: period.end)
            async let extras = service.extraBudgets(in: id)
            let (current, latest, list, extraList) = try await (budget, last, movements, extras)
            // Si el usuario ya cambió de periodo mientras cargaba, no se pisa.
            guard period == self.period else { return }
            store(current, in: \.budget, turn: turn)
            store(current == nil ? latest : nil, in: \.proposal, turn: turn)
            store(latest, in: \.previousBudget, turn: turn)
            store(list, in: \.movements, turn: turn)
            store(extraList, in: \.extraBudgets, turn: turn)
        }
    }

    @discardableResult
    func save(_ budget: Budget) async -> Bool {
        await perform {
            let saved = try await self.service.saveBudget(budget)
            markChanged(\.budget)
            markChanged(\.proposal)
            self.budget = saved
            self.proposal = nil
        }
    }

    @discardableResult
    func save(_ schedule: PaySchedule) async -> Bool {
        let ok = await perform {
            let saved = try await self.service.savePaySchedule(schedule)
            markChanged(\.schedule)
            self.schedule = saved
            self.hasOwnSchedule = true
            self.period = schedule.period(containing: self.today())
        }
        if ok { await load() }
        return ok
    }

    /// Uno sin versión (`updatedAt`) aún no se ha leído del servidor: es un alta, con el id que le dio el
    /// formulario, y guardarlo otra vez con el mismo no crea otro. Con versión es un cambio sobre esa versión.
    @discardableResult
    func save(_ extra: ExtraBudget) async -> Bool {
        let ok = await perform {
            let saved = try await self.service.saveExtraBudget(extra)
            // Se ve ya, aunque falle la recarga.
            markChanged(\.extraBudgets)
            self.extraBudgets.removeAll { $0.id == saved.id }
            self.extraBudgets.append(saved)
            await reloadAfterSave {
                let turn = nextTurn()
                let list = try await self.service.extraBudgets(in: self.household.id)
                store(list, in: \.extraBudgets, turn: turn)
            }
        }
        // Si otro dispositivo lo cambió antes, se recarga para que se vea lo nuevo detrás del aviso.
        if !ok {
            await reloadAfterSave {
                let turn = nextTurn()
                let list = try await self.service.extraBudgets(in: self.household.id)
                store(list, in: \.extraBudgets, turn: turn)
            }
        }
        return ok
    }

    @discardableResult
    func delete(_ extra: ExtraBudget) async -> Bool {
        await perform {
            try await self.service.deleteExtraBudget(extra.id)
            markChanged(\.extraBudgets)
            self.extraBudgets.removeAll { $0.id == extra.id }
        }
    }

    /// Movimientos que puede necesitar un presupuesto extra (sus fechas pueden salirse del periodo).
    func movements(for extra: ExtraBudget) async -> [Movement] {
        let end = extra.endsOn ?? today()
        do {
            return try await service.movements(in: household.id, from: extra.startsOn, through: max(end, extra.startsOn))
        } catch {
            return []
        }
    }
}
