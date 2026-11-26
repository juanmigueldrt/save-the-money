import XCTest
@testable import STMCore

/// El resto de tablas (ORC-142): repetir un alta con el mismo identificador no duplica, y un cambio sobre una versión
/// antigua se rechaza. Los servicios en memoria imitan las funciones `create_…` y `update_…` del servidor. Datos inventados.
final class IdempotentTablesTests: XCTestCase {
    private let day = CalendarDay(year: 2026, month: 11, day: 5)!
    private let otherData = AppError.invalidInput(TransferDraft.storedWithOtherData)

    /// Ana con su hogar, y Bruno ya dentro de él. Queda la sesión de Ana.
    private func home() async throws -> (backend: InMemoryBackend, id: UUID) {
        let backend = InMemoryBackend()
        let password = "contrasena-de-prueba"
        _ = try await backend.signUp(username: Username("ana"), password: password, displayName: nil)
        let home = try await backend.createHousehold(name: "Casa de prueba")
        let invite = try await backend.createInvite(for: home.id)
        try await backend.signOut()
        _ = try await backend.signUp(username: Username("bruno"), password: password, displayName: nil)
        _ = try await backend.acceptInvite(XCTUnwrap(invite.inviteCode))
        try await enter(backend, "ana")
        return (backend, home.id)
    }

    private func enter(_ backend: InMemoryBackend, _ name: String) async throws {
        try await backend.signOut()
        _ = try await backend.signIn(username: Username(name), password: "contrasena-de-prueba")
    }

