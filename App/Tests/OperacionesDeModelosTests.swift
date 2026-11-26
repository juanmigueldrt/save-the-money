import XCTest
import STMCore
@testable import SaveTheMoney

/// Retiene la primera llamada que pasa por aquí hasta que la prueba la suelta: así se decide qué respuesta llega antes.
private actor Puerta {
    private var usada = false
    private var retenida: CheckedContinuation<Void, any Error>?
    private var aviso: CheckedContinuation<Void, Never>?

    /// La primera llamada espera a `abrir`; las demás pasan sin esperar.
    func pasar() async throws {
        guard !usada else { return }
        usada = true
        aviso?.resume()
        aviso = nil
        try await withCheckedThrowingContinuation { retenida = $0 }
    }

    /// Vuelve cuando la primera llamada ya está retenida.
    func llegada() async {
        guard !usada else { return }
        await withCheckedContinuation { aviso = $0 }
    }

    /// Suelta la llamada retenida con su respuesta o, con `error`, fallando.
    func abrir(fallando error: (any Error)? = nil) {
        if let error { retenida?.resume(throwing: error) } else { retenida?.resume() }
        retenida = nil
    }
}

/// El servicio de presupuesto en memoria, pero la primera lectura de movimientos se lee en su momento y se
/// entrega cuando la prueba abre la puerta: es una respuesta antigua que llega tarde.
private final class PresupuestoConPuerta: BudgetService {
    let backend: InMemoryBackend
    let puerta = Puerta()

    init(_ backend: InMemoryBackend) { self.backend = backend }

    func budget(startingOn day: CalendarDay, in householdId: UUID) async throws -> Budget? {
        try await backend.budget(startingOn: day, in: householdId)
    }
    func latestBudget(before day: CalendarDay, in householdId: UUID) async throws -> Budget? {
        try await backend.latestBudget(before: day, in: householdId)
    }
    func saveBudget(_ budget: Budget) async throws -> Budget { try await backend.saveBudget(budget) }
    func paySchedule() async throws -> PaySchedule? { try await backend.paySchedule() }
    func savePaySchedule(_ schedule: PaySchedule) async throws -> PaySchedule { try await backend.savePaySchedule(schedule) }
    func extraBudgets(in householdId: UUID) async throws -> [ExtraBudget] { try await backend.extraBudgets(in: householdId) }
    func saveExtraBudget(_ budget: ExtraBudget) async throws -> ExtraBudget { try await backend.saveExtraBudget(budget) }
    func deleteExtraBudget(_ id: UUID) async throws { try await backend.deleteExtraBudget(id) }
    func movements(in householdId: UUID, from: CalendarDay, through: CalendarDay) async throws -> [Movement] {
        let list = try await backend.movements(in: householdId, from: from, through: through)
        try await puerta.pasar()
        return list
    }
}

private let mensajeSinRed = AppError.network.errorDescription ?? ""
private let mensajeDesconocido = AppError.unknown("").errorDescription ?? ""

/// El ayudante común de los modelos (ORC-100): tareas canceladas y respuestas que se cruzan (ORC-87), y una
/// recarga que falla después de guardar bien (ORC-141).
@MainActor
final class OperacionesDeModelosTests: XCTestCase {
    private struct Hogar {
        let backend: InMemoryBackend
        let home: Household
        let finance: FinanceModel
        let account: Account
    }

    private let hoy = CalendarDay(year: 2026, month: 11, day: 5) ?? CalendarDay()

    private func hogar() async throws -> Hogar {
        let services = AppServices.demo()
        let session = SessionModel(services: services)
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        try await session.createHousehold(name: "Casa de prueba")
        guard case .ready(_, let home) = session.state else { throw AppError.unknown("sin hogar") }
        let backend = try XCTUnwrap(services.finance as? InMemoryBackend)
        let finance = FinanceModel(household: home, service: services.finance)
        _ = await finance.createAccount(AccountDraft(name: "Corriente", openingBalance: Money(minor: 100_000)))
        return Hogar(backend: backend, home: home, finance: finance, account: try XCTUnwrap(finance.activeAccounts.first))
    }

    private func cafe(_ account: Account) -> MovementDraft {
        MovementDraft(accountId: account.id, bookedOn: hoy, amount: Money(minor: -1_250), description: "Café de prueba")
    }

    private func presupuesto(_ hogar: Hogar) -> (BudgetModel, Puerta) {
        let service = PresupuestoConPuerta(hogar.backend)
        let hoy = hoy
        return (BudgetModel(household: hogar.home, service: service, today: { hoy }), service.puerta)
    }

    // MARK: ORC-87

    func testCargaCanceladaQueFallaNoEscribeError() async throws {
        let hogar = try await hogar()
        let (budgets, puerta) = presupuesto(hogar)

        let carga = Task { await budgets.load() }
        await puerta.llegada()
        carga.cancel()
        await puerta.abrir(fallando: AppError.network)
        await carga.value

        XCTAssertNil(budgets.error, "la tarea cancelada no deja su error en pantalla")
    }

