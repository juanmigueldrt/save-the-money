import XCTest
import STMCore
@testable import SaveTheMoney

/// Retiene la primera lectura de la lista que cumple `retener` hasta que la prueba la suelta: es una respuesta
/// antigua que llega tarde.
private actor PuertaDeLista {
    private var usada = false
    private var retenida: CheckedContinuation<Void, Never>?
    private var aviso: CheckedContinuation<Void, Never>?

    func pasar() async {
        guard !usada else { return }
        usada = true
        aviso?.resume()
        aviso = nil
        await withCheckedContinuation { retenida = $0 }
    }

    func llegada() async {
        guard !usada else { return }
        await withCheckedContinuation { aviso = $0 }
    }

    func abrir() {
        retenida?.resume()
        retenida = nil
    }
}

/// El servicio en memoria, pero la primera página de la lista que cumple `retener` se lee en su momento y se entrega
/// cuando la prueba abre la puerta.
private final class ListaConPuerta: FinanceService, @unchecked Sendable {
    let backend: InMemoryBackend
    let puerta = PuertaDeLista()
    let retener: @Sendable (_ search: MovementSearch?, _ after: Movement?) -> Bool

    init(_ backend: InMemoryBackend, retener: @escaping @Sendable (MovementSearch?, Movement?) -> Bool) {
        self.backend = backend
        self.retener = retener
    }

    func movements(in householdId: UUID, accountId: UUID?, search: MovementSearch?, after: Movement?,
                   limit: Int) async throws -> [Movement] {
        let page = try await backend.movements(in: householdId, accountId: accountId, search: search, after: after, limit: limit)
        if retener(search, after) { await puerta.pasar() }
        return page
    }

    func accounts(in householdId: UUID) async throws -> [Account] { try await backend.accounts(in: householdId) }
    func balances(in householdId: UUID) async throws -> [UUID: Money] { try await backend.balances(in: householdId) }
    func createAccount(_ draft: AccountDraft, in householdId: UUID) async throws -> Account {
        try await backend.createAccount(draft, in: householdId)
    }
    func updateAccount(_ account: Account) async throws -> Account { try await backend.updateAccount(account) }
    func deleteAccount(_ accountId: UUID) async throws { try await backend.deleteAccount(accountId) }
    func categories(in householdId: UUID) async throws -> [BudgetCategory] { try await backend.categories(in: householdId) }
    func createCategory(_ category: BudgetCategory) async throws -> BudgetCategory { try await backend.createCategory(category) }
    func updateCategory(_ category: BudgetCategory) async throws -> BudgetCategory { try await backend.updateCategory(category) }
    func deleteCategory(_ categoryId: UUID) async throws { try await backend.deleteCategory(categoryId) }
    func resetHousehold(_ householdId: UUID) async throws { try await backend.resetHousehold(householdId) }
    func movements(in householdId: UUID, accountId: UUID?, limit: Int) async throws -> [Movement] {
        try await backend.movements(in: householdId, accountId: accountId, limit: limit)
    }
    func movements(in householdId: UUID, ids: [UUID]) async throws -> [Movement] {
        try await backend.movements(in: householdId, ids: ids)
    }
    func movements(in householdId: UUID, accountId: UUID, since: CalendarDay, limit: Int) async throws -> [Movement] {
        try await backend.movements(in: householdId, accountId: accountId, since: since, limit: limit)
    }
    func allMovements(in householdId: UUID) async throws -> [Movement] { try await backend.allMovements(in: householdId) }
    func addMovement(_ draft: MovementDraft, in householdId: UUID) async throws -> Movement {
        try await backend.addMovement(draft, in: householdId)
    }
    func addTransfer(_ transfer: TransferDraft, in householdId: UUID) async throws -> [Movement] {
        try await backend.addTransfer(transfer, in: householdId)
    }
    func updateMovement(_ movement: Movement) async throws -> Movement { try await backend.updateMovement(movement) }
    func deleteMovement(_ movementId: UUID) async throws { try await backend.deleteMovement(movementId) }
    func deleteTransfer(_ transferId: UUID) async throws { try await backend.deleteTransfer(transferId) }
    func importMovements(_ drafts: [MovementDraft], in householdId: UUID) async throws -> ImportResult {
        try await backend.importMovements(drafts, in: householdId)
    }
}

/// ORC-85: la lista de movimientos se carga por páginas y busca en el servidor, sin pisar lo nuevo con lo viejo.
/// Datos inventados.
@MainActor
final class ListaPaginadaAppTests: XCTestCase {
    private struct Hogar {
        let backend: InMemoryBackend
        let home: Household
        let account: Account
    }

    private let pagina = FinanceModel.listPageSize
    private let operacion = "movements(in:accountId:search:after:limit:)"

