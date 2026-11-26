import XCTest
import STMCore
@testable import SaveTheMoney

/// Guarda los avisos que se programarían, por prefijo, en vez de lanzarlos.
private actor PrefixedReminders: ReminderScheduling {
    private(set) var byPrefix: [String: [PlannedReminder]] = [:]
    func replace(with reminders: [PlannedReminder], prefix: String) async { byPrefix[prefix] = reminders }
}

/// Un hogar listo en modo demo, con su backend en memoria a mano para hacerlo fallar.
@MainActor
private func demoHome() async throws -> (AppServices, InMemoryBackend, Household) {
    let services = AppServices.demo()
    let session = SessionModel(services: services)
    try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
    try await session.createHousehold(name: "Casa de prueba")
    guard case .ready(_, let home) = session.state else { throw AppError.unknown("sin hogar") }
    let backend = try XCTUnwrap(services.finance as? InMemoryBackend)
    return (services, backend, home)
}

private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }
private let networkMessage = AppError.network.errorDescription

@MainActor
final class InvestmentModelTests: XCTestCase {
    func testHoldingPriceTradesAndPlans() async throws {
        let (services, _, home) = try await demoHome()
        let today = day(2026, 11, 10)
        let reminders = PrefixedReminders()
        let investments = InvestmentModel(household: home, service: services.investments, households: services.households,
                                          reminders: reminders, today: { today })
        await investments.load()
        XCTAssertTrue(investments.holdings.isEmpty)
        XCTAssertEqual(investments.members.count, 1)
        XCTAssertFalse(investments.isLoading)

        let saved = await investments.save(Holding(householdId: home.id, name: "  Fondo de prueba  ", price: 10))
        let fund = try XCTUnwrap(saved)
        XCTAssertEqual(fund.name, "Fondo de prueba")
        XCTAssertEqual(investments.holdings.map(\.id), [fund.id])

        let priced = await investments.recordPrice(12, on: today, for: fund)
        XCTAssertTrue(priced)
        XCTAssertEqual(investments.holding(fund.id)?.price, 12)
        XCTAssertEqual(investments.prices.map(\.price), [12])

        let buy = InvestmentTrade(householdId: home.id, holdingId: fund.id, tradedOn: day(2026, 11, 2), side: .buy,
                                  quantity: 10, price: 10, fee: Money(minor: 100))
        let bought = await investments.add(buy)
        XCTAssertTrue(bought)
        let position = investments.position(of: try XCTUnwrap(investments.holding(fund.id)))
        XCTAssertEqual(position.quantity, 10)
        XCTAssertEqual(position.cost, Money(minor: 10_100))
        XCTAssertEqual(position.value, Money(minor: 12_000))
        XCTAssertEqual(investments.portfolio.gain, Money(minor: 1_900))

        let oversell = InvestmentTrade(householdId: home.id, holdingId: fund.id, tradedOn: today, side: .sell,
                                       quantity: 15, price: 12)
        let sold = await investments.add(oversell)
        XCTAssertFalse(sold)
        XCTAssertEqual(investments.error, "No tienes tantas participaciones para vender.")
        XCTAssertEqual(investments.trades.map(\.id), [buy.id])

        let plan = InvestmentPlan(householdId: home.id, holdingId: fund.id, amount: Money(minor: 5_000),
                                  startsOn: day(2026, 11, 15), remindDaysBefore: 1)
        let planned = await investments.save(plan)
        XCTAssertTrue(planned)
        XCTAssertEqual(investments.monthlyPlanned, Money(minor: 5_000))
        let scheduled = await reminders.byPrefix[ReminderPlanner.investmentPrefix] ?? []
        XCTAssertEqual(scheduled.map(\.fireOn), [day(2026, 11, 14), day(2026, 12, 14)])

        // Se pausa el que hay cargado (con su versión), como hace la pantalla.
        let paused = await investments.setPaused(true, try XCTUnwrap(investments.plans.first))
        XCTAssertTrue(paused)
        XCTAssertEqual(investments.monthlyPlanned, .zero)
        XCTAssertEqual(investments.planCounts.active, 0)
        XCTAssertEqual(investments.planCounts.paused, 1)
        let afterPause = await reminders.byPrefix[ReminderPlanner.investmentPrefix] ?? []
        XCTAssertTrue(afterPause.isEmpty, "un plan en pausa no avisa")

        // Borrar el activo se lleva sus precios, operaciones y planes, aquí y en lo guardado.
        let deleted = await investments.delete(fund)
        XCTAssertTrue(deleted)
        XCTAssertTrue(investments.holdings.isEmpty)
        XCTAssertTrue(investments.trades.isEmpty)
        XCTAssertTrue(investments.plans.isEmpty)
        let reloaded = InvestmentModel(household: home, service: services.investments, households: services.households)
        await reloaded.load()
        XCTAssertTrue(reloaded.holdings.isEmpty)
        XCTAssertTrue(reloaded.trades.isEmpty)
        XCTAssertTrue(reloaded.plans.isEmpty)
    }

