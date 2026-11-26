import Foundation
import Observation
import STMCore

/// Cuentas, saldos, categorías y movimientos del hogar abierto.
/// Las pantallas leen de aquí y llaman a sus métodos para cambiar datos.
@Observable
@MainActor
final class FinanceModel: ServerModel {
    let household: Household
    private let service: any FinanceService

    private(set) var accounts: [Account] = []
    private(set) var balances: [UUID: Money] = [:]
    private(set) var categories: [BudgetCategory] = []
    private(set) var recent: [Movement] = []
    var isLoading = false
    /// La primera carga ya ha terminado (bien o mal). Antes, RootView no carga lo que depende de ella.
    private(set) var hasLoaded = false
    var error: String?
    @ObservationIgnored var turns = ReadTurns()

    /// Movimientos recientes que se cargan para resúmenes, sugerencias y pagos fijos (la lista va por páginas).
    nonisolated static let recentLimit = 500

    /// La lista de Movimientos que se ve (la general o la de una cuenta), por páginas y con la búsqueda hecha en el
    /// servidor (ORC-85). Va aparte de `recent`: saldos, resúmenes y sugerencias siguen viendo lo mismo que antes.
    private(set) var list = MovementList()
    /// Por qué no se ha podido cargar la lista o su página siguiente. Lo ya cargado se queda.
    private(set) var listError: String?
    /// true mientras se carga la lista o una página.
    private(set) var isLoadingList = false
    @ObservationIgnored private var listLoads = 0
    /// La lista se ha abierto alguna vez: desde entonces se recarga con cada cambio.
    @ObservationIgnored private var listShown = false
    /// Filas por página de la lista.
    nonisolated static let listPageSize = 200

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
        beginLoad()
        defer { endLoad() }
        let service = service, id = household.id, turn = nextTurn()
        await perform(turn: turn) {
            async let accounts = service.accounts(in: id)
            async let balances = service.balances(in: id)
            async let categories = service.categories(in: id)
            async let recent = service.movements(in: id, accountId: nil, limit: Self.recentLimit)
            let loaded = try await (accounts, balances, categories, recent)
            store(loaded.0, in: \.accounts, turn: turn)
            store(loaded.1, in: \.balances, turn: turn)
            store(loaded.2, in: \.categories, turn: turn)
            store(loaded.3, in: \.recent, turn: turn)
        }
        if !Task.isCancelled { hasLoaded = true }
        await reloadList()
    }

    /// Los últimos movimientos de la cuenta, para su gráfico. Lanza el error: la pantalla distingue «sin
    /// movimientos» de «no se han podido cargar».
    func movements(of account: Account) async throws -> [Movement] {
        try await service.movements(in: household.id, accountId: account.id, limit: Self.recentLimit)
    }

    /// Enseña la lista de esa cuenta (nil: todas) con esa búsqueda. Si es otra lista empieza de cero; si es la misma,
    /// vuelve a cargar lo que ya se veía.
    func showList(accountId: UUID?, search: String) async {
        listShown = true
        if list.accountId != accountId || list.search != search {
            // Desde aquí, una lectura de la lista anterior que llegue tarde ya no la pisa.
            markChanged(\.list)
            list = MovementList(accountId: accountId, search: search)
            markChanged(\.listError)
            listError = nil
        }
        await reloadList()
    }

    /// La página siguiente, al llegar al final. Si falla, lo cargado se queda, `listError` lo dice y se puede
    /// volver a pedir. No pide nada mientras otra lectura de la lista está en marcha: empezaría en un sitio viejo.
    func loadMoreList() async {
        guard list.hasMore, listLoads == 0, let last = list.rows.last else { return }
        let base = list
        await readList { [self] in
            let page = try await fetchList(base, after: last, count: Self.listPageSize)
            return MovementList(accountId: base.accountId, search: base.search, rows: base.rows + page.rows, hasMore: page.hasMore)
        }
    }

    /// «Reintentar»: vuelve a cargar lo que había y una página más.
    func retryList() async {
        await reloadList(extra: Self.listPageSize)
    }

    /// Vuelve a pedir la lista abierta desde el principio, tantas filas como se veían (como poco una página).
    private func reloadList(extra: Int = 0) async {
        guard listShown else { return }
        let current = list
        await readList { [self] in
            let page = try await fetchList(current, after: nil, count: max(current.rows.count + extra, Self.listPageSize))
            return MovementList(accountId: current.accountId, search: current.search, rows: page.rows, hasMore: page.hasMore)
        }
    }

    /// Una lectura de la lista con su turno: lo que trae (o su error) sólo se guarda si nada que empezó después lo ha
    /// guardado ya. Un fallo deja la lista como estaba.
    private func readList(_ read: () async throws -> MovementList) async {
        let turn = nextTurn()
        listLoads += 1
        isLoadingList = true
        defer {
            listLoads -= 1
            isLoadingList = listLoads > 0
        }
        do {
            let loaded = try await read()
            store(loaded, in: \.list, turn: turn)
            store(nil, in: \.listError, turn: turn)
        } catch {
            guard let message = Self.message(for: error) else { return }
            store("No se han podido cargar los movimientos. " + message, in: \.listError, turn: turn)
        }
    }

    /// Pide al menos `count` filas detrás de `after`, página a página, hasta tenerlas o llegar al final. Cada página
    /// es de `listPageSize`: una que llega incompleta es el final; una llena dice que puede haber más.
    private func fetchList(_ list: MovementList, after: Movement?, count: Int) async throws -> (rows: [Movement], hasMore: Bool) {
        let search = MovementSearch(list.search, categories: categories)
        var rows: [Movement] = []
        var cursor = after
        while true {
            let page = try await service.movements(in: household.id, accountId: list.accountId, search: search,
                                                    after: cursor, limit: Self.listPageSize)
            rows += page
            if page.count < Self.listPageSize { return (rows, false) }
            if rows.count >= count { return (rows, true) }
            cursor = page.last
        }
    }

    @discardableResult
    func createAccount(_ draft: AccountDraft) async -> Bool {
        await write({ _ = try await service.createAccount(draft, in: household.id) }, thenReload: reloadAccounts)
    }

    @discardableResult
    func updateAccount(_ account: Account) async -> Bool {
        await write({ _ = try await service.updateAccount(account) }, thenReload: reloadAccounts)
    }

    @discardableResult
    func deleteAccount(_ account: Account) async -> Bool {
        await perform {
            try await service.deleteAccount(account.id)
            await reloadAfterSave { try await reloadAll() }
        }
    }

    @discardableResult
    func add(_ draft: MovementDraft) async -> Bool {
        await addMovement(draft) != nil
    }

    /// Como `add`, pero devuelve el movimiento creado (para aplazarlo o hacerlo recurrente).
    func addMovement(_ draft: MovementDraft) async -> Movement? {
        var created: Movement?
        _ = await perform {
            created = try await service.addMovement(draft, in: household.id)
            await reloadAfterSave { try await reloadAll() }
        }
        return created
    }

    @discardableResult
    func update(_ movement: Movement) async -> Bool {
        await update([movement])
    }

    /// Guarda varios movimientos ya cambiados (edición masiva, «cambiar similares»). Recarga una vez al final.
    @discardableResult
    func update(_ movements: [Movement]) async -> Bool {
        guard !movements.isEmpty else { return true }
        let saved = await perform {
            // Guardar una pata de transferencia cambia también la otra (importe y día): si la otra también está en la
            // lista, se guarda sobre su versión nueva, que ya trae lo mismo, en vez de fallar como si la hubiera
            // cambiado otro dispositivo.
            var versions: [UUID: String?] = [:]
            for var movement in movements {
                if let version = versions[movement.id] { movement.updatedAt = version }
                let saved = try await service.updateMovement(movement)
                let pairs = movements.filter { $0.transferId != nil && $0.transferId == saved.transferId && $0.id != saved.id }
                guard !pairs.isEmpty else { continue }
                for pair in try await service.movements(in: household.id, ids: pairs.map(\.id)) {
                    versions[pair.id] = pair.updatedAt
                }
            }
            await reloadAfterSave { try await reloadAll() }
        }
        // Si otro dispositivo cambió alguno antes, se recarga para que se vea lo nuevo detrás del aviso.
        if !saved { await reloadAfterSave { try await reloadAll() } }
        return saved
    }

    /// Borra varios a la vez (sin «Deshacer»: la vista pide confirmación antes).
    /// Una pata de transferencia se lleva la otra, aunque no esté en la lista.
    @discardableResult
    func delete(_ movements: [Movement]) async -> Bool {
        await perform {
            var transfers = Set<UUID>()
            for movement in movements {
                if let transferId = movement.transferId {
                    if transfers.insert(transferId).inserted { try await service.deleteTransfer(transferId) }
                } else {
                    try await service.deleteMovement(movement.id)
                }
            }
            await reloadAfterSave { try await reloadAll() }
        }
    }

    /// La cuenta que sale elegida al apuntar: la predeterminada o la primera activa.
    var defaultAccount: Account? { accounts.defaultAccount }

    /// Etiquetas y beneficiarios usados, para sugerir al escribir.
    var knownTags: [String] { MovementTags.all(in: recent) }
    var knownPayees: [String] { Payee.all(in: recent) }

    /// El último movimiento borrado, para «Deshacer» (como en Android).
    var lastDeleted: Movement?

    /// Una pata de transferencia se borra con la otra y sin «Deshacer», que solo volvería a apuntar una.
    @discardableResult
    func delete(_ movement: Movement) async -> Bool {
        let done = await perform {
            if let transferId = movement.transferId {
                try await service.deleteTransfer(transferId)
            } else {
                try await service.deleteMovement(movement.id)
            }
            await reloadAfterSave { try await reloadAll() }
        }
        if done { lastDeleted = movement.transferId == nil ? movement : nil }
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
    /// Se guardan los dos o ninguno. Con el mismo `id` (uno por formulario) reintentar no duplica.
    /// `toDescription` es el concepto de la entrada cuando no es el mismo que el de la salida (pago de tarjeta).
    @discardableResult
    func transfer(id: UUID = UUID(), from: Account, to: Account, amount: Money, on day: CalendarDay,
                  description: String, toDescription: String? = nil) async -> Bool {
        guard from.id != to.id else { error = "Elige dos cuentas distintas."; return false }
        guard amount.minor > 0 else { error = "El importe tiene que ser mayor que cero."; return false }
        let category = categories(for: .transfer).first?.id
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = text.isEmpty ? "Transferencia" : text
        let saved = await perform {
            let draft = TransferDraft(id: id, fromAccountId: from.id, toAccountId: to.id, categoryId: category, bookedOn: day,
                                      amount: amount, fromDescription: title, toDescription: toDescription ?? title)
            _ = try await service.addTransfer(draft, in: household.id)
            await reloadAfterSave { try await reloadAll() }
        }
        // Si falla puede que ya estuviera guardada (con otros datos): se recarga para que se vea detrás del aviso.
        if !saved { await reloadAfterSave { try await reloadAll() } }
        return saved
    }

    func importMovements(_ drafts: [MovementDraft]) async -> ImportResult? {
        var result: ImportResult?
        await perform {
            result = try await service.importMovements(drafts, in: household.id)
            await reloadAfterSave { try await reloadAll() }
        }
        return result
    }

    /// Una categoría sin versión (`updatedAt`) aún no se ha leído del servidor: es un alta, con el id que le dio el
    /// formulario, y guardarla otra vez con el mismo no crea otra. Con versión es un cambio sobre esa versión.
    @discardableResult
    func save(_ category: BudgetCategory) async -> Bool {
        if let issue = category.issue(among: categories) {
            error = issue
            return false
        }
        let ok = await perform {
            let saved = category.updatedAt == nil
                ? try await service.createCategory(category)
                : try await service.updateCategory(category)
            // Se ve ya, aunque falle la recarga.
            markChanged(\.categories)
            categories.removeAll { $0.id == category.id || $0.id == saved.id }
            categories.append(saved)
            await reloadAfterSave { try await reloadCategories() }
        }
        // Si otro dispositivo la cambió antes, se recarga para que se vea lo nuevo detrás del aviso.
        if !ok { await reloadAfterSave(reloadCategories) }
        return ok
    }

    @discardableResult
    func delete(_ category: BudgetCategory) async -> Bool {
        await perform {
            try await service.deleteCategory(category.id)
            markChanged(\.categories)
            categories.removeAll { $0.id == category.id }
            await reloadAfterSave {
                try await reloadCategories()
                try await reloadAll()
            }
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
        let service = service, id = household.id, turn = nextTurn()
        async let accounts = service.accounts(in: id)
        async let balances = service.balances(in: id)
        let loaded = try await (accounts, balances)
        store(loaded.0, in: \.accounts, turn: turn)
        store(loaded.1, in: \.balances, turn: turn)
    }

    private func reloadAll() async throws {
        try await reloadAccounts()
        let turn = nextTurn()
        let movements = try await service.movements(in: household.id, accountId: nil, limit: Self.recentLimit)
        store(movements, in: \.recent, turn: turn)
        // Lo cambiado puede estar en una página de la lista que no entra en `recent`.
        await reloadList()
    }

    private func reloadCategories() async throws {
        let turn = nextTurn()
        let list = try await service.categories(in: household.id)
        store(list, in: \.categories, turn: turn)
    }
}

/// Lo que se ve en la lista de Movimientos: de qué cuenta (nil: todas), qué se busca y las filas cargadas, en el
/// orden del servidor.
struct MovementList: Equatable {
    var accountId: UUID?
    var search = ""
    var rows: [Movement] = []
    /// Puede haber más en el servidor: la última página llegó llena.
    var hasMore = false
}
