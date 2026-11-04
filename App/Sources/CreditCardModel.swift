import Foundation
import Observation
import STMCore

/// Tarjetas de crédito del hogar: condiciones, compras aplazadas y lo que se paga cada mes.
/// Lee los movimientos de cada tarjeta y, al cambiar algo, reprograma los avisos de cargo
/// y avisa si una tarjeta pasa del % del límite.
@Observable
@MainActor
final class CreditCardModel {
    let household: Household
    private let service: any CreditCardService
    private let finance: any FinanceService
    private let reminders: any ReminderScheduling
    private let alerts: any BudgetAlerting
    private let today: () -> CalendarDay

    private(set) var terms: [UUID: CreditCardTerms] = [:]
    private(set) var installments: [CardInstallment] = []
    private(set) var movements: [UUID: [Movement]] = [:]
    private(set) var summaries: [UUID: CreditCardSummary] = [:]
    private(set) var isLoading = false
    var error: String?

    /// Lo último que se supo de las cuentas, para recalcular sin esperar a FinanceModel.
    private var accounts: [Account] = []
    private var balances: [UUID: Money] = [:]
    private var transferCategories: Set<UUID> = []

    init(household: Household, service: any CreditCardService, finance: any FinanceService,
         reminders: any ReminderScheduling = NoReminders(), alerts: any BudgetAlerting = NoBudgetAlerts(),
         today: @escaping () -> CalendarDay = { CalendarDay() }) {
        self.household = household
        self.service = service
        self.finance = finance
        self.reminders = reminders
        self.alerts = alerts
        self.today = today
    }

    var day: CalendarDay { today() }

    var cardAccounts: [Account] { accounts.filter { $0.kind == .creditCard && !$0.isArchived } }

    func summary(for account: Account) -> CreditCardSummary? { summaries[account.id] }
    func installment(for movement: Movement) -> CardInstallment? { installments.first { $0.movementId == movement.id } }
    func movements(of account: Account) -> [Movement] { movements[account.id] ?? [] }
    func balance(of accountId: UUID?) -> Money? { accountId.flatMap { balances[$0] } }

    /// Compras de la tarjeta que se pueden aplazar: del extracto abierto, de 50 € o más y sin aplazar.
    func deferrable(in account: Account) -> [Movement] {
        guard let summary = summaries[account.id], let terms = terms[account.id] else { return [] }
        let start = terms.cycleStart(forStatement: summary.openStatement)
        return movements(of: account).filter {
            $0.amount.minor <= -5_000 && $0.bookedOn >= start && installment(for: $0) == nil
                && !(transferCategories.contains($0.categoryId ?? UUID()))
        }
    }

    /// Total de los próximos cargos de todas las tarjetas, para el resumen.
    var nextPaymentsTotal: Money {
        summaries.values.compactMap(\.next?.amount).reduce(.zero, +)
    }

    // MARK: Cargar

    func load(accounts: [Account], balances: [UUID: Money], categories: [BudgetCategory]) async {
        self.accounts = accounts
        self.balances = balances
        transferCategories = Set(categories.filter { $0.kind == .transfer }.map(\.id))
        isLoading = true
        defer { isLoading = false }
        await perform {
            let service = service, id = household.id
            async let terms = service.creditCards(in: id)
            async let installments = service.cardInstallments(in: id)
            let (loadedTerms, loadedInstallments) = try await (terms, installments)
            self.terms = Dictionary(loadedTerms.map { ($0.accountId, $0) }, uniquingKeysWith: { a, _ in a })
            self.installments = loadedInstallments
            var loaded: [UUID: [Movement]] = [:]
            for account in cardAccounts {
                loaded[account.id] = try await finance.movements(in: id, accountId: account.id, limit: FinanceModel.recentLimit)
            }
            movements = loaded
        }
        await recompute()
    }

    private func recompute() async {
        var result: [UUID: CreditCardSummary] = [:]
        for account in cardAccounts {
            guard let terms = terms[account.id] else { continue }
            result[account.id] = CreditCardCalculator.summary(
                terms: terms, balance: balances[account.id] ?? account.openingBalance, movements: movements(of: account),
                installments: installments, transferCategories: transferCategories, today: today())
        }
        summaries = result

        let cards = cardAccounts.compactMap { account -> (summary: CreditCardSummary, name: String, payFromBalance: Money?)? in
            guard let summary = result[account.id] else { return nil }
            return (summary, account.name, balance(of: summary.terms.payFromAccountId))
        }
        await reminders.replace(with: ReminderPlanner.plan(cards: cards, today: today()), prefix: ReminderPlanner.cardPrefix)
        await alerts.notify(cards.compactMap { BudgetAlertPlanner.cardAlert(for: $0.summary, name: $0.name) })
    }

    // MARK: Cambiar

    @discardableResult
    func save(_ terms: CreditCardTerms) async -> Bool {
        if let issue = terms.issue {
            error = issue
            return false
        }
        let ok = await perform {
            let saved = try await service.saveCreditCard(terms)
            self.terms[saved.accountId] = saved
        }
        if ok { await recompute() }
        return ok
    }

    @discardableResult
    func deferPurchase(_ movement: Movement, months: Int, in account: Account) async -> Bool {
        let rate = terms[account.id]?.installmentRate ?? 14
        let plan = installment(for: movement).map { existing -> CardInstallment in
            var changed = existing
            changed.months = months
            return changed
        } ?? CardInstallment(householdId: household.id, accountId: account.id, movementId: movement.id,
                             months: months, rate: rate)
        let ok = await perform {
            _ = try await service.saveInstallment(plan)
            installments = try await service.cardInstallments(in: household.id)
        }
        if ok { await recompute() }
        return ok
    }

    @discardableResult
    func removeInstallment(_ installment: CardInstallment) async -> Bool {
        let ok = await perform {
            try await service.deleteInstallment(installment.id)
            installments = try await service.cardInstallments(in: household.id)
        }
        if ok { await recompute() }
        return ok
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