    func testFailingServiceLeavesModelAndStoreUntouched() async throws {
        let (services, backend, home) = try await demoHome()
        let investments = InvestmentModel(household: home, service: services.investments, households: services.households)
        await investments.load()
        let saved = await investments.save(Holding(householdId: home.id, name: "Fondo de prueba", price: 10))
        let fund = try XCTUnwrap(saved)
        let buy = InvestmentTrade(householdId: home.id, holdingId: fund.id, tradedOn: day(2026, 11, 2), quantity: 10, price: 10)
        _ = await investments.add(buy)

        // Sin red: falla, avisa y no toca nada.
        await backend.failCalls()
        let second = InvestmentTrade(householdId: home.id, holdingId: fund.id, tradedOn: day(2026, 11, 3), quantity: 5, price: 10)
        let added = await investments.add(second)
        XCTAssertFalse(added)
        XCTAssertEqual(investments.error, networkMessage)
        XCTAssertEqual(investments.trades.map(\.id), [buy.id])

        // Al cargar sin red se queda lo que había y se apaga el indicador.
        await investments.load()
        XCTAssertEqual(investments.error, networkMessage)
        XCTAssertEqual(investments.holdings.map(\.id), [fund.id])
        XCTAssertFalse(investments.isLoading)

        // Cancelada: tampoco guarda nada.
        await backend.clearFailures()
        await backend.failCalls("addTrade(_:cash:)", with: CancellationError())
        let cancelled = await investments.add(second)
        XCTAssertFalse(cancelled)
        XCTAssertEqual(investments.trades.map(\.id), [buy.id])

        await backend.clearFailures()
        let stored = try await backend.trades(in: home.id)
        XCTAssertEqual(stored.map(\.id), [buy.id])
    }
}

/// Los flujos con dos escrituras: el pago de la tarjeta (`FinanceModel.transfer`) y la compra y la venta
/// con su movimiento en la cuenta (`InvestmentModel.buy` y `sell`). Las vistas solo llaman a esos métodos.
@MainActor
final class MultiStepFlowTests: XCTestCase {
    private struct Setup {
        let services: AppServices
        let backend: InMemoryBackend
        let home: Household
        let finance: FinanceModel
        let checking: Account
    }

    private func setup() async throws -> Setup {
        let (services, backend, home) = try await demoHome()
        let finance = FinanceModel(household: home, service: services.finance)
        await finance.load()
        _ = await finance.createAccount(AccountDraft(name: "Cuenta común", openingBalance: Money(minor: 100_000)))
        let checking = try XCTUnwrap(finance.accounts.first)
        return Setup(services: services, backend: backend, home: home, finance: finance, checking: checking)
    }

    private func storedBalances(_ s: Setup) async throws -> [UUID: Money] {
        try await s.backend.balances(in: s.home.id)
    }

    // MARK: Pago de la tarjeta

    /// Igual que `CardPaymentFormView.save`: una transferencia de la cuenta a la tarjeta, con el id del formulario.
    private func payCard(_ card: Account, from: Account, amount: Money, on date: CalendarDay, finance: FinanceModel,
                         id: UUID = UUID()) async -> Bool {
        await finance.transfer(id: id, from: from, to: card, amount: amount, on: date,
                               description: "Pago de \(card.name)", toDescription: "Pago de la tarjeta")
    }

