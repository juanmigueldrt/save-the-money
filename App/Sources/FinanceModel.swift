import Foundation
import Observation
import STMCore

/// Cuentas, saldos, categorías y movimientos del hogar abierto.
/// Las pantallas leen de aquí y llaman a sus métodos para cambiar datos.
@Observable
@MainActor
final class FinanceModel {
    let household: Household
    private let service: any FinanceService

    private(set) var accounts: [Account] = []
    private(set) var balances: [UUID: Money] = [:]
    private(set) var categories: [BudgetCategory] = []
    private(set) var recent: [Movement] = []
    private(set) var isLoading = false
    var error: String?

    /// Movimientos que se cargan para la lista general.
    nonisolated static let recentLimit = 500

    init(household: Household, service: any FinanceService) {
        self.household = household
        self.service = service
    }

    var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    /// Suma de los saldos de las cuentas no archivadas.
    var totalBalance: Money {
        activeAccounts.reduce(Money.zero) { $0 + balance(of: $1) }
    }

    func balance(of account: Account) -> Money {
        balances[account.id] ?? account.openingBalance
    }

    func account(_ id: UUID) -> Account? { accounts.first { $0.id == id } }
    func category(_ id: UUID?) -> BudgetCategory? { id.flatMap { id in categories.first { $0.id == id } } }

    func categories(for kind: CategoryKind) -> [BudgetCategory] {
        categories.filter { $0.kind == kind }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let service = service, id = household.id
        await perform {
            async let accounts = service.accounts(in: id)
            async let balances = service.balances(in: id)
            async let categories = service.categories(in: id)
            async let recent = service.movements(in: id, accountId: nil, limit: Self.recentLimit)
            (self.accounts, self.balances, self.categories, self.recent) = try await (accounts, balances, categories, recent)
        }
    }

    func movements(of account: Account) async -> [Movement] {
        (try? await service.movements(in: household.id, accountId: account.id, limit: Self.recentLimit)) ?? []
    }

    @discardableResult
    func createAccount(_ draft: AccountDraft) async -> Bool {
        await perform {
            _ = try await service.createAccount(draft, in: household.id)
            try await reloadAccounts()
        }
    }

    @discardableResult
    func updateAccount(_ account: Account) async -> Bool {
        await perform {
            _ = try await service.updateAccount(account)
            try await reloadAccounts()
        }
    }

    @discardableResult
    func deleteAccount(_ account: Account) async -> Bool {
        await perform {
            try await service.deleteAccount(account.id)
            try await reloadAll()
        }
    }

    @discardableResult
    func add(_ draft: MovementDraft) async -> Bool {
        await perform {
            _ = try await service.addMovement(draft, in: household.id)
            try await reloadAll()
        }
    }

    @discardableResult
    func update(_ movement: Movement) async -> Bool {
        await perform {
            _ = try await service.updateMovement(movement)
            try await reloadAll()
        }
    }

    /// Guarda varios movimientos ya cambiados (edición masiva, «cambiar similares»). Recarga una vez al final.
    @discardableResult
    func update(_ movements: [Movement]) async -> Bool {
        guard !movements.isEmpty else { return true }
        return await perform {
            for movement in movements { _ = try await service.updateMovement(movement) }
            try await reloadAll()
        }
    }

    /// Borra varios a la vez (sin «Deshacer»: la vista pide confirmación antes).
    @discardableResult
    func delete(_ movements: [Movement]) async -> Bool {
        await perform {
            for movement in movements { try await service.deleteMovement(movement.id) }
            try await reloadAll()
        }
    }

    /// La cuenta que sale elegida al apuntar: la predeterminada o la primera activa.
    var defaultAccount: Account? { accounts.defaultAccount }

    /// Etiquetas y beneficiarios usados, para sugerir al escribir.
    var knownTags: [String] { MovementTags.all(in: recent) }
    var knownPayees: [String] { Payee.all(in: recent) }

    /// El último movimiento borrado, para «Deshacer» (como en Android).
    var lastDeleted: Movement?

    @discardableResult
    func delete(_ movement: Movement) async -> Bool {
        let done = await perform {
            try await service.deleteMovement(movement.id)
            try await reloadAll()
        }
        if done { lastDeleted = movement }
        return done
    }

