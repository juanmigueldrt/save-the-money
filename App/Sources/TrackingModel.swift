import Foundation
import Observation
import STMCore

/// Seguimiento: patrimonio neto con su historia, score crediticio e informes.
@Observable
@MainActor
final class TrackingModel {
    let household: Household
    private let finance: any FinanceService
    private let budgets: any BudgetService
    private let scores: any CreditScoreService
    private let today: () -> CalendarDay

    /// Todos los movimientos, para rehacer el patrimonio mes a mes.
    private(set) var allMovements: [Movement] = []
    /// Día del movimiento más antiguo, calculado al cargar (lo usa el tramo «Todo»).
    private var firstMovement: CalendarDay?
    /// Patrimonio ya calculado, para no rehacerlo en cada pintado. Se vacía al cargar otros movimientos.
    @ObservationIgnored private var historyCache: [HistoryKey: [NetWorthPoint]] = [:]
    private(set) var creditScores: [CreditScore] = []
    private(set) var reportMovements: [Movement] = []
    private(set) var isLoading = false
    var error: String?

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
        let points = NetWorth.history(accounts: accounts, movements: allMovements, months: months, through: key.through)
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
        let finance = finance, id = household.id
        await perform {
            let list = try await finance.allMovements(in: id)
            guard list != self.allMovements else { return }
            self.allMovements = list
            self.firstMovement = list.map(\.bookedOn).min()
            self.historyCache = [:]
        }
    }

    // MARK: Score

    var latestScore: CreditScore? { creditScores.first }

    func loadScores() async {
        let scores = scores
        await perform { self.creditScores = try await scores.creditScores() }
    }

    @discardableResult
    func add(_ score: CreditScore) async -> Bool {
        if let issue = score.issue { error = issue; return false }
        return await perform {
            _ = try await scores.addCreditScore(score)
            creditScores = try await scores.creditScores()
        }
    }

    @discardableResult
    func delete(_ score: CreditScore) async -> Bool {
        await perform {
            try await scores.deleteCreditScore(score.id)
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
        let budgets = budgets, id = household.id, range = reportRange
        // Se carga desde el principio del periodo anterior para poder comparar.
        let from = min(previousRange.lowerBound, range.lowerBound)
        isLoading = true
        defer { isLoading = false }
        await perform {
            let list = try await budgets.movements(in: id, from: from, through: range.upperBound)
            // Si se cambió de periodo mientras cargaba, no se pisa.
            if range == self.reportRange { self.reportMovements = list }
        }
    }

    @discardableResult
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