    private func cardSetup() async throws -> (Setup, Account, CreditCardModel) {
        let s = try await setup()
        _ = await s.finance.createAccount(AccountDraft(name: "Tarjeta", kind: .creditCard))
        let card = try XCTUnwrap(s.finance.accounts.first { $0.kind == .creditCard })
        _ = await s.finance.add(MovementDraft(accountId: card.id, bookedOn: day(2026, 10, 10), amount: Money(minor: -30_000),
                                              description: "Compra de prueba"))
        let cards = CreditCardModel(household: s.home, service: s.services.creditCards, finance: s.services.finance,
                                    today: { day(2026, 11, 4) })
        await cards.load(accounts: s.finance.accounts, balances: s.finance.balances, categories: s.finance.categories)
        let saved = await cards.save(CreditCardTerms(accountId: card.id, householdId: s.home.id,
                                                     creditLimit: Money(minor: 300_000), payFromAccountId: s.checking.id))
        XCTAssertTrue(saved)
        XCTAssertEqual(cards.summary(for: card)?.next?.amount, Money(minor: 30_000))
        return (s, card, cards)
    }

    func testCardPayment() async throws {
        let (s, card, cards) = try await cardSetup()
        let paid = await payCard(card, from: s.checking, amount: Money(minor: 30_000), on: day(2026, 11, 4), finance: s.finance)
        XCTAssertTrue(paid)
        XCTAssertEqual(s.finance.balances[s.checking.id], Money(minor: 70_000))
        XCTAssertEqual(s.finance.balances[card.id], .zero)
        let stored = try await storedBalances(s)
        XCTAssertEqual(stored, s.finance.balances)

        await cards.load(accounts: s.finance.accounts, balances: s.finance.balances, categories: s.finance.categories)
        XCTAssertEqual(cards.summary(for: card)?.used, .zero)
        XCTAssertEqual(cards.summary(for: card)?.available, Money(minor: 300_000))
    }

    func testCardPaymentWhenTheSecondWriteFails() async throws {
        let (s, card, _) = try await cardSetup()
        let id = UUID()
        await s.backend.failCalls("addMovement(_:in:)", after: 1)
        let paid = await payCard(card, from: s.checking, amount: Money(minor: 30_000), on: day(2026, 11, 4), finance: s.finance, id: id)
        XCTAssertFalse(paid)
        XCTAssertEqual(s.finance.error, networkMessage)
        // El modelo enseña lo mismo que hay guardado.
        var stored = try await storedBalances(s)
        XCTAssertEqual(s.finance.balances, stored)
        XCTAssertEqual(stored[card.id], Money(minor: -30_000), "la entrada en la tarjeta no se guardó")
        XCTAssertEqual(stored[s.checking.id], Money(minor: 100_000), "un pago a medias no debe sacar dinero de la cuenta")
        XCTAssertFalse(s.finance.recent.contains { $0.description == "Pago de Tarjeta" }, "no debe quedar la mitad del pago")

        // Al reintentar desde el mismo formulario el pago entra entero, una sola vez.
        await s.backend.clearFailures()
        let retried = await payCard(card, from: s.checking, amount: Money(minor: 30_000), on: day(2026, 11, 4), finance: s.finance, id: id)
        XCTAssertTrue(retried)
        stored = try await storedBalances(s)
        XCTAssertEqual(s.finance.balances, stored)
        XCTAssertEqual(stored[s.checking.id], Money(minor: 70_000))
        XCTAssertEqual(stored[card.id], .zero)
    }

