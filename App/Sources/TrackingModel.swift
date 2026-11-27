import Foundation
import Observation
import STMCore

/// Seguimiento: patrimonio neto con su historia, score crediticio e informes.
@Observable
@MainActor
final class TrackingModel: ServerModel {
    let household: Household
    private let finance: any FinanceService
    private let budgets: any BudgetService
    private let scores: any CreditScoreService
    private let today: () -> CalendarDay

    /// Todos los movimientos, sólo con cuenta, día e importe, para rehacer el patrimonio mes a mes.
    private(set) var amounts: [MovementAmount] = []
    /// Movimientos de los últimos seis meses: «Ingresos y gastos» y la categoría que más sube.
    private(set) var sixMonthMovements: [Movement] = []
    /// Día del movimiento más antiguo, calculado al cargar (lo usa el tramo «Todo»).
    private var firstMovement: CalendarDay?
    /// Patrimonio ya calculado, para no rehacerlo en cada pintado. Se vacía al cargar otros movimientos.
    @ObservationIgnored private var historyCache: [HistoryKey: [NetWorthPoint]] = [:]
    private(set) var creditScores: [CreditScore] = []
    private(set) var reportMovements: [Movement] = []
    var isLoading = false
    var error: String?
    @ObservationIgnored var turns = ReadTurns()

    var period: ReportPeriod = .thisMonth
    var kind: SpendingReport.Kind = .expense
    var categoryFilter: Set<UUID> = []

    init(household: Household, finance: any FinanceService, budgets: any BudgetService, scores: any CreditScoreService,
         today: @escaping () -> CalendarDay = { CalendarDay() }) {
        self.household = household
        self.finance = finance
        self.budgets = budgets
        self.scores = scores
        self.today = today
    }

    // MARK: Patrimonio

    private struct HistoryKey: Hashable {
        var accounts: [Account]
        var months: Int
        var through: MonthKey
    }

    func history(accounts: [Account], months: Int = 12) -> [NetWorthPoint] {
        let key = HistoryKey(accounts: accounts, months: months, through: MonthKey(today()))
        if let cached = historyCache[key] { return cached }
        let points = NetWorth.history(accounts: accounts, amounts: amounts, months: months, through: key.through)
        // Cambiar cuentas sin cambiar movimientos deja claves viejas: con esto no crece sin límite.
        if historyCache.count >= 16 { historyCache.removeAll() }
        historyCache[key] = points
        return points
    }

    /// Patrimonio del tramo elegido (1M, 6M, 1A o Todo), como en Android.
    func history(accounts: [Account], range: NetWorthRange) -> [NetWorthPoint] {
        let through = MonthKey(today())
        return history(accounts: accounts, months: range.months(firstMovement: firstMovement, through: through))
    }

    /// Se recarga con cada cambio (también los del otro miembro), pero si llega lo mismo no se recalcula nada.
    func loadHistory() async {
        let finance = finance, id = household.id, turn = nextTurn()
        await perform(turn: turn) {
            let list = try await finance.movementAmounts(in: id)
            // Una respuesta antigua no pisa una más nueva; y si llega lo mismo no se recalcula nada.
            guard mayStore(\.amounts, turn: turn), list != self.amounts else { return }
            self.amounts = list
            self.firstMovement = list.map(\.bookedOn).min()
            self.historyCache = [:]
        }
    }

    /// Sólo el tramo que pintan los informes de seis meses, no todos los movimientos (ORC-149).
    func loadSixMonths() async {
        let budgets = budgets, id = household.id, turn = nextTurn()
        let range = ReportPeriod.last6Months.range(today: today(), monthStartDay: household.monthStartDay)
        await perform(turn: turn) {
            let list = try await budgets.movements(in: id, from: range.lowerBound, through: range.upperBound)
            store(list, in: \.sixMonthMovements, turn: turn)
        }
    }

    // MARK: Score

    var latestScore: CreditScore? { creditScores.first }

    func loadScores() async {
        let scores = scores, turn = nextTurn()
        await perform(turn: turn) { store(try await scores.creditScores(), in: \.creditScores, turn: turn) }
    }

    @discardableResult
    func add(_ score: CreditScore) async -> Bool {
        if let issue = score.issue { error = issue.text; return false }
        return await perform {
            let saved = try await scores.addCreditScore(score)
            // Se ve ya, aunque falle la recarga: así no se vuelve a apuntar.
            markChanged(\.creditScores)
            creditScores.append(saved)
            creditScores.sort { $0.recordedOn > $1.recordedOn }
            await reloadAfterSave {
                let turn = nextTurn()
                store(try await scores.creditScores(), in: \.creditScores, turn: turn)
            }
        }
    }

    @discardableResult
    func delete(_ score: CreditScore) async -> Bool {
        await perform {
            try await scores.deleteCreditScore(score.id)
            markChanged(\.creditScores)
            creditScores.removeAll { $0.id == score.id }
        }
    }

    // MARK: Informes

    /// Los periodos de los informes empiezan el día de inicio de mes del hogar, como el presupuesto.
    var reportRange: ClosedRange<CalendarDay> { period.range(today: today(), monthStartDay: household.monthStartDay) }

    var previousRange: ClosedRange<CalendarDay> {
        period.previousRange(today: today(), monthStartDay: household.monthStartDay)
    }

    func report(categories: [BudgetCategory]) -> SpendingReport {
        SpendingReport(movements: reportMovements, categories: categories, range: reportRange, kind: kind,
                       categoryIds: categoryFilter, monthStartDay: household.monthStartDay)
    }

    /// El mismo informe del periodo anterior, para comparar.
    func previousReport(categories: [BudgetCategory]) -> SpendingReport {
        SpendingReport(movements: reportMovements, categories: categories, range: previousRange, kind: kind,
                       categoryIds: categoryFilter, monthStartDay: household.monthStartDay)
    }

    func loadReport() async {
        let budgets = budgets, id = household.id, range = reportRange, turn = nextTurn()
        // Se carga desde el principio del periodo anterior para poder comparar.
        let from = min(previousRange.lowerBound, range.lowerBound)
        beginLoad()
        defer { endLoad() }
        await perform(turn: turn) {
            let list = try await budgets.movements(in: id, from: from, through: range.upperBound)
            // Si se cambió de periodo mientras cargaba, no se pisa.
            if range == self.reportRange { store(list, in: \.reportMovements, turn: turn) }
        }
    }
}
