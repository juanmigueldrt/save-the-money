import Foundation
import Observation
import STMCore

/// Inversiones del hogar abierto: activos, precios, operaciones y aportaciones automáticas.
/// Al cambiar los planes se reprograman sus avisos en el dispositivo.
@Observable
@MainActor
final class InvestmentModel {
    let household: Household
    private let service: any InvestmentService
    private let households: any HouseholdService
    private let reminders: any ReminderScheduling
    private let today: () -> CalendarDay

    private(set) var holdings: [Holding] = []
    private(set) var prices: [HoldingPrice] = []
    private(set) var trades: [InvestmentTrade] = []
    private(set) var plans: [InvestmentPlan] = []
    private(set) var members: [HouseholdMember] = []
    private(set) var isLoading = false
    var error: String?
    var range: ChartRange = .month

    init(household: Household, service: any InvestmentService, households: any HouseholdService,
         reminders: any ReminderScheduling = NoReminders(), today: @escaping () -> CalendarDay = { CalendarDay() }) {
        self.household = household
        self.service = service
        self.households = households
        self.reminders = reminders
        self.today = today
    }

    var day: CalendarDay { today() }

    // MARK: Cálculos

    var activeHoldings: [Holding] { holdings.filter { !$0.isArchived } }
    var portfolio: Portfolio { Portfolio(holdings: holdings, trades: trades) }

    var evolution: [PortfolioPoint] {
        PriceHistory.evolution(holdings: holdings, prices: prices, trades: trades, range: range, today: today())
    }

    func holding(_ id: UUID) -> Holding? { holdings.first { $0.id == id } }
    func position(of holding: Holding) -> Position { Position(holding: holding, trades: trades) }
    func trades(of holding: Holding) -> [InvestmentTrade] {
        trades.filter { $0.holdingId == holding.id }.sorted { $0.tradedOn > $1.tradedOn }
    }

    func priceHistory(of holding: Holding, range: ChartRange) -> [(CalendarDay, Decimal)] {
        let start = range.start(today: today(), earliest: nil)
        return PriceHistory.points(for: holding, prices: prices, trades: trades).filter { $0.0 >= start }
    }

    func yearRange(of holding: Holding) -> ClosedRange<Decimal>? {
        PriceHistory.range(for: holding, prices: prices, trades: trades, from: today().adding(months: -12), through: today())
    }

    var livePlans: [InvestmentPlan] { plans.filter { !$0.isArchived } }
    var monthlyPlanned: Money { plans.monthlyTotal(on: today()) }
    var planCounts: (active: Int, paused: Int) { plans.counts(on: today()) }
    func charges(in month: MonthKey) -> [PlanCharge] { plans.charges(in: month) }

    /// "Ana" o "Compartido", para el subtítulo de un activo o plan.
    func ownerName(_ id: UUID?) -> String {
        guard let id else { return "Compartido" }
        return members.first { $0.profile.id == id }?.profile.name ?? "Otro miembro"
    }

    // MARK: Carga

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let service = service, households = households, id = household.id
        _ = await perform {
            async let holdings = service.holdings(in: id)
            async let prices = service.holdingPrices(in: id)
            async let trades = service.trades(in: id)
            async let plans = service.investmentPlans(in: id)
            (self.holdings, self.prices, self.trades, self.plans) = try await (holdings, prices, trades, plans)
        }
        members = (try? await households.members(of: id)) ?? members
        await reschedule()
    }

    func reschedule() async {
        await reminders.replace(with: ReminderPlanner.plan(plans, holdings: holdings, today: today()),
                                prefix: ReminderPlanner.investmentPrefix)
    }

    // MARK: Activos

    @discardableResult
    func save(_ holding: Holding) async -> Holding? {
        if let issue = holding.issue { error = issue; return nil }
        let isNew = !holdings.contains { $0.id == holding.id }
        var result: Holding?
        _ = await perform {
            let saved = isNew ? try await service.createHolding(holding) : try await service.updateHolding(holding)
            holdings.removeAll { $0.id == holding.id || $0.id == saved.id }
            holdings.append(saved)
            holdings.sort { $0.trimmedName.localizedStandardCompare($1.trimmedName) == .orderedAscending }
            result = saved
        }
        return result
    }

    @discardableResult
    func delete(_ holding: Holding) async -> Bool {
        let ok = await perform {
            try await service.deleteHolding(holding.id)
            holdings.removeAll { $0.id == holding.id }
            prices.removeAll { $0.holdingId == holding.id }
            trades.removeAll { $0.holdingId == holding.id }
            plans.removeAll { $0.holdingId == holding.id }
        }
        if ok { await reschedule() }
        return ok
    }

    @discardableResult
    func recordPrice(_ price: Decimal, on day: CalendarDay, for holding: Holding) async -> Bool {
        await perform {
            let saved = try await service.recordPrice(price, on: day, for: holding.id)
            if let index = holdings.firstIndex(where: { $0.id == saved.id }) { holdings[index] = saved }
            prices = try await service.holdingPrices(in: household.id)
        }
    }

    // MARK: Operaciones

    @discardableResult
    func add(_ trade: InvestmentTrade) async -> Bool {
        if let issue = trade.issue(given: trades) { error = issue; return false }
        return await perform {
            let saved = try await service.addTrade(trade)
            trades.append(saved)
        }
    }

    @discardableResult
    func delete(_ trade: InvestmentTrade) async -> Bool {
        await perform {
            try await service.deleteTrade(trade.id)
            trades.removeAll { $0.id == trade.id }
        }
    }

    // MARK: Planes

    @discardableResult
    func save(_ plan: InvestmentPlan) async -> Bool {
        if let issue = plan.issue { error = issue; return false }
        let isNew = !plans.contains { $0.id == plan.id }
        let ok = await perform {
            let saved = isNew ? try await service.createPlan(plan) : try await service.updatePlan(plan)
            plans.removeAll { $0.id == plan.id || $0.id == saved.id }
            plans.append(saved)
            plans.sort { $0.startsOn < $1.startsOn }
        }
        if ok { await reschedule() }
        return ok
    }

    @discardableResult
    func setPaused(_ paused: Bool, _ plan: InvestmentPlan) async -> Bool {
        var changed = plan
        changed.pausedAt = paused ? Date() : nil
        return await save(changed)
    }

    @discardableResult
    func delete(_ plan: InvestmentPlan) async -> Bool {
        let ok = await perform {
            try await service.deletePlan(plan.id)
            plans.removeAll { $0.id == plan.id }
        }
        if ok { await reschedule() }
        return ok
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