    func testCardPaymentRepeatedDoesNotDuplicate() async throws {
        let (s, card, _) = try await cardSetup()
        let id = UUID()
        for _ in 1...2 {
            let paid = await payCard(card, from: s.checking, amount: Money(minor: 30_000), on: day(2026, 11, 4), finance: s.finance, id: id)
            XCTAssertTrue(paid, "repetir la petición no es un error")
        }
        XCTAssertEqual(s.finance.recent.filter { $0.description == "Pago de Tarjeta" }.count, 1, "una sola salida de la cuenta")
        XCTAssertEqual(s.finance.recent.filter { $0.description == "Pago de la tarjeta" }.count, 1, "y una sola entrada en la tarjeta")
        let stored = try await storedBalances(s)
        XCTAssertEqual(s.finance.balances, stored)
        XCTAssertEqual(stored[s.checking.id], Money(minor: 70_000))
        XCTAssertEqual(stored[card.id], .zero)

        // Desde el mismo formulario pero con otro importe: no se da por guardado, y se ve el pago que ya estaba.
        let changed = await payCard(card, from: s.checking, amount: Money(minor: 99_900), on: day(2026, 11, 4), finance: s.finance, id: id)
        XCTAssertFalse(changed, "el formulario se queda abierto")
        XCTAssertEqual(s.finance.error, TransferDraft.storedWithOtherData)
        let after = try await storedBalances(s)
        XCTAssertEqual(after, stored, "no se apunta nada")
        XCTAssertEqual(s.finance.balances, after)
        XCTAssertEqual(s.finance.recent.filter { $0.description == "Pago de Tarjeta" }.map(\.amount), [Money(minor: -30_000)])
    }

    // MARK: Compra

    private func investmentSetup() async throws -> (Setup, InvestmentModel, Holding) {
        let s = try await setup()
        let investments = InvestmentModel(household: s.home, service: s.services.investments, households: s.services.households)
        await investments.load()
        let saved = await investments.save(Holding(householdId: s.home.id, name: "Fondo de prueba", price: 10, feeRate: Decimal(string: "0.2")!))
        return (s, investments, try XCTUnwrap(saved))
    }

    func testBuy() async throws {
        let (s, investments, fund) = try await investmentSetup()
        let quote = try XCTUnwrap(BuyQuote.byAmount(Money(minor: 50_000), price: fund.price, feeRate: fund.feeRate))
        XCTAssertEqual(quote.quantity, 50)
        XCTAssertEqual(quote.total, Money(minor: 50_100))

        let bought = await investments.buy(quote.trade(for: fund, price: fund.price, on: day(2026, 11, 4), id: UUID()), of: fund,
                                           paying: quote.total, from: s.checking.id, finance: s.finance)
        XCTAssertTrue(bought)
        XCTAssertEqual(investments.position(of: fund).quantity, 50)
        XCTAssertEqual(investments.position(of: fund).cost, Money(minor: 50_100))
        XCTAssertEqual(s.finance.balances[s.checking.id], Money(minor: 49_900))
        let charge = try XCTUnwrap(s.finance.recent.first { $0.description == "Compra de Fondo de prueba" })
        XCTAssertEqual(charge.amount, Money(minor: -50_100))
        XCTAssertEqual(charge.bookedOn, day(2026, 11, 4))
        XCTAssertEqual(s.finance.category(charge.categoryId)?.budgetGroup, .savings)
        let storedTrades = try await s.backend.trades(in: s.home.id)
        XCTAssertEqual(storedTrades.count, 1)
        let stored = try await storedBalances(s)
        XCTAssertEqual(stored[s.checking.id], Money(minor: 49_900))
    }

    func testBuyWithoutAccountOnlyStoresTheTrade() async throws {
        let (s, investments, fund) = try await investmentSetup()
        let quote = try XCTUnwrap(BuyQuote.byQuantity(5, price: fund.price, feeRate: fund.feeRate))
        let bought = await investments.buy(quote.trade(for: fund, price: fund.price, on: day(2026, 11, 4), id: UUID()), of: fund,
                                           paying: quote.total, from: nil, finance: s.finance)
        XCTAssertTrue(bought)
        XCTAssertEqual(investments.position(of: fund).quantity, 5)
        let stored = try await storedBalances(s)
        XCTAssertEqual(stored[s.checking.id], Money(minor: 100_000))
    }