    func testCargaCanceladaQueAcabaBienNoEscribeDatos() async throws {
        let hogar = try await hogar()
        _ = await hogar.finance.add(cafe(hogar.account))
        let (budgets, puerta) = presupuesto(hogar)

        let carga = Task { await budgets.load() }
        await puerta.llegada()
        carga.cancel()
        await puerta.abrir()
        await carga.value

        XCTAssertEqual(budgets.movements, [], "la tarea cancelada no guarda lo que ha traído")
    }

    func testUnaRespuestaAntiguaNoPisaUnaMasNueva() async throws {
        let hogar = try await hogar()
        let (budgets, puerta) = presupuesto(hogar)

        // La primera carga lee sin movimientos y su respuesta se queda en camino.
        let antigua = Task { await budgets.load() }
        await puerta.llegada()

        // Mientras, se apunta un gasto y una carga nueva lo trae.
        _ = await hogar.finance.add(cafe(hogar.account))
        await budgets.load()
        XCTAssertEqual(budgets.movements.map(\.description), ["Café de prueba"])

        await puerta.abrir()
        await antigua.value
        XCTAssertEqual(budgets.movements.map(\.description), ["Café de prueba"], "la respuesta antigua no pisa la nueva")
    }

    func testUnFalloAntiguoNoPisaUnaCargaMasNuevaQueFueBien() async throws {
        let hogar = try await hogar()
        let (budgets, puerta) = presupuesto(hogar)

        let antigua = Task { await budgets.load() }
        await puerta.llegada()
        await budgets.load()
        XCTAssertNil(budgets.error)

        await puerta.abrir(fallando: AppError.network)
        await antigua.value
        XCTAssertNil(budgets.error, "lo que hay en pantalla es de la carga nueva, que fue bien")
    }

    /// RootView vuelve a cargar presupuesto y tarjetas cuando cambia `Inputs`; antes de la primera carga de
    /// FinanceModel no hace nada. Con un hogar vacío, terminar esa carga también tiene que cambiar `Inputs`.
    func testLaPrimeraCargaCambiaLasEntradasAunqueNoHayaDatos() async throws {
        let services = AppServices.demo()
        let session = SessionModel(services: services)
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        try await session.createHousehold(name: "Casa vacía")
        guard case .ready(_, let home) = session.state else { throw AppError.unknown("sin hogar") }
        let finance = FinanceModel(household: home, service: services.finance)

        let antes = CreditCardModel.Inputs(finance: finance)
        XCTAssertFalse(finance.hasLoaded)
        await finance.load()
        XCTAssertTrue(finance.hasLoaded)
        XCTAssertNotEqual(CreditCardModel.Inputs(finance: finance), antes)
    }

    // MARK: ORC-141

    func testSiFallaLaRecargaTrasGuardarElGuardadoCuentaComoHecho() async throws {
        let hogar = try await hogar()
        _ = await hogar.finance.add(cafe(hogar.account))
        var cambiado = try XCTUnwrap(hogar.finance.recent.first)
        cambiado.amount = Money(minor: -3_000)

        await hogar.backend.failCalls("movements(in:accountId:limit:)")
        let guardado = await hogar.finance.update(cambiado)
        XCTAssertTrue(guardado, "el cambio está guardado: el formulario se cierra y no invita a guardarlo otra vez")
        XCTAssertEqual(hogar.finance.error, mensajeSinRed, "el fallo se ve como problema de carga")

        await hogar.backend.clearFailures()
        let enServidor = try await hogar.backend.movements(in: hogar.home.id, accountId: nil, limit: 10)
        XCTAssertEqual(enServidor.map(\.amount), [Money(minor: -3_000)])
        await hogar.finance.load()
        XCTAssertNil(hogar.finance.error, "se reintenta cargando")
        XCTAssertEqual(hogar.finance.recent.map(\.amount), [Money(minor: -3_000)])
    }

    func testCategoriaGuardadaSeVeAunqueFalleLaRecarga() async throws {
        let hogar = try await hogar()
        let mascotas = BudgetCategory(householdId: hogar.home.id, name: "Mascotas")

        await hogar.backend.failCalls("categories(in:)")
        let guardada = await hogar.finance.save(mascotas)
        XCTAssertTrue(guardada)
        XCTAssertEqual(hogar.finance.error, mensajeSinRed)
        XCTAssertTrue(hogar.finance.categories.contains { $0.name == "Mascotas" }, "se ve ya, aunque falle la recarga")
    }

    func testSiFallanLaEscrituraYLaRecargaSeVenLosDosErrores() async throws {
        let hogar = try await hogar()
        _ = await hogar.finance.createAccount(AccountDraft(name: "Ahorro"))
        let ahorro = try XCTUnwrap(hogar.finance.activeAccounts.first { $0.name == "Ahorro" })

        await hogar.backend.failCalls("addTransfer(_:in:)")
        await hogar.backend.failCalls("accounts(in:)", with: AppError.unknown("recarga"))
        let hecha = await hogar.finance.transfer(from: hogar.account, to: ahorro, amount: Money(minor: 5_000), on: hoy,
                                                 description: "Ahorro del mes")
        XCTAssertFalse(hecha, "la transferencia no se ha guardado: el formulario sigue abierto")
        XCTAssertEqual(hogar.finance.error,
                       mensajeSinRed + " Además, no se han podido volver a cargar los datos: " + mensajeDesconocido)
    }
}