    private func assertThrows(_ expected: AppError, _ message: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("debería fallar: " + message)
        } catch {
            XCTAssertEqual(error as? AppError, expected, message)
        }
    }

    /// Lo común de un alta: falla la red, se reintenta con el mismo formulario (el mismo id) dos veces y queda una
    /// sola fila; Bruno no puede usar ese id (el servidor da 23505, o 42501 si la fila cuelga de algo de Ana).
    /// `create` guarda la fila tal cual la manda el formulario y `count` dice cuántas ve quien tiene la sesión.
    private func assertCreatedOnce<Row: Equatable>(
        _ backend: InMemoryBackend, failing operation: String, create: () async throws -> Row, count: () async throws -> Int
    ) async throws -> Row {
        await backend.failCalls(operation)
        await assertThrows(.network, "sin red no se guarda") { _ = try await create() }
        await backend.clearFailures()
        let first = try await create()
        let second = try await create()
        XCTAssertEqual(second, first, "repetirlo devuelve lo guardado")
        let stored = try await count()
        XCTAssertEqual(stored, 1, "queda una sola fila")
        try await enter(backend, "bruno")
        do {
            _ = try await create()
            XCTFail("Bruno no guarda nada con un id de Ana")
        } catch {
            XCTAssertNotNil(error as? AppError)
        }
        let seen = try await count()
        XCTAssertEqual(seen, 0, "ni ve la fila de Ana")
        try await enter(backend, "ana")
        let kept = try await count()
        XCTAssertEqual(kept, 1, "y Ana sigue con la suya, sin cambios")
        return first
    }

    /// Lo común de un cambio: `phone` y `tablet` salen de la misma lectura (`read`). El primero entra y cambia la
    /// versión; el segundo, sobre la versión antigua, se rechaza, igual que uno sin versión y que uno de Bruno.
    /// `savesNew`: la misma llamada da de alta lo que llega sin versión (tarjetas, aplazados), así que eso no se prueba.
    private func assertStaleRejected<Row: Versioned>(
        _ backend: InMemoryBackend, read: Row, phone: Row, tablet: Row, savesNew: Bool = false,
        update: (Row) async throws -> Row
    ) async throws -> Row {
        XCTAssertNotNil(read.updatedAt, "cada fila guardada tiene versión")
        let saved = try await update(phone)
        XCTAssertNotEqual(saved.updatedAt, read.updatedAt, "cambiarla cambia la versión")
        await assertThrows(.movementChanged, "la versión antigua no pisa el cambio") { _ = try await update(tablet) }
        var unread = saved
        unread.updatedAt = nil
        if !savesNew {
            await assertThrows(.movementChanged, "sin versión tampoco") { _ = try await update(unread) }
        }
        try await enter(backend, "bruno")
        await assertThrows(.movementChanged, "Bruno no cambia lo de Ana") { _ = try await update(saved) }
        try await enter(backend, "ana")
        return saved
    }

    func testCuentas() async throws {
        let (backend, home) = try await home()
        let draft = AccountDraft(name: "Corriente", openingBalance: Money(minor: 100_000))
        let read = try await assertCreatedOnce(backend, failing: "createAccount(_:in:)",
                                               create: { try await backend.createAccount(draft, in: home) },
                                               count: { try await backend.accounts(in: home).count })
        XCTAssertEqual(read.id, draft.id, "la cuenta lleva el identificador que eligió la app")
        var other = draft
        other.openingBalance = Money(minor: 5)
        await assertThrows(otherData, "otro saldo inicial") { _ = try await backend.createAccount(other, in: home) }

        var phone = read, tablet = read
        phone.name = "Nómina"
        tablet.openingBalance = Money(minor: 1)
        _ = try await assertStaleRejected(backend, read: read, phone: phone, tablet: tablet) { try await backend.updateAccount($0) }
        let stored = try await backend.accounts(in: home)
        XCTAssertEqual(stored.map(\.name), ["Nómina"])
        XCTAssertEqual(stored.map(\.openingBalance), [Money(minor: 100_000)], "el saldo inicial no se ha pisado")

        // Elegir otra predeterminada cambia también la versión de la que deja de serlo, como en el servidor.
        var first = try XCTUnwrap(stored.first)
        first.isDefault = true
        let wasDefault = try await backend.updateAccount(first)
        var savings = try await backend.createAccount(AccountDraft(name: "Ahorro"), in: home)
        savings.isDefault = true
        _ = try await backend.updateAccount(savings)
        await assertThrows(.movementChanged, "la antigua predeterminada ya es otra versión") {
            _ = try await backend.updateAccount(wasDefault)
        }
    }

    func testLaVersionDeUnaCuentaSeGuardaComoTexto() throws {
        let json = """
        {"id":"20000000-0000-0000-0000-000000000001","household_id":"20000000-0000-0000-0000-0000000000aa",
         "name":"Corriente","kind":"checking","currency":"EUR","opening_balance_minor":0,
         "updated_at":"2026-11-01T10:00:00.123456+00:00"}
        """
        let account = try JSONDecoder().decode(Account.self, from: Data(json.utf8))
        XCTAssertEqual(account.updatedAt, "2026-11-01T10:00:00.123456+00:00")
    }

    func testMetasYAportaciones() async throws {
        let (backend, home) = try await home()
        let goal = Goal(householdId: home, name: "Vacaciones", target: Money(minor: 200_000))
        let read = try await assertCreatedOnce(backend, failing: "createGoal(_:)",
                                               create: { try await backend.createGoal(goal) },
                                               count: { try await backend.goals(in: home).count })
        XCTAssertEqual(read.id, goal.id, "la meta lleva el identificador que eligió la app")
        var other = goal
        other.target = Money(minor: 5)
        await assertThrows(otherData, "otro objetivo") { _ = try await backend.createGoal(other) }

        var phone = read, tablet = read
        phone.name = "Viaje"
        tablet.target = Money(minor: 1)
        _ = try await assertStaleRejected(backend, read: read, phone: phone, tablet: tablet) { try await backend.updateGoal($0) }
        let stored = try await backend.goals(in: home)
        XCTAssertEqual(stored.map(\.name), ["Viaje"])
        XCTAssertEqual(stored.map(\.target), [Money(minor: 200_000)], "el objetivo no se ha pisado")

        let contribution = GoalContribution(householdId: home, goalId: goal.id, amount: Money(minor: 10_000), madeOn: day)
        _ = try await assertCreatedOnce(backend, failing: "addContribution(_:)",
                                        create: { try await backend.addContribution(contribution) },
                                        count: { try await backend.contributions(in: home).count })
        var more = contribution
        more.amount = Money(minor: 20_000)
        await assertThrows(otherData, "otro importe") { _ = try await backend.addContribution(more) }
        let saved = try await backend.contributions(in: home)
        XCTAssertEqual(saved.map(\.amount), [Money(minor: 10_000)], "el dinero se aporta una sola vez")
    }
}