    func testBuyWhenTheCashMovementFails() async throws {
        let (s, investments, fund) = try await investmentSetup()
        let quote = try XCTUnwrap(BuyQuote.byAmount(Money(minor: 50_000), price: fund.price, feeRate: fund.feeRate))
        let id = UUID()
        await s.backend.failCalls("addMovement(_:in:)")

        let bought = await investments.buy(quote.trade(for: fund, price: fund.price, on: day(2026, 11, 4), id: id), of: fund,
                                           paying: quote.total, from: s.checking.id, finance: s.finance)
        XCTAssertFalse(bought)
        XCTAssertEqual(investments.error, networkMessage)
        XCTAssertEqual(s.finance.balances[s.checking.id], Money(minor: 100_000), "la cuenta no se movió")
        var stored = try await storedBalances(s)
        XCTAssertEqual(stored[s.checking.id], Money(minor: 100_000))
        var storedTrades = try await s.backend.trades(in: s.home.id)
        XCTAssertEqual(storedTrades.count, 0, "una compra a medias no debe quedar guardada")
        XCTAssertEqual(investments.trades.count, 0)
        XCTAssertEqual(investments.position(of: fund).quantity, 0)

        // Al reintentar desde el mismo formulario la compra entra entera, una sola vez.
        await s.backend.clearFailures()
        for _ in 1...2 {
            let retried = await investments.buy(quote.trade(for: fund, price: fund.price, on: day(2026, 11, 4), id: id), of: fund,
                                           paying: quote.total, from: s.checking.id, finance: s.finance)
            XCTAssertTrue(retried, "repetir la petición no es un error")
        }
        storedTrades = try await s.backend.trades(in: s.home.id)
        XCTAssertEqual(storedTrades.map(\.id), [id])
        XCTAssertEqual(investments.trades.map(\.id), [id])
        XCTAssertEqual(investments.position(of: fund).quantity, 50)
        stored = try await storedBalances(s)
        XCTAssertEqual(stored[s.checking.id], Money(minor: 49_900), "un solo cargo")
        XCTAssertEqual(s.finance.balances, stored)
        XCTAssertEqual(s.finance.recent.filter { $0.description == "Compra de Fondo de prueba" }.count, 1)

        // Desde el mismo formulario pero con otro importe: no se da por guardada.
        let other = try XCTUnwrap(BuyQuote.byAmount(Money(minor: 10_000), price: fund.price, feeRate: fund.feeRate))
        let changed = await investments.buy(other.trade(for: fund, price: fund.price, on: day(2026, 11, 4), id: id), of: fund,
                                           paying: other.total, from: s.checking.id, finance: s.finance)
        XCTAssertFalse(changed)
        XCTAssertEqual(investments.error, TransferDraft.storedWithOtherData)
        XCTAssertEqual(investments.position(of: fund).quantity, 50)
        let after = try await storedBalances(s)
        XCTAssertEqual(after, stored, "no se apunta nada")
    }

    // MARK: Venta

    private func sellSetup() async throws -> (Setup, InvestmentModel, Holding, InvestmentTrade) {
        let (s, investments, fund) = try await investmentSetup()
        let buy = InvestmentTrade(householdId: s.home.id, holdingId: fund.id, tradedOn: day(2026, 11, 2), quantity: 10, price: 10)
        let bought = await investments.add(buy)
        XCTAssertTrue(bought)
        let sale = InvestmentTrade(householdId: s.home.id, holdingId: fund.id, tradedOn: day(2026, 11, 4), side: .sell,
                                   quantity: 4, price: 12, fee: Money(minor: 50))
        XCTAssertEqual(sale.cashImpact, Money(minor: 4_750))
        return (s, investments, fund, sale)
    }

