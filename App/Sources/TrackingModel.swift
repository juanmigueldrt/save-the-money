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

    func history(accounts: [Account], months: Int = 12) -> [NetWorthPoint] {
        NetWorth.history(accounts: accounts, movements: allMovements, months: months, through: MonthKey(today()))
    }

    func loadHistory() async {
        let finance = finance, id = household.id
        await perform { self.allMovements = try await finance.allMovements(in: id) }
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

    var reportRange: ClosedRange<CalendarDay> { period.range(today: today()) }

    func report(categories: [BudgetCategory]) -> SpendingReport {
        SpendingReport(movements: reportMovements, categories: categories, range: reportRange, kind: kind,
                       categoryIds: categoryFilter)
    }

    func loadReport() async {
        let budgets = budgets, id = household.id, range = reportRange
        isLoading = true
        defer { isLoading = false }
        await perform {
            let list = try await budgets.movements(in: id, from: range.lowerBound, through: range.upperBound)
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