extension IdempotentTablesTests {
    func testPagosFijos() async throws {
        let (backend, home) = try await home()
        let series = RecurringSeries(householdId: home, name: "Alquiler", kind: .essential, amount: Money(minor: 80_000), startsOn: day)
        let read = try await assertCreatedOnce(backend, failing: "createRecurring(_:)",
                                               create: { try await backend.createRecurring(series) },
                                               count: { try await backend.recurringSeries(in: home).count })
        XCTAssertEqual(read.id, series.id, "el pago fijo lleva el identificador que eligió la app")
        var other = series
        other.amount = Money(minor: 90_000)
        await assertThrows(otherData, "otro importe") { _ = try await backend.createRecurring(other) }

        var phone = read, tablet = read
        phone.name = "Alquiler del piso"
        tablet.amount = Money(minor: 1)
        _ = try await assertStaleRejected(backend, read: read, phone: phone, tablet: tablet) { try await backend.updateRecurring($0) }
        let stored = try await backend.recurringSeries(in: home)
        XCTAssertEqual(stored.map(\.name), ["Alquiler del piso"])
        XCTAssertEqual(stored.map(\.amount), [Money(minor: 80_000)], "el importe no se ha pisado")
    }

    /// El pago fijo que nace de un gasto lleva el id del movimiento: guardar otra vez el formulario no crea otro.
    func testElPagoFijoDeUnGastoNoSeDuplicaAlRepetirElFormulario() async throws {
        let (backend, home) = try await home()
        let card = try await backend.createAccount(AccountDraft(name: "Tarjeta", kind: .creditCard), in: home)
        let draft = MovementDraft(accountId: card.id, bookedOn: day, amount: Money(minor: -999), description: "Música")
        for _ in 0..<2 {
            let movement = try await backend.addMovement(draft, in: home)
            _ = try await backend.createRecurring(RecurringSeries.fromPurchase(movement))
        }
        let stored = try await backend.recurringSeries(in: home)
        XCTAssertEqual(stored.map(\.id), [draft.id])
    }
}

extension IdempotentTablesTests {
    func testTarjetasYAplazados() async throws {
        let (backend, home) = try await home()
        let card = try await backend.createAccount(AccountDraft(name: "Tarjeta", kind: .creditCard), in: home)
        // Sin versión son condiciones nuevas: guardarlas otra vez no las duplica ni las cambia.
        let terms = CreditCardTerms(accountId: card.id, householdId: home, creditLimit: Money(minor: 300_000))
        let read = try await assertCreatedOnce(backend, failing: "saveCreditCard(_:)",
                                               create: { try await backend.saveCreditCard(terms) },
                                               count: { try await backend.creditCards(in: home).count })
        var other = terms
        other.creditLimit = Money(minor: 5)
        await assertThrows(otherData, "otro límite") { _ = try await backend.saveCreditCard(other) }

        var phone = read, tablet = read
        phone.statementDay = 10
        tablet.creditLimit = Money(minor: 1)
        _ = try await assertStaleRejected(backend, read: read, phone: phone, tablet: tablet, savesNew: true) {
            try await backend.saveCreditCard($0)
        }
        let stored = try await backend.creditCards(in: home)
        XCTAssertEqual(stored.map(\.statementDay), [10])
        XCTAssertEqual(stored.map(\.creditLimit), [Money(minor: 300_000)], "el límite no se ha pisado")

        // El aplazado nuevo lleva el id de su movimiento.
        let purchase = try await backend.addMovement(
            MovementDraft(accountId: card.id, bookedOn: day, amount: Money(minor: -60_000), description: "Portátil"), in: home)
        let plan = CardInstallment(id: purchase.id, householdId: home, accountId: card.id, movementId: purchase.id, months: 6)
        let planned = try await assertCreatedOnce(backend, failing: "saveInstallment(_:)",
                                                  create: { try await backend.saveInstallment(plan) },
                                                  count: { try await backend.cardInstallments(in: home).count })
        var longer = plan
        longer.months = 12
        await assertThrows(otherData, "otro plazo") { _ = try await backend.saveInstallment(longer) }
        let second = CardInstallment(householdId: home, accountId: card.id, movementId: purchase.id, months: 6)
        await assertThrows(.idUsedBySomeoneElse, "un aplazado por compra") { _ = try await backend.saveInstallment(second) }

        var here = planned, there = planned
        here.months = 9
        there.months = 3
        _ = try await assertStaleRejected(backend, read: planned, phone: here, tablet: there, savesNew: true) {
            try await backend.saveInstallment($0)
        }
        let plans = try await backend.cardInstallments(in: home)
        XCTAssertEqual(plans.map(\.months), [9], "queda el primer cambio")
    }
}