    func testSell() async throws {
        let (s, investments, fund, sale) = try await sellSetup()
        let sold = await investments.sell(sale, of: fund, into: s.checking.id, finance: s.finance)
        XCTAssertTrue(sold)
        XCTAssertEqual(investments.position(of: fund).quantity, 6)
        // 48 € − 0,50 € − 40 € de coste = 7,50 €.
        XCTAssertEqual(investments.position(of: fund).realized, Money(minor: 750))
        XCTAssertEqual(s.finance.balances[s.checking.id], Money(minor: 104_750))
        XCTAssertEqual(s.finance.recent.first { $0.description == "Venta de Fondo de prueba" }?.amount, Money(minor: 4_750))
        let stored = try await storedBalances(s)
        XCTAssertEqual(stored[s.checking.id], Money(minor: 104_750))
        let storedTrades = try await s.backend.trades(in: s.home.id)
        XCTAssertEqual(storedTrades.count, 2)
    }

    func testSellWhenTheCashMovementFails() async throws {
        let (s, investments, fund, sale) = try await sellSetup()
        await s.backend.failCalls("addMovement(_:in:)")

        let sold = await investments.sell(sale, of: fund, into: s.checking.id, finance: s.finance)
        XCTAssertFalse(sold)
        XCTAssertEqual(investments.error, networkMessage)
        XCTAssertEqual(s.finance.balances[s.checking.id], Money(minor: 100_000), "no entró el dinero")
        var stored = try await storedBalances(s)
        XCTAssertEqual(stored[s.checking.id], Money(minor: 100_000))
        var storedTrades = try await s.backend.trades(in: s.home.id)
        XCTAssertEqual(storedTrades.count, 1, "una venta a medias no debe quedar guardada")
        XCTAssertEqual(investments.trades.map(\.id), storedTrades.map(\.id))
        XCTAssertEqual(investments.position(of: fund).quantity, 10)

        // «Guardar» otra vez en la misma hoja (misma venta, mismo id): una sola venta y un solo ingreso.
        await s.backend.clearFailures()
        for _ in 1...2 {
            let retried = await investments.sell(sale, of: fund, into: s.checking.id, finance: s.finance)
            XCTAssertTrue(retried, "repetir la petición no es un error")
        }
        storedTrades = try await s.backend.trades(in: s.home.id)
        XCTAssertEqual(storedTrades.filter { $0.side == .sell }.map(\.id), [sale.id])
        XCTAssertEqual(investments.position(of: fund).quantity, 6)
        stored = try await storedBalances(s)
        XCTAssertEqual(stored[s.checking.id], Money(minor: 104_750), "un solo ingreso")
        XCTAssertEqual(s.finance.balances, stored)
    }

    func testSellCannotLeaveALaterSaleWithoutShares() async throws {
        let (s, investments, fund, sale) = try await sellSetup()
        let sold = await investments.sell(sale, of: fund, into: nil, finance: s.finance)
        XCTAssertTrue(sold)

        // Compró 10 el día 2 y vendió 4 el día 4. Vender 7 el día 3 dejaría el día 4 en 10 − 7 − 4 = −1.
        let earlier = InvestmentTrade(householdId: s.home.id, holdingId: fund.id, tradedOn: day(2026, 11, 3), side: .sell,
                                      quantity: 7, price: 12)
        let oversold = await investments.sell(earlier, of: fund, into: s.checking.id, finance: s.finance)
        XCTAssertFalse(oversold)
        XCTAssertEqual(investments.error, InvestmentTrade.notEnoughShares)

        // Y la compra de la que depende la venta no se puede borrar; la venta sí, y después la compra.
        let buy = try XCTUnwrap(investments.trades.first { $0.side == .buy })
        let deleted = await investments.delete(buy)
        XCTAssertFalse(deleted)
        XCTAssertEqual(investments.error, InvestmentTrade.neededByLaterSale)
        var storedTrades = try await s.backend.trades(in: s.home.id)
        XCTAssertEqual(storedTrades.count, 2)
        let stored = try await storedBalances(s)
        XCTAssertEqual(stored[s.checking.id], Money(minor: 100_000))

        let saleDeleted = await investments.delete(sale)
        XCTAssertTrue(saleDeleted)
        let buyDeleted = await investments.delete(buy)
        XCTAssertTrue(buyDeleted)
        storedTrades = try await s.backend.trades(in: s.home.id)
        XCTAssertTrue(storedTrades.isEmpty)
    }
}
