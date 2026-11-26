import Foundation
import Observation
import STMCore

/// Tarjetas de crédito del hogar: condiciones, compras aplazadas y lo que se paga cada mes.
/// Lee los movimientos de cada tarjeta y, al cambiar algo, reprograma los avisos de cargo
/// y avisa si una tarjeta pasa del % del límite.
@Observable
@MainActor
final class CreditCardModel: ServerModel {
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
    var isLoading = false
    var error: String?
    @ObservationIgnored var turns = ReadTurns()

    /// Lo último que se supo de las cuentas, para recalcular sin esperar a FinanceModel.
    private var accounts: [Account] = []
    private var balances: [UUID: Money] = [:]
    private var transferCategories: Set<UUID> = []
    /// Tarjetas cuyos extractos sin cobrar tienen más movimientos que `cycleLimit`.
    private var truncatedAccounts: Set<UUID> = []

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

    /// Lo que cambia lo que muestra la tarjeta: cuentas, saldos y movimientos. Guarda su propia copia de las cuentas,
    /// así que hay que volver a cargarla cuando cambia cualquiera de estos (RootView lo hace con `.task(id:)`).
    struct Inputs: Equatable {
        let accounts: [Account]
        let balances: [UUID: Money]
        let recent: [Movement]
        /// Cambia al terminar la primera carga de FinanceModel, aunque el hogar esté vacío.
        let financeLoaded: Bool

        @MainActor
        init(finance: FinanceModel) {
            accounts = finance.accounts
            balances = finance.balances
            recent = finance.recent
            financeLoaded = finance.hasLoaded
        }
    }

    func summary(for account: Account) -> CreditCardSummary? { summaries[account.id] }
    func installment(for movement: Movement) -> CardInstallment? { installments.first { $0.movementId == movement.id } }
    func movements(of account: Account) -> [Movement] { movements[account.id] ?? [] }
    func balance(of accountId: UUID?) -> Money? { accountId.flatMap { balances[$0] } }

