import XCTest
import STMCore
@testable import SaveTheMoney

/// Guardar dos veces el mismo formulario no duplica, y un cambio sobre una versión antigua avisa y recarga (ORC-69).
@MainActor
final class EscriturasIdempotentesTests: XCTestCase {
    private struct Hogar {
        let backend: InMemoryBackend
        let finance: FinanceModel
        let account: Account
    }

    private func hogar() async throws -> Hogar {
        let services = AppServices.demo()
        let session = SessionModel(services: services)
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        try await session.createHousehold(name: "Casa de prueba")
        guard case .ready(_, let home) = session.state else { throw AppError.unknown("sin hogar") }
        let backend = try XCTUnwrap(services.finance as? InMemoryBackend)
        let finance = FinanceModel(household: home, service: services.finance)
        _ = await finance.createAccount(AccountDraft(name: "Corriente", openingBalance: Money(minor: 100_000)))
        return Hogar(backend: backend, finance: finance, account: try XCTUnwrap(finance.activeAccounts.first))
    }

    private func cafe(_ account: Account) throws -> MovementDraft {
        MovementDraft(accountId: account.id, bookedOn: try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 5)),
                      amount: Money(minor: -1_250), description: "Café de prueba")
    }

    /// «Guardar» falla por la red y la persona vuelve a pulsarlo, una vez o varias, con el mismo formulario:
    /// es decir, con el mismo borrador y el mismo id. También vale si el primero sí llegó y solo se perdió la respuesta.
    func testGuardarOtraVezTrasUnFalloDeRedNoDuplica() async throws {
        let hogar = try await hogar()
        let (backend, finance) = (hogar.backend, hogar.finance)
        let account = hogar.account
        let draft = try cafe(account)

        await backend.failCalls("addMovement(_:in:)")
        let primera = await finance.add(draft)
        XCTAssertFalse(primera)
        XCTAssertEqual(finance.error, AppError.network.errorDescription)

        await backend.clearFailures()
        let segunda = await finance.add(draft)
        let tercera = await finance.add(draft)
        XCTAssertTrue(segunda)
        XCTAssertTrue(tercera, "repetirlo ya guardado no es un error")
        XCTAssertEqual(finance.recent.map(\.id), [draft.id], "queda una sola fila")
        XCTAssertEqual(finance.balance(of: account), Money(minor: 98_750), "y el dinero se descuenta una vez")
    }

    func testCambiarUnaVersionAntiguaAvisaYRecarga() async throws {
        let hogar = try await hogar()
        let (backend, finance) = (hogar.backend, hogar.finance)
        _ = await finance.add(try cafe(hogar.account))
        let leido = try XCTUnwrap(finance.recent.first)

        // Otro dispositivo lo cambia mientras este tiene abierta la versión anterior.
        var desdeOtro = leido
        desdeOtro.amount = Money(minor: -2_000)
        _ = try await backend.updateMovement(desdeOtro)

        var aqui = leido
        aqui.amount = Money(minor: -3_000)
        let guardado = await finance.update(aqui)
        XCTAssertFalse(guardado)
        XCTAssertEqual(finance.error, AppError.movementChanged.errorDescription)
        XCTAssertEqual(finance.recent.map(\.amount), [Money(minor: -2_000)], "se ve lo que guardó el otro dispositivo, no se pisa")

        // Con el movimiento recargado, el cambio entra.
        var recargado = try XCTUnwrap(finance.recent.first)
        recargado.amount = Money(minor: -3_000)
        let repetido = await finance.update(recargado)
        XCTAssertTrue(repetido)
        XCTAssertEqual(finance.recent.map(\.amount), [Money(minor: -3_000)])
    }

    // MARK: El resto de tablas (ORC-142)

    func testCuentaGuardarOtraVezNoDuplicaYUnaVersionAntiguaAvisaYRecarga() async throws {
        let hogar = try await hogar()
        let (backend, finance) = (hogar.backend, hogar.finance)
        // El formulario crea el borrador (y su id) una vez; cada «Guardar» manda el mismo.
        let draft = AccountDraft(name: "Ahorro", openingBalance: Money(minor: 5_000))
        await backend.failCalls("createAccount(_:in:)")
        let primera = await finance.createAccount(draft)
        XCTAssertFalse(primera)
        XCTAssertEqual(finance.error, AppError.network.errorDescription)
        await backend.clearFailures()
        let segunda = await finance.createAccount(draft)
        let tercera = await finance.createAccount(draft)
        XCTAssertTrue(segunda)
        XCTAssertTrue(tercera, "repetirlo ya guardado no es un error")
        XCTAssertEqual(finance.accounts.filter { $0.name == "Ahorro" }.map(\.id), [draft.id], "queda una sola cuenta")

        // Otro dispositivo la cambia mientras este tiene abierta la versión anterior.
        let leida = try XCTUnwrap(finance.account(draft.id))
        var desdeOtro = leida
        desdeOtro.name = "Vacaciones"
        _ = try await backend.updateAccount(desdeOtro)
        var aqui = leida
        aqui.openingBalance = Money(minor: 1)
        let guardado = await finance.updateAccount(aqui)
        XCTAssertFalse(guardado)
        XCTAssertEqual(finance.error, AppError.movementChanged.errorDescription)
        let recargada = try XCTUnwrap(finance.account(draft.id))
        XCTAssertEqual(recargada.name, "Vacaciones", "se ve lo que guardó el otro dispositivo")
        XCTAssertEqual(recargada.openingBalance, Money(minor: 5_000), "y no se pisa")
        var repetida = recargada
        repetida.openingBalance = Money(minor: 1)
        let repetido = await finance.updateAccount(repetida)
        XCTAssertTrue(repetido, "con la cuenta recargada, el cambio entra")
    }

    private func planning(_ hogar: Hogar) -> PlanningModel {
        PlanningModel(household: hogar.finance.household, recurring: hogar.backend, goals: hogar.backend)
    }

    func testMetaYAportacionGuardarOtraVezNoDuplicaYUnaVersionAntiguaAvisaYRecarga() async throws {
        let hogar = try await hogar()
        let backend = hogar.backend
        let planning = planning(hogar)
        await planning.load()
        // El formulario crea la meta (y su id) una vez; cada «Guardar» manda la misma.
        let meta = Goal(householdId: planning.household.id, name: "Vacaciones", target: Money(minor: 200_000))
        await backend.failCalls("createGoal(_:)")
        let primera = await planning.save(meta)
        XCTAssertFalse(primera)
        await backend.clearFailures()
        let segunda = await planning.save(meta)
        let tercera = await planning.save(meta)
        XCTAssertTrue(segunda)
        XCTAssertTrue(tercera, "repetirlo ya guardado no es un error")
        XCTAssertEqual(planning.goals.map(\.id), [meta.id], "queda una sola meta")

        // Otro dispositivo la cambia mientras este tiene abierta la versión anterior.
        let leida = try XCTUnwrap(planning.goals.first)
        var desdeOtro = leida
        desdeOtro.name = "Viaje"
        _ = try await backend.updateGoal(desdeOtro)
        var aqui = leida
        aqui.target = Money(minor: 1)
        let guardado = await planning.save(aqui)
        XCTAssertFalse(guardado)
        XCTAssertEqual(planning.error, AppError.movementChanged.errorDescription)
        XCTAssertEqual(planning.goals.map(\.name), ["Viaje"], "se ve lo que guardó el otro dispositivo")
        XCTAssertEqual(planning.goals.map(\.target), [Money(minor: 200_000)], "y no se pisa")

        // La aportación lleva el id del formulario: repetirla no aporta dos veces.
        let recargada = try XCTUnwrap(planning.goals.first)
        let hoy = try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 5))
        let id = UUID()
        await backend.failCalls("addContribution(_:)")
        let sinRed = await planning.contribute(Money(minor: 10_000), to: recargada, on: hoy, note: nil, id: id)
        XCTAssertFalse(sinRed)
        await backend.clearFailures()
        let aportada = await planning.contribute(Money(minor: 10_000), to: recargada, on: hoy, note: nil, id: id)
        let repetida = await planning.contribute(Money(minor: 10_000), to: recargada, on: hoy, note: nil, id: id)
        XCTAssertTrue(aportada)
        XCTAssertTrue(repetida)
        XCTAssertEqual(planning.contributions.map(\.amount), [Money(minor: 10_000)], "el dinero se aporta una sola vez")
        let otroImporte = await planning.contribute(Money(minor: 20_000), to: recargada, on: hoy, note: nil, id: id)
        XCTAssertFalse(otroImporte)
        XCTAssertEqual(planning.error, TransferDraft.storedWithOtherData)
    }

    func testPagoFijoGuardarOtraVezNoDuplicaYUnaVersionAntiguaAvisaYRecarga() async throws {
        let hogar = try await hogar()
        let backend = hogar.backend
        let planning = planning(hogar)
        await planning.load()
        let hoy = try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 5))
        // El formulario crea el pago fijo (y su id) una vez; cada «Guardar» manda el mismo.
        let alquiler = RecurringSeries(householdId: planning.household.id, name: "Alquiler", kind: .essential,
                                       amount: Money(minor: 80_000), startsOn: hoy)
        await backend.failCalls("createRecurring(_:)")
        let primera = await planning.save(alquiler)
        XCTAssertFalse(primera)
        await backend.clearFailures()
        let segunda = await planning.save(alquiler)
        let tercera = await planning.save(alquiler)
        XCTAssertTrue(segunda)
        XCTAssertTrue(tercera, "repetirlo ya guardado no es un error")
        XCTAssertEqual(planning.series.map(\.id), [alquiler.id], "queda un solo pago fijo")

        // Otro dispositivo lo cambia mientras este tiene abierta la versión anterior.
        let leido = try XCTUnwrap(planning.series.first)
        var desdeOtro = leido
        desdeOtro.name = "Alquiler del piso"
        _ = try await backend.updateRecurring(desdeOtro)
        var aqui = leido
        aqui.amount = Money(minor: 1)
        let guardado = await planning.save(aqui)
        XCTAssertFalse(guardado)
        XCTAssertEqual(planning.error, AppError.movementChanged.errorDescription)
        XCTAssertEqual(planning.series.map(\.name), ["Alquiler del piso"], "se ve lo que guardó el otro dispositivo")
        XCTAssertEqual(planning.series.map(\.amount), [Money(minor: 80_000)], "y no se pisa")
        var recargado = try XCTUnwrap(planning.series.first)
        recargado.amount = Money(minor: 85_000)
        let repetido = await planning.save(recargado)
        XCTAssertTrue(repetido, "con el pago fijo recargado, el cambio entra")
    }

    func testTarjetaYAplazadoGuardarOtraVezNoDuplicaYUnaVersionAntiguaAvisaYRecarga() async throws {
        let hogar = try await hogar()
        let (backend, finance) = (hogar.backend, hogar.finance)
        _ = await finance.createAccount(AccountDraft(name: "Tarjeta", kind: .creditCard))
        let tarjeta = try XCTUnwrap(finance.accounts.first { $0.kind == .creditCard })
        let hoy = try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 5))
        let compra = try await backend.addMovement(
            MovementDraft(accountId: tarjeta.id, bookedOn: hoy, amount: Money(minor: -60_000), description: "Portátil"),
            in: finance.household.id)
        let cards = CreditCardModel(household: finance.household, service: backend, finance: backend, today: { hoy })
        await cards.load(accounts: finance.accounts, balances: finance.balances, categories: finance.categories)

        // Sin versión son condiciones nuevas: guardarlas otra vez no las duplica ni las cambia.
        let condiciones = CreditCardTerms(accountId: tarjeta.id, householdId: finance.household.id, creditLimit: Money(minor: 300_000))
        await backend.failCalls("saveCreditCard(_:)")
        let primera = await cards.save(condiciones)
        XCTAssertFalse(primera)
        await backend.clearFailures()
        let segunda = await cards.save(condiciones)
        let tercera = await cards.save(condiciones)
        XCTAssertTrue(segunda)
        XCTAssertTrue(tercera, "repetirlo ya guardado no es un error")

        // Otro dispositivo las cambia mientras este tiene abierta la versión anterior.
        let leidas = try XCTUnwrap(cards.terms[tarjeta.id])
        var desdeOtro = leidas
        desdeOtro.statementDay = 10
        _ = try await backend.saveCreditCard(desdeOtro)
        var aqui = leidas
        aqui.creditLimit = Money(minor: 1)
        let guardado = await cards.save(aqui)
        XCTAssertFalse(guardado)
        XCTAssertEqual(cards.error, AppError.movementChanged.errorDescription)
        XCTAssertEqual(cards.terms[tarjeta.id]?.statementDay, 10, "se ve lo que guardó el otro dispositivo")
        XCTAssertEqual(cards.terms[tarjeta.id]?.creditLimit, Money(minor: 300_000), "y no se pisa")

        // El aplazado nuevo lleva el id de su movimiento: repetirlo no crea otro.
        await backend.failCalls("saveInstallment(_:)")
        let sinRed = await cards.deferPurchase(compra, months: 6, in: tarjeta)
        XCTAssertFalse(sinRed)
        await backend.clearFailures()
        let aplazada = await cards.deferPurchase(compra, months: 6, in: tarjeta)
        XCTAssertTrue(aplazada)
        let planes = try await backend.cardInstallments(in: finance.household.id)
        XCTAssertEqual(planes.map(\.id), [compra.id], "queda un solo aplazado")
        XCTAssertEqual(planes.map(\.months), [6])
    }

    func testActivoYPlanGuardarOtraVezNoDuplicaYUnaVersionAntiguaAvisaYRecarga() async throws {
        let hogar = try await hogar()
        let backend = hogar.backend
        let hoy = try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 5))
        let investments = InvestmentModel(household: hogar.finance.household, service: backend, households: backend, today: { hoy })
        await investments.load()
        // El formulario crea el activo (y su id) una vez; cada «Guardar» manda el mismo.
        let fondo = Holding(householdId: investments.household.id, name: "Fondo indexado", price: 10)
        await backend.failCalls("createHolding(_:)")
        let primera = await investments.save(fondo)
        XCTAssertNil(primera)
        await backend.clearFailures()
        let segunda = await investments.save(fondo)
        let tercera = await investments.save(fondo)
        XCTAssertNotNil(segunda)
        XCTAssertNotNil(tercera, "repetirlo ya guardado no es un error")
        XCTAssertEqual(investments.holdings.map(\.id), [fondo.id], "queda un solo activo")

        // Otro dispositivo lo cambia mientras este tiene abierta la versión anterior.
        let leido = try XCTUnwrap(investments.holdings.first)
        var desdeOtro = leido
        desdeOtro.name = "Fondo mundial"
        _ = try await backend.updateHolding(desdeOtro)
        var aqui = leido
        aqui.feeRate = 1
        let guardado = await investments.save(aqui)
        XCTAssertNil(guardado)
        XCTAssertEqual(investments.error, AppError.movementChanged.errorDescription)
        XCTAssertEqual(investments.holdings.map(\.name), ["Fondo mundial"], "se ve lo que guardó el otro dispositivo")
        XCTAssertEqual(investments.holdings.map(\.feeRate), [0], "y no se pisa")

        // El plan lleva el id del formulario.
        let plan = InvestmentPlan(householdId: investments.household.id, holdingId: fondo.id, amount: Money(minor: 10_000), startsOn: hoy)
        await backend.failCalls("createPlan(_:)")
        let sinRed = await investments.save(plan)
        XCTAssertFalse(sinRed)
        await backend.clearFailures()
        let creado = await investments.save(plan)
        let repetido = await investments.save(plan)
        XCTAssertTrue(creado)
        XCTAssertTrue(repetido)
        XCTAssertEqual(investments.plans.map(\.id), [plan.id], "queda un solo plan")
        let planLeido = try XCTUnwrap(investments.plans.first)
        var planDesdeOtro = planLeido
        planDesdeOtro.amount = Money(minor: 15_000)
        _ = try await backend.updatePlan(planDesdeOtro)
        let pausado = await investments.setPaused(true, planLeido)
        XCTAssertFalse(pausado)
        XCTAssertEqual(investments.error, AppError.movementChanged.errorDescription)
        XCTAssertEqual(investments.plans.map(\.amount), [Money(minor: 15_000)], "se ve el importe que guardó el otro dispositivo")
        XCTAssertEqual(investments.plans.map(\.isPaused), [false])
    }

    func testCategoriaGuardarOtraVezNoDuplicaYUnaVersionAntiguaAvisaYRecarga() async throws {
        let hogar = try await hogar()
        let (backend, finance) = (hogar.backend, hogar.finance)
        await finance.load()
        let dePartida = finance.categories.count
        // El formulario crea la categoría (y su id) una vez; cada «Guardar» manda la misma.
        let mascotas = BudgetCategory(householdId: finance.household.id, name: "Mascotas", kind: .expense, budgetGroup: .wants)
        await backend.failCalls("createCategory(_:)")
        let primera = await finance.save(mascotas)
        XCTAssertFalse(primera)
        await backend.clearFailures()
        let segunda = await finance.save(mascotas)
        let tercera = await finance.save(mascotas)
        XCTAssertTrue(segunda)
        XCTAssertTrue(tercera, "repetirlo ya guardado no es un error")
        XCTAssertEqual(finance.categories.count, dePartida + 1, "queda una sola categoría nueva")

        // Otro dispositivo la cambia mientras este tiene abierta la versión anterior.
        let leida = try XCTUnwrap(finance.category(mascotas.id))
        var desdeOtro = leida
        desdeOtro.name = "Perro"
        _ = try await backend.updateCategory(desdeOtro)
        var aqui = leida
        aqui.budgetGroup = .needs
        let guardado = await finance.save(aqui)
        XCTAssertFalse(guardado)
        XCTAssertEqual(finance.error, AppError.movementChanged.errorDescription)
        let recargada = try XCTUnwrap(finance.category(mascotas.id))
        XCTAssertEqual(recargada.name, "Perro", "se ve lo que guardó el otro dispositivo")
        XCTAssertEqual(recargada.budgetGroup, .wants, "y no se pisa")
        var repetida = recargada
        repetida.budgetGroup = .needs
        let repetido = await finance.save(repetida)
        XCTAssertTrue(repetido, "con la categoría recargada, el cambio entra")
    }

    func testPresupuestoExtraGuardarOtraVezNoDuplicaYUnaVersionAntiguaAvisaYRecarga() async throws {
        let hogar = try await hogar()
        let backend = hogar.backend
        let hoy = try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 5))
        let budgets = BudgetModel(household: hogar.finance.household, service: backend, today: { hoy })
        await budgets.load()
        // El formulario crea el presupuesto extra (y su id) una vez; cada «Guardar» manda el mismo, sin versión.
        let viaje = ExtraBudget(householdId: budgets.household.id, name: "Vacaciones", limit: Money(minor: 80_000), startsOn: hoy)
        await backend.failCalls("saveExtraBudget(_:)")
        let primera = await budgets.save(viaje)
        XCTAssertFalse(primera)
        await backend.clearFailures()
        let segunda = await budgets.save(viaje)
        let tercera = await budgets.save(viaje)
        XCTAssertTrue(segunda)
        XCTAssertTrue(tercera, "repetirlo ya guardado no es un error")
        XCTAssertEqual(budgets.extraBudgets.map(\.id), [viaje.id], "queda uno solo")

        // Otro dispositivo lo cambia mientras este tiene abierta la versión anterior.
        let leido = try XCTUnwrap(budgets.extraBudgets.first)
        var desdeOtro = leido
        desdeOtro.name = "Viaje"
        _ = try await backend.saveExtraBudget(desdeOtro)
        var aqui = leido
        aqui.limit = Money(minor: 1)
        let guardado = await budgets.save(aqui)
        XCTAssertFalse(guardado)
        XCTAssertEqual(budgets.error, AppError.movementChanged.errorDescription)
        XCTAssertEqual(budgets.extraBudgets.map(\.name), ["Viaje"], "se ve lo que guardó el otro dispositivo")
        XCTAssertEqual(budgets.extraBudgets.map(\.limit), [Money(minor: 80_000)], "y no se pisa")
        var recargado = try XCTUnwrap(budgets.extraBudgets.first)
        recargado.limit = Money(minor: 90_000)
        let repetido = await budgets.save(recargado)
        XCTAssertTrue(repetido, "con el presupuesto recargado, el cambio entra")
    }

    func testSaltarUnCargoQueCambioEnOtroDispositivoAvisaYRecarga() async throws {
        let hogar = try await hogar()
        let backend = hogar.backend
        let hoy = try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 5))
        _ = try await backend.createRecurring(RecurringSeries(householdId: hogar.finance.household.id, name: "Gimnasio",
                                                              amount: Money(minor: 3_200), accountId: hogar.account.id, startsOn: hoy))
        let planning = PlanningModel(household: hogar.finance.household, recurring: backend, goals: backend, today: { hoy })
        await planning.load()
        let pendiente = try XCTUnwrap(planning.pending.first, "el cargo de hoy está pendiente")

        // Otro dispositivo lo confirma mientras este lo tiene delante como pendiente.
        _ = try await backend.confirmCharge(pendiente.charge.id, with: MovementDraft(
            accountId: hogar.account.id, bookedOn: hoy, amount: Money(minor: -3_200), description: "Gimnasio"))
        let saltado = await planning.skip(pendiente)
        XCTAssertFalse(saltado)
        XCTAssertEqual(planning.error, AppError.movementChanged.errorDescription)
        XCTAssertEqual(planning.charges.map(\.status), [.confirmed], "se ve lo que guardó el otro dispositivo, no se pisa")
        XCTAssertTrue(planning.pending.isEmpty)
    }
}