extension IdempotentTablesTests {
    func testActivosYPlanes() async throws {
        let (backend, home) = try await home()
        let fund = Holding(householdId: home, name: "Fondo indexado", price: 10)
        let read = try await assertCreatedOnce(backend, failing: "createHolding(_:)",
                                               create: { try await backend.createHolding(fund) },
                                               count: { try await backend.holdings(in: home).count })
        XCTAssertEqual(read.id, fund.id, "el activo lleva el identificador que eligió la app")
        var other = fund
        other.kind = .stock
        await assertThrows(otherData, "otro tipo") { _ = try await backend.createHolding(other) }

        var phone = read, tablet = read
        phone.name = "Fondo mundial"
        tablet.feeRate = 1
        let saved = try await assertStaleRejected(backend, read: read, phone: phone, tablet: tablet) { try await backend.updateHolding($0) }
        // Apuntar un precio cambia el activo en el servidor: también su versión.
        let priced = try await backend.recordPrice(12, on: day, for: fund.id)
        XCTAssertNotEqual(priced.updatedAt, saved.updatedAt)
        var stale = saved
        stale.note = "Con el precio antiguo"
        await assertThrows(.movementChanged, "el precio lo cambió") { _ = try await backend.updateHolding(stale) }
        let stored = try await backend.holdings(in: home)
        XCTAssertEqual(stored.map(\.name), ["Fondo mundial"])
        XCTAssertEqual(stored.map(\.price), [12], "el precio nuevo no se ha pisado")

        let plan = InvestmentPlan(householdId: home, holdingId: fund.id, amount: Money(minor: 10_000), startsOn: day)
        let planned = try await assertCreatedOnce(backend, failing: "createPlan(_:)",
                                                  create: { try await backend.createPlan(plan) },
                                                  count: { try await backend.investmentPlans(in: home).count })
        var bigger = plan
        bigger.amount = Money(minor: 20_000)
        await assertThrows(otherData, "otro importe") { _ = try await backend.createPlan(bigger) }
        var here = planned, there = planned
        here.amount = Money(minor: 15_000)
        there.pausedAt = Date(timeIntervalSince1970: 0)
        _ = try await assertStaleRejected(backend, read: planned, phone: here, tablet: there) { try await backend.updatePlan($0) }
        let plans = try await backend.investmentPlans(in: home)
        XCTAssertEqual(plans.map(\.amount), [Money(minor: 15_000)])
        XCTAssertEqual(plans.map(\.isPaused), [false], "la pausa sobre la versión antigua no ha entrado")
    }
}

extension IdempotentTablesTests {
    func testCategorias() async throws {
        let (backend, home) = try await home()
        let seeded = try await backend.categories(in: home).count
        let pets = BudgetCategory(householdId: home, name: "Mascotas", kind: .expense, budgetGroup: .wants)
        let read = try await assertCreatedOnce(backend, failing: "createCategory(_:)",
                                               create: { try await backend.createCategory(pets) },
                                               count: { try await backend.categories(in: home).filter { $0.id == pets.id }.count })
        XCTAssertEqual(read.id, pets.id, "la categoría lleva el identificador que eligió la app")
        let total = try await backend.categories(in: home).count
        XCTAssertEqual(total, seeded + 1, "una sola categoría nueva")
        var other = pets
        other.name = "Animales"
        await assertThrows(otherData, "otro nombre") { _ = try await backend.createCategory(other) }

        var phone = read, tablet = read
        phone.name = "Perro"
        tablet.budgetGroup = .needs
        _ = try await assertStaleRejected(backend, read: read, phone: phone, tablet: tablet) { try await backend.updateCategory($0) }
        let stored = try await backend.categories(in: home).first { $0.id == pets.id }
        XCTAssertEqual(stored?.name, "Perro")
        XCTAssertEqual(stored?.budgetGroup, .wants, "el grupo no se ha pisado")
        // Las de partida también tienen versión: se pueden cambiar.
        let all = try await backend.categories(in: home)
        var first = try XCTUnwrap(all.first { $0.id != pets.id })
        XCTAssertNotNil(first.updatedAt)
        first.icon = "star"
        _ = try await backend.updateCategory(first)
    }
}