    /// Compras de la tarjeta que se pueden aplazar: del extracto abierto, de 50 € o más y sin aplazar.
    func deferrable(in account: Account) -> [Movement] {
        guard let summary = summaries[account.id], let terms = terms[account.id] else { return [] }
        let start = terms.cycleStart(forStatement: summary.openStatement)
        return movements(of: account).filter {
            $0.amount.minor <= -CardInstallment.usualMinimum.minor && $0.bookedOn >= start && installment(for: $0) == nil
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
        beginLoad()
        defer { endLoad() }
        let turn = nextTurn()
        let succeeded = await perform(turn: turn) {
            let service = service, id = household.id
            async let terms = service.creditCards(in: id)
            async let installments = service.cardInstallments(in: id)
            let (loadedTerms, loadedInstallments) = try await (terms, installments)
            store(Dictionary(loadedTerms.map { ($0.accountId, $0) }, uniquingKeysWith: { a, _ in a }), in: \.terms, turn: turn)
            store(loadedInstallments, in: \.installments, turn: turn)
            var loaded: [UUID: [Movement]] = [:]
            var truncated: Set<UUID> = []
            // Sin condiciones no hay cálculo: no hace falta ningún movimiento (se cargan al guardarlas).
            for account in cardAccounts {
                guard let cardTerms = self.terms[account.id] else { continue }
                let (list, cut) = try await cardMovements(of: account.id, terms: cardTerms)
                loaded[account.id] = list
                if cut { truncated.insert(account.id) }
            }
            store(loaded, in: \.movements, turn: turn)
            store(truncated, in: \.truncatedAccounts, turn: turn)
        }
        // Cancelada, no cambia nada: ni el resumen ni los avisos.
        guard !Task.isCancelled else { return }
        // Si la carga falla, el resumen se ve igual, pero los avisos ya programados no se tocan.
        await recompute(rescheduling: succeeded)
    }

    /// Tope de movimientos de los extractos sin cobrar de una tarjeta: el servidor da como mucho 1000 filas por
    /// petición. Si se llega, el resumen lo dice (`movementsTruncated`) en vez de dar cifras recortadas sin avisar.
    nonisolated static let cycleLimit = 1000

    /// Lo que necesita el cálculo de la tarjeta: todos los movimientos de los extractos sin cobrar (por fecha, no
    /// los N más recientes) y la compra de cada aplazado. `truncated` si se ha llegado a `cycleLimit`.
    private func cardMovements(of accountId: UUID, terms: CreditCardTerms) async throws -> (list: [Movement], truncated: Bool) {
        let first = CreditCardCalculator.firstUnpaidStatement(terms: terms, today: today())
        let list = try await finance.movements(in: household.id, accountId: accountId,
                                               since: terms.cycleStart(forStatement: first), limit: Self.cycleLimit)
        return (try await addingPurchases(to: list, of: accountId), list.count >= Self.cycleLimit)
    }

    /// Añade las compras de los aplazados de la tarjeta que falten, por antiguas que sean.
    private func addingPurchases(to list: [Movement], of accountId: UUID) async throws -> [Movement] {
        let known = Set(list.map(\.id))
        let missing = installments.filter { $0.accountId == accountId && !known.contains($0.movementId) }
        guard !missing.isEmpty else { return list }
        return list + (try await finance.movements(in: household.id, ids: missing.map(\.movementId)))
    }

    /// Tras recargar los aplazados: uno creado en otro dispositivo puede ser de una compra que no se había cargado.
    private func loadMissingPurchases() async throws {
        let turn = nextTurn()
        for account in cardAccounts where movements[account.id] != nil {
            let list = try await addingPurchases(to: movements(of: account), of: account.id)
            guard mayStore(\.movements, turn: turn) else { return }
            movements[account.id] = list
        }
    }

    private func recompute(rescheduling: Bool = true) async {
        var result: [UUID: CreditCardSummary] = [:]
        for account in cardAccounts {
            guard let terms = terms[account.id] else { continue }
            result[account.id] = CreditCardCalculator.summary(
                terms: terms, balance: balances[account.id] ?? account.openingBalance, movements: movements(of: account),
                installments: installments, transferCategories: transferCategories, today: today())
            result[account.id]?.movementsTruncated = truncatedAccounts.contains(account.id)
        }
        summaries = result
        guard rescheduling else { return }

        let cards = cardAccounts.compactMap { account -> (summary: CreditCardSummary, name: String, payFromBalance: Money?)? in
            guard let summary = result[account.id] else { return nil }
            return (summary, account.name, balance(of: summary.terms.payFromAccountId))
        }
        await reminders.replace(with: ReminderPlanner.plan(cards: cards, today: today()), prefix: ReminderPlanner.cardPrefix)
        await alerts.notify(cards.compactMap { BudgetAlertPlanner.cardAlert(for: $0.summary, name: $0.name) })
    }

    /// Al tocar el interruptor de avisos en Más opciones: los vuelve a programar (o los quita) con lo último cargado.
    func reschedule() async { await recompute() }

    // MARK: Cambiar

    @discardableResult
    func save(_ terms: CreditCardTerms) async -> Bool {
        if let issue = terms.issue {
            error = issue.text
            return false
        }
        let ok = await perform {
            let saved = try await service.saveCreditCard(terms)
            markChanged(\.terms)
            self.terms[saved.accountId] = saved
            // Con otro día de extracto cambian los ciclos sin cobrar: se vuelven a cargar sus movimientos.
            await reloadAfterSave {
                let turn = nextTurn()
                let (list, cut) = try await cardMovements(of: saved.accountId, terms: saved)
                guard mayStore(\.movements, turn: turn), mayStore(\.truncatedAccounts, turn: turn) else { return }
                movements[saved.accountId] = list
                if cut { truncatedAccounts.insert(saved.accountId) } else { truncatedAccounts.remove(saved.accountId) }
            }
        }
        // Si otro dispositivo las cambió antes, se recargan para que se vea lo nuevo detrás del aviso.
        if !ok {
            await reloadAfterSave {
                let turn = nextTurn()
                let list = try await service.creditCards(in: household.id)
                store(Dictionary(list.map { ($0.accountId, $0) }, uniquingKeysWith: { first, _ in first }), in: \.terms, turn: turn)
            }
        }
        await recompute()
        return ok
    }

    /// Un aplazado nuevo lleva el id de su movimiento (hay uno por compra): repetirlo no crea otro.
    @discardableResult
    func deferPurchase(_ movement: Movement, months: Int, in account: Account) async -> Bool {
        let rate = terms[account.id]?.installmentRate ?? CreditCardTerms.defaultInstallmentRate
        let plan = installment(for: movement).map { existing -> CardInstallment in
            var changed = existing
            changed.months = months
            return changed
        } ?? CardInstallment(id: movement.id, householdId: household.id, accountId: account.id, movementId: movement.id,
                             months: months, rate: rate)
        let ok = await perform {
            let saved = try await service.saveInstallment(plan)
            // Se ve ya, aunque falle la recarga.
            markChanged(\.installments)
            installments.removeAll { $0.movementId == saved.movementId }
            installments.append(saved)
            await reloadAfterSave { try await reloadInstallments() }
        }
        // Si otro dispositivo lo cambió antes, o ya estaba guardado con otros datos, se recarga detrás del aviso.
        if !ok { await reloadAfterSave { try await reloadInstallments() } }
        await recompute()
        return ok
    }

    @discardableResult
    func removeInstallment(_ installment: CardInstallment) async -> Bool {
        let ok = await perform {
            try await service.deleteInstallment(installment.id)
            markChanged(\.installments)
            installments.removeAll { $0.id == installment.id }
            await reloadAfterSave { try await reloadInstallments() }
        }
        if ok { await recompute() }
        return ok
    }

    private func reloadInstallments() async throws {
        let turn = nextTurn()
        let list = try await service.cardInstallments(in: household.id)
        store(list, in: \.installments, turn: turn)
        try await loadMissingPurchases()
    }
}