    /// Vuelve a apuntar el último borrado (con otro id).
    func undoDelete() async {
        guard let movement = lastDeleted else { return }
        lastDeleted = nil
        await add(MovementDraft(accountId: movement.accountId, categoryId: movement.categoryId,
                                bookedOn: movement.bookedOn, amount: movement.amount,
                                description: movement.description, notes: movement.notes,
                                importHash: movement.importHash, excluded: movement.excluded,
                                payee: movement.payee, tags: movement.tags))
    }

    /// «Actualizar saldo»: apunta un ajuste para que el saldo de la cuenta sea `actual`.
    /// Devuelve true también si ya coincidía (no hace falta apuntar nada).
    @discardableResult
    func adjustBalance(of account: Account, to actual: Money, on day: CalendarDay = CalendarDay()) async -> Bool {
        guard let draft = BalanceAdjustment.draft(account: account, current: balance(of: account), actual: actual,
                                                  on: day, categories: categories) else { return true }
        return await add(draft)
    }

    var archivedAccounts: [Account] { accounts.filter(\.isArchived) }

    /// Transferencia entre dos cuentas: dos movimientos con la categoría de transferencia, que no cuentan como gasto.
    @discardableResult
    func transfer(from: Account, to: Account, amount: Money, on day: CalendarDay, description: String) async -> Bool {
        guard from.id != to.id else { error = "Elige dos cuentas distintas."; return false }
        guard amount.minor > 0 else { error = "El importe tiene que ser mayor que cero."; return false }
        let category = categories(for: .transfer).first?.id
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = text.isEmpty ? "Transferencia" : text
        return await perform {
            _ = try await service.addMovement(MovementDraft(accountId: from.id, categoryId: category, bookedOn: day,
                                                            amount: -amount, description: title), in: household.id)
            _ = try await service.addMovement(MovementDraft(accountId: to.id, categoryId: category, bookedOn: day,
                                                            amount: amount, description: title), in: household.id)
            try await reloadAll()
        }
    }

    func importMovements(_ drafts: [MovementDraft]) async -> ImportResult? {
        var result: ImportResult?
        await perform {
            result = try await service.importMovements(drafts, in: household.id)
            try await reloadAll()
        }
        return result
    }

    @discardableResult
    func save(_ category: BudgetCategory) async -> Bool {
        if let issue = category.issue(among: categories) {
            error = issue
            return false
        }
        return await perform {
            if categories.contains(where: { $0.id == category.id }) {
                _ = try await service.updateCategory(category)
            } else {
                _ = try await service.createCategory(category)
            }
            categories = try await service.categories(in: household.id)
        }
    }

    @discardableResult
    func delete(_ category: BudgetCategory) async -> Bool {
        await perform {
            try await service.deleteCategory(category.id)
            categories = try await service.categories(in: household.id)
            try await reloadAll()
        }
    }

    /// Cuántos de los movimientos recientes usan esa categoría, para avisar antes de borrarla.
    func recentUses(of category: BudgetCategory) -> Int {
        recent.filter { $0.categoryId == category.id }.count
    }

    /// El CSV con todos los movimientos del hogar, listo para Excel.
    func exportCSV() async -> Data? {
        var data: Data?
        await perform {
            let all = try await service.allMovements(in: household.id)
            data = MovementsCSV.data(all, accounts: accounts, categories: categories)
        }
        return data
    }

    /// Borra todo lo apuntado en el hogar y vuelve a cargar.
    @discardableResult
    func resetHousehold() async -> Bool {
        guard await perform({ try await service.resetHousehold(household.id) }) else { return false }
        await load()
        return true
    }

    private func reloadAccounts() async throws {
        let service = service, id = household.id
        async let accounts = service.accounts(in: id)
        async let balances = service.balances(in: id)
        (self.accounts, self.balances) = try await (accounts, balances)
    }

    private func reloadAll() async throws {
        try await reloadAccounts()
        recent = try await service.movements(in: household.id, accountId: nil, limit: Self.recentLimit)
    }

    /// Ejecuta la operación y deja el error en español en `error`. Devuelve si fue bien.
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
