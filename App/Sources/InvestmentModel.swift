import Foundation
import Observation
import STMCore

/// Inversiones del hogar abierto: activos, precios, operaciones y aportaciones automáticas.
/// Al cambiar los planes se reprograman sus avisos en el dispositivo.
@Observable
@MainActor
final class InvestmentModel: ServerModel {
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
    var isLoading = false
    var error: String?
    @ObservationIgnored var turns = ReadTurns()
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
        beginLoad()
        defer { endLoad() }
        let service = service, households = households, id = household.id, turn = nextTurn()
        let loaded = await perform(turn: turn) {
            async let holdings = service.holdings(in: id)
            async let prices = service.holdingPrices(in: id)
            async let trades = service.trades(in: id)
            async let plans = service.investmentPlans(in: id)
            let list = try await (holdings, prices, trades, plans)
            store(list.0, in: \.holdings, turn: turn)
            store(list.1, in: \.prices, turn: turn)
            store(list.2, in: \.trades, turn: turn)
            store(list.3, in: \.plans, turn: turn)
        }
        if let list = try? await households.members(of: id) { store(list, in: \.members, turn: turn) }
        // Si la carga falla (o se cancela), los avisos ya programados se quedan como estaban.
        if loaded, !Task.isCancelled { await reschedule() }
    }

    func reschedule() async {
        await reminders.replace(with: ReminderPlanner.plan(plans, holdings: holdings, today: today()),
                                prefix: ReminderPlanner.investmentPrefix)
    }

    // MARK: Activos

    /// Un activo sin versión (`updatedAt`) aún no se ha leído del servidor: es un alta, con el id que le dio el
    /// formulario, y guardarlo otra vez con el mismo no crea otro. Con versión es un cambio sobre esa versión.
    @discardableResult
    func save(_ holding: Holding) async -> Holding? {
        if let issue = holding.issue { error = issue; return nil }
        let isNew = holding.updatedAt == nil
        var result: Holding?
        let ok = await perform {
            let saved = isNew ? try await service.createHolding(holding) : try await service.updateHolding(holding)
            markChanged(\.holdings)
            holdings.removeAll { $0.id == holding.id || $0.id == saved.id }
            holdings.append(saved)
            holdings.sort { $0.trimmedName.localizedStandardCompare($1.trimmedName) == .orderedAscending }
            result = saved
        }
        // Si otro dispositivo lo cambió antes, se recarga para que se vea lo nuevo detrás del aviso.
        if !ok {
            await reloadAfterSave {
                let turn = nextTurn()
                store(try await service.holdings(in: household.id), in: \.holdings, turn: turn)
            }
        }
        return result
    }

    @discardableResult
    func delete(_ holding: Holding) async -> Bool {
        let ok = await perform {
            try await service.deleteHolding(holding.id)
            markChanged(\.holdings)
            markChanged(\.prices)
            markChanged(\.trades)
            markChanged(\.plans)
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
            markChanged(\.holdings)
            if let index = holdings.firstIndex(where: { $0.id == saved.id }) { holdings[index] = saved }
            await reloadAfterSave {
                let turn = nextTurn()
                let list = try await service.holdingPrices(in: household.id)
                store(list, in: \.prices, turn: turn)
            }
        }
    }

    // MARK: Operaciones

    /// Guarda la operación y, con `cash`, su movimiento en la cuenta: los dos o ninguno, en una sola llamada.
    /// Con el mismo `trade.id` (uno por formulario) reintentar no duplica.
    @discardableResult
    func add(_ trade: InvestmentTrade, cash: TradeCash? = nil) async -> Bool {
        if let issue = trade.issue(given: trades) { error = issue; return false }
        let saved = await perform {
            let stored = try await service.addTrade(trade, cash: cash)
            markChanged(\.trades)
            trades.removeAll { $0.id == stored.id }
            trades.append(stored)
        }
        // Si falla puede que ya estuviera guardada (con otros datos): se recarga para que se vea detrás del aviso.
        if !saved {
            await reloadAfterSave {
                let turn = nextTurn()
                let list = try await service.trades(in: household.id)
                store(list, in: \.trades, turn: turn)
            }
        }
        return saved
    }

    /// Compra (`BuyQuote.trade`): con cuenta, el cargo de `total` (con comisión, categoría de ahorro) va con la operación.
    @discardableResult
    func buy(_ trade: InvestmentTrade, of holding: Holding, paying total: Money, from accountId: UUID?,
             finance: FinanceModel) async -> Bool {
        let savings = finance.categories.first { $0.kind == .expense && $0.budgetGroup == .savings }
        let cash = accountId.map {
            TradeCash(accountId: $0, categoryId: savings?.id, amount: -total, description: "Compra de \(holding.trimmedName)")
        }
        return await add(trade, cash: cash, finance: finance)
    }

    /// Venta: con cuenta, el ingreso (lo vendido menos la comisión) va con la operación.
    @discardableResult
    func sell(_ trade: InvestmentTrade, of holding: Holding, into accountId: UUID?, finance: FinanceModel) async -> Bool {
        let cash = accountId.map {
            TradeCash(accountId: $0, amount: trade.cashImpact, description: "Venta de \(holding.trimmedName)")
        }
        return await add(trade, cash: cash, finance: finance)
    }

    private func add(_ trade: InvestmentTrade, cash: TradeCash?, finance: FinanceModel) async -> Bool {
        let saved = await add(trade, cash: cash)
        // Saldos y movimientos al día; también si falla, por si se guardó y no llegó la respuesta.
        if cash != nil { await finance.load() }
        return saved
    }

    @discardableResult
    func delete(_ trade: InvestmentTrade) async -> Bool {
        if let issue = trade.deletionIssue(given: trades) { error = issue; return false }
        return await perform {
            try await service.deleteTrade(trade.id)
            markChanged(\.trades)
            trades.removeAll { $0.id == trade.id }
        }
    }

    // MARK: Planes

    /// Como `save(_ holding:)`: sin versión es un alta con el id del formulario; con versión, un cambio sobre ella.
    @discardableResult
    func save(_ plan: InvestmentPlan) async -> Bool {
        if let issue = plan.issue { error = issue; return false }
        let isNew = plan.updatedAt == nil
        let ok = await perform {
            let saved = isNew ? try await service.createPlan(plan) : try await service.updatePlan(plan)
            markChanged(\.plans)
            plans.removeAll { $0.id == plan.id || $0.id == saved.id }
            plans.append(saved)
            plans.sort { $0.startsOn < $1.startsOn }
        }
        // Si otro dispositivo lo cambió antes, se recarga para que se vea lo nuevo detrás del aviso.
        if !ok {
            await reloadAfterSave {
                let turn = nextTurn()
                store(try await service.investmentPlans(in: household.id), in: \.plans, turn: turn)
            }
        }
        await reschedule()
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
            markChanged(\.plans)
            plans.removeAll { $0.id == plan.id }
        }
        if ok { await reschedule() }
        return ok
    }
}