    /// Un hogar con `count` gastos recientes («Gasto n») y, si se pide, uno muy antiguo («Panadería antigua»).
    private func hogar(count: Int, antiguo: Bool = false) async throws -> Hogar {
        let services = AppServices.demo()
        let session = SessionModel(services: services)
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        try await session.createHousehold(name: "Casa de prueba")
        guard case .ready(_, let home) = session.state else { throw AppError.unknown("sin hogar") }
        let backend = try XCTUnwrap(services.finance as? InMemoryBackend)
        let account = try await backend.createAccount(AccountDraft(name: "Corriente"), in: home.id)
        let start = try XCTUnwrap(CalendarDay(year: 2026, month: 1, day: 1))
        var drafts = (0..<count).map {
            MovementDraft(accountId: account.id, bookedOn: start.adding(days: $0 % 300), amount: Money(minor: -100 - $0),
                          description: "Gasto \($0)", importHash: "h\($0)")
        }
        if antiguo {
            drafts.append(MovementDraft(accountId: account.id, bookedOn: try XCTUnwrap(CalendarDay(year: 2019, month: 5, day: 1)),
                                        amount: Money(minor: -350), description: "Panadería antigua", importHash: "viejo"))
        }
        _ = try await backend.importMovements(drafts, in: home.id)
        return Hogar(backend: backend, home: home, account: account)
    }

    func testCargaMasAlLlegarAlFinal() async throws {
        let hogar = try await hogar(count: pagina + 5)
        let finance = FinanceModel(household: hogar.home, service: hogar.backend)

        await finance.showList(accountId: nil, search: "")
        XCTAssertEqual(finance.list.rows.count, pagina)
        XCTAssertTrue(finance.list.hasMore)

        await finance.loadMoreList()
        XCTAssertEqual(finance.list.rows.count, pagina + 5)
        XCTAssertEqual(Set(finance.list.rows.map(\.id)).count, pagina + 5, "ninguna fila repetida")
        XCTAssertFalse(finance.list.hasMore)
        XCTAssertNil(finance.listError)
    }

    func testUnaPaginaQueFallaAvisaYNoPareceElFinal() async throws {
        let hogar = try await hogar(count: pagina + 5)
        let finance = FinanceModel(household: hogar.home, service: hogar.backend)
        await finance.showList(accountId: nil, search: "")
        let cargadas = finance.list.rows

        await hogar.backend.failCalls(operacion)
        await finance.loadMoreList()
        XCTAssertEqual(finance.list.rows, cargadas, "lo cargado se queda")
        XCTAssertTrue(finance.list.hasMore, "no parece el final de la lista")
        XCTAssertNotNil(finance.listError)

        await hogar.backend.clearFailures()
        await finance.retryList()
        XCTAssertEqual(finance.list.rows.count, pagina + 5)
        XCTAssertNil(finance.listError)
    }

    func testLaBusquedaEncuentraFueraDeLaPrimeraPagina() async throws {
        let hogar = try await hogar(count: FinanceModel.recentLimit + 10, antiguo: true)
        let finance = FinanceModel(household: hogar.home, service: hogar.backend)
        await finance.load()
        XCTAssertFalse(finance.recent.contains { $0.description == "Panadería antigua" }, "no está entre los recientes")

        await finance.showList(accountId: nil, search: "  panadería ")
        XCTAssertEqual(finance.list.rows.map(\.description), ["Panadería antigua"])
        XCTAssertFalse(finance.list.hasMore)
    }

    func testLaListaDeUnaCuentaSoloTraeEsaCuenta() async throws {
        let hogar = try await hogar(count: 3)
        let other = try await hogar.backend.createAccount(AccountDraft(name: "Ahorro"), in: hogar.home.id)
        _ = try await hogar.backend.addMovement(MovementDraft(accountId: other.id, bookedOn: CalendarDay(), amount: Money(minor: 500),
                                                              description: "Ingreso"), in: hogar.home.id)
        let finance = FinanceModel(household: hogar.home, service: hogar.backend)
        await finance.showList(accountId: other.id, search: "")
        XCTAssertEqual(finance.list.rows.map(\.accountId), [other.id])
    }

    func testUnaBusquedaViejaNoPisaLaNueva() async throws {
        let hogar = try await hogar(count: 3, antiguo: true)
        let service = ListaConPuerta(hogar.backend) { search, _ in search?.text == "gasto" }
        let finance = FinanceModel(household: hogar.home, service: service)

        let vieja = Task { await finance.showList(accountId: nil, search: "gasto") }
        await service.puerta.llegada()
        await finance.showList(accountId: nil, search: "panadería")
        await service.puerta.abrir()
        await vieja.value

        XCTAssertEqual(finance.list.search, "panadería")
        XCTAssertEqual(finance.list.rows.map(\.description), ["Panadería antigua"], "la respuesta de «gasto» llegó tarde y no cuenta")
    }

    func testUnaPaginaViejaNoPisaLaListaRecargada() async throws {
        let hogar = try await hogar(count: pagina + 5)
        let service = ListaConPuerta(hogar.backend) { _, after in after != nil }
        let finance = FinanceModel(household: hogar.home, service: service)
        await finance.showList(accountId: nil, search: "")

        let pagina = Task { await finance.loadMoreList() }
        await service.puerta.llegada()
        // Mientras tanto se apunta uno nuevo: la recarga trae la lista al día.
        _ = await finance.add(MovementDraft(accountId: hogar.account.id, bookedOn: try XCTUnwrap(CalendarDay(year: 2027, month: 1, day: 1)),
                                            amount: Money(minor: -1), description: "Nuevo"))
        let recargada = finance.list
        XCTAssertEqual(recargada.rows.first?.description, "Nuevo")
        await service.puerta.abrir()
        await pagina.value

        XCTAssertEqual(finance.list, recargada, "la página pedida antes de la recarga llegó tarde y no cuenta")
    }
}