extension IdempotentTablesTests {
    func testPresupuestosExtra() async throws {
        let (backend, home) = try await home()
        // Sin versión es uno nuevo: guardarlo otra vez no lo duplica ni lo cambia.
        let trip = ExtraBudget(householdId: home, name: "Vacaciones", limit: Money(minor: 80_000), startsOn: day, isFavorite: true)
        let read = try await assertCreatedOnce(backend, failing: "saveExtraBudget(_:)",
                                               create: { try await backend.saveExtraBudget(trip) },
                                               count: { try await backend.extraBudgets(in: home).count })
        XCTAssertEqual(read.id, trip.id, "lleva el identificador que eligió la app")
        var other = trip
        other.limit = Money(minor: 5)
        await assertThrows(otherData, "otro límite") { _ = try await backend.saveExtraBudget(other) }

        var phone = read, tablet = read
        phone.name = "Viaje"
        tablet.limit = Money(minor: 1)
        let saved = try await assertStaleRejected(backend, read: read, phone: phone, tablet: tablet, savesNew: true) {
            try await backend.saveExtraBudget($0)
        }
        // Otro favorito le quita la marca a este: también cambia su versión, como en el servidor.
        _ = try await backend.saveExtraBudget(ExtraBudget(householdId: home, name: "Obra", limit: Money(minor: 100), startsOn: day,
                                                          isFavorite: true))
        var stale = saved
        stale.limit = Money(minor: 2)
        await assertThrows(.movementChanged, "ya no es favorito: es otra versión") { _ = try await backend.saveExtraBudget(stale) }
        let stored = try await backend.extraBudgets(in: home).first { $0.id == trip.id }
        XCTAssertEqual(stored?.name, "Viaje")
        XCTAssertEqual(stored?.limit, Money(minor: 80_000), "el límite no se ha pisado")
        XCTAssertEqual(stored?.isFavorite, false)
        // Repetir el alta del primero no le quita la marca al favorito de ahora.
        var again = trip
        again.name = "Viaje"
        _ = try await backend.saveExtraBudget(again)
        let favorites = try await backend.extraBudgets(in: home).filter(\.isFavorite).map(\.name)
        XCTAssertEqual(favorites, ["Obra"])
    }
}

extension IdempotentTablesTests {
    func testCargosDePagosFijos() async throws {
        let (backend, home) = try await home()
        let series = try await backend.createRecurring(
            RecurringSeries(householdId: home, name: "Gimnasio", amount: Money(minor: 3_200), startsOn: day))
        let created = try await backend.createCharges([
            RecurringCharge(householdId: home, seriesId: series.id, dueOn: day, amount: Money(minor: -3_200)),
            RecurringCharge(householdId: home, seriesId: series.id, dueOn: day.adding(months: 1), amount: Money(minor: -3_200))
        ])
        let read = try XCTUnwrap(created.first)
        XCTAssertNotNil(read.updatedAt, "cada cargo guardado tiene versión")

        // Un dispositivo lo salta; el otro, que aún tiene la versión anterior, ya no lo cambia.
        let skipped = try await backend.updateCharge(read, status: .skipped, transactionId: nil)
        XCTAssertNotEqual(skipped.updatedAt, read.updatedAt, "cambiarlo cambia la versión")
        await assertThrows(.movementChanged, "la versión antigua no pisa el cambio") {
            _ = try await backend.updateCharge(read, status: .pending, transactionId: nil)
        }
        var unread = skipped
        unread.updatedAt = nil
        await assertThrows(.movementChanged, "sin versión tampoco") {
            _ = try await backend.updateCharge(unread, status: .pending, transactionId: nil)
        }
        try await enter(backend, "bruno")
        await assertThrows(.movementChanged, "Bruno no cambia lo de Ana") {
            _ = try await backend.updateCharge(skipped, status: .pending, transactionId: nil)
        }
        try await enter(backend, "ana")

        // Confirmarlo creando su movimiento también cambia la versión.
        let second = try XCTUnwrap(created.last)
        let account = try await backend.createAccount(AccountDraft(name: "Corriente"), in: home)
        _ = try await backend.confirmCharge(second.id, with: MovementDraft(accountId: account.id, bookedOn: second.dueOn,
                                                                            amount: Money(minor: -3_200), description: "Gimnasio"))
        await assertThrows(.movementChanged, "ya confirmado: es otra versión") {
            _ = try await backend.updateCharge(second, status: .skipped, transactionId: nil)
        }
        let stored = try await backend.recurringCharges(in: home)
        XCTAssertEqual(Set(stored.map(\.status)), [.skipped, .confirmed])
    }
}

extension ExtraBudget: Versioned {}
extension BudgetCategory: Versioned {}
extension Holding: Versioned {}
extension InvestmentPlan: Versioned {}
extension CreditCardTerms: Versioned {}
extension CardInstallment: Versioned {}
extension RecurringSeries: Versioned {}

/// Fila con versión, para comprobarlas todas igual.
private protocol Versioned {
    var updatedAt: String? { get set }
}

extension Account: Versioned {}
extension Goal: Versioned {}
