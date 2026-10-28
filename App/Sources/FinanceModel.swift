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

    @discardableResult
    func delete(_ movement: Movement) async -> Bool {
        await perform {
            try await service.deleteMovement(movement.id)
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
