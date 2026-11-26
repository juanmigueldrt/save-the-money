import XCTest
import STMCore
@testable import SaveTheMoney

/// ORC-147: borrar una cuenta o una categoría no deja versiones viejas en los otros modelos, y repetir una importación
/// CSV no duplica los pagos fijos que crea.
@MainActor
final class ReferenciasYReintentosTests: XCTestCase {
    private struct Hogar {
        let backend: InMemoryBackend
        let home: Household
        let finance: FinanceModel
        let planning: PlanningModel
        let investments: InvestmentModel
        let cards: CreditCardModel
        let reload: HouseholdReload
    }

    private func hogar() async throws -> Hogar {
        let services = AppServices.demo()
        let session = SessionModel(services: services)
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        try await session.createHousehold(name: "Casa de prueba")
        guard case .ready(_, let home) = session.state else { throw AppError.unknown("sin hogar") }
        let finance = FinanceModel(household: home, service: services.finance)
        let budgets = BudgetModel(household: home, service: services.budgets)
        let planning = PlanningModel(household: home, recurring: services.recurring, goals: services.goals)
        let investments = InvestmentModel(household: home, service: services.investments, households: services.households)
        let cards = CreditCardModel(household: home, service: services.creditCards, finance: services.finance)
        let tracking = TrackingModel(household: home, finance: services.finance, budgets: services.budgets, scores: services.creditScores)
        let reload = HouseholdReload(finance: finance, budgets: budgets, planning: planning, investments: investments,
                                     cards: cards, tracking: tracking)
        return Hogar(backend: try XCTUnwrap(services.finance as? InMemoryBackend), home: home, finance: finance,
                     planning: planning, investments: investments, cards: cards, reload: reload)
    }

    private func dia() throws -> CalendarDay { try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 5)) }

    func testTrasBorrarUnaCuentaLaSiguienteEdicionNoAvisaDeUnCambio() async throws {
        let hogar = try await hogar()
        let (finance, planning, investments, cards) = (hogar.finance, hogar.planning, hogar.investments, hogar.cards)
        let corriente = AccountDraft(name: "Corriente", openingBalance: Money(minor: 100_000))
        let tarjeta = AccountDraft(name: "Tarjeta", kind: .creditCard)
        _ = await finance.createAccount(corriente)
        _ = await finance.createAccount(tarjeta)
        let cuenta = try XCTUnwrap(finance.account(corriente.id))

        // Todo lo que apunta a la cuenta con `on delete set null` en el servidor.
        let saved = await planning.save(Goal(householdId: hogar.home.id, name: "Viaje", target: Money(minor: 50_000), accountId: cuenta.id))
        XCTAssertTrue(saved)
        let seriesSaved = await planning.save(RecurringSeries(householdId: hogar.home.id, name: "Luz", amount: Money(minor: 4_000),
                                                              accountId: cuenta.id, startsOn: try dia()))
        XCTAssertTrue(seriesSaved)
        let holding = await investments.save(Holding(householdId: hogar.home.id, name: "Fondo", accountId: cuenta.id))
        XCTAssertNotNil(holding)
        await cards.load(accounts: finance.accounts, balances: finance.balances, categories: finance.categories)
        let cardSaved = await cards.save(CreditCardTerms(accountId: tarjeta.id, householdId: hogar.home.id,
                                                         creditLimit: Money(minor: 300_000), payFromAccountId: cuenta.id))
        XCTAssertTrue(cardSaved)

        let deleted = await hogar.reload.deleteAccount(cuenta)
        XCTAssertTrue(deleted)

        var goal = try XCTUnwrap(planning.goals.first)
        XCTAssertNil(goal.accountId, "se ve sin la cuenta borrada")
        goal.name = "Viaje a Lisboa"
        let goalEdited = await planning.save(goal)
        XCTAssertTrue(goalEdited, planning.error ?? "")
        var series = try XCTUnwrap(planning.series.first)
        XCTAssertNil(series.accountId)
        series.name = "Luz y gas"
        let seriesEdited = await planning.save(series)
        XCTAssertTrue(seriesEdited, planning.error ?? "")
        var fondo = try XCTUnwrap(investments.holdings.first)
        XCTAssertNil(fondo.accountId)
        fondo.name = "Fondo indexado"
        let holdingEdited = await investments.save(fondo)
        XCTAssertNotNil(holdingEdited, investments.error ?? "")
        var terms = try XCTUnwrap(cards.terms[tarjeta.id])
        XCTAssertNil(terms.payFromAccountId)
        terms.creditLimit = Money(minor: 400_000)
        let cardEdited = await cards.save(terms)
        XCTAssertTrue(cardEdited, cards.error ?? "")
    }

    func testTrasBorrarUnaCategoriaLaSiguienteEdicionNoAvisaDeUnCambio() async throws {
        let hogar = try await hogar()
        let (finance, planning) = (hogar.finance, hogar.planning)
        await finance.load()
        let categoria = try XCTUnwrap(finance.categories(for: .expense).first)
        let saved = await planning.save(RecurringSeries(householdId: hogar.home.id, name: "Gimnasio", amount: Money(minor: 3_500),
                                                        categoryId: categoria.id, startsOn: try dia()))
        XCTAssertTrue(saved)

        let deleted = await hogar.reload.delete(categoria)
        XCTAssertTrue(deleted)

        var series = try XCTUnwrap(planning.series.first)
        XCTAssertNil(series.categoryId, "se ve sin la categoría borrada")
        series.amount = Money(minor: 3_900)
        let edited = await planning.save(series)
        XCTAssertTrue(edited, planning.error ?? "")
    }

    /// El alta de un pago fijo llegó al servidor pero se perdió la respuesta, y la persona repite la importación. Cada
    /// intento hace un plan nuevo (con ids nuevos): el id fijado al empezar es el que se manda otra vez.
    func testRepetirLaImportacionNoDuplicaLosPagosFijos() async throws {
        let hogar = try await hogar()
        let planning = hogar.planning
        func plan() throws -> [RecurringSeries] {
            [RecurringSeries(householdId: hogar.home.id, name: "Netflix", amount: Money(minor: 1_299), startsOn: try dia())]
        }
        var ids: [String: UUID] = [:]

        let primero = CSVImportView.pinned(try plan(), ids: &ids)
        _ = try await hogar.backend.createRecurring(try XCTUnwrap(primero.first))

        let segundo = CSVImportView.pinned(try plan(), ids: &ids)
        XCTAssertEqual(segundo.map(\.id), primero.map(\.id))
        for series in segundo {
            let saved = await planning.save(series)
            XCTAssertTrue(saved, planning.error ?? "")
        }
        let stored = try await hogar.backend.recurringSeries(in: hogar.home.id)
        XCTAssertEqual(stored.map(\.name), ["Netflix"], "queda un solo pago fijo")
    }
}
