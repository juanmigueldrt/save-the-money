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

        let paused = await investments.setPaused(true, plan)
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
        await backend.failCalls("addTrade(_:)", with: CancellationError())
        let cancelled = await investments.add(second)
        XCTAssertFalse(cancelled)
        XCTAssertEqual(investments.trades.map(\.id), [buy.id])

        await backend.clearFailures()
        let stored = try await backend.trades(in: home.id)
        XCTAssertEqual(stored.map(\.id), [buy.id])
    }
}

/// Los flujos con dos escrituras. Viven en las vistas (`CardPaymentFormView.save`, `BuyCard.buy`,
/// `SellView.save`), así que cada prueba repite sus llamadas a los modelos en el mismo orden.
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

    /// Igual que `CardPaymentFormView.save`: salida de la cuenta y entrada en la tarjeta, como transferencia.
    private func payCard(_ card: Account, from: Account, amount: Money, on date: CalendarDay, finance: FinanceModel) async -> Bool {
        let transfer = finance.categories(for: .transfer).first?.id
        let out = MovementDraft(accountId: from.id, categoryId: transfer, bookedOn: date, amount: -amount,
                                description: "Pago de \(card.name)")
        let inbound = MovementDraft(accountId: card.id, categoryId: transfer, bookedOn: date, amount: amount,
                                    description: "Pago de la tarjeta")
        guard await finance.add(out) else { return false }
        guard await finance.add(inbound) else { return false }
        return true
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
        await s.backend.failCalls("addMovement(_:in:)", after: 1)
        let paid = await payCard(card, from: s.checking, amount: Money(minor: 30_000), on: day(2026, 11, 4), finance: s.finance)
        XCTAssertFalse(paid)
        XCTAssertEqual(s.finance.error, networkMessage)
        // El modelo enseña lo mismo que hay guardado.
        let stored = try await storedBalances(s)
        XCTAssertEqual(s.finance.balances, stored)
        XCTAssertEqual(stored[card.id], Money(minor: -30_000), "la entrada en la tarjeta no se guardó")

        XCTExpectFailure("ORC-107: el pago no se deshace si falla la segunda escritura; queda sólo la salida de la cuenta") {
            XCTAssertEqual(stored[s.checking.id], Money(minor: 100_000), "un pago a medias no debe sacar dinero de la cuenta")
            XCTAssertFalse(s.finance.recent.contains { $0.description == "Pago de Tarjeta" }, "no debe quedar la mitad del pago")
        }
    }

    // MARK: Compra

    /// Igual que `BuyCard.buy` sin «Repetir cada mes»: la operación y luego el cargo en la cuenta.
    private func buy(_ quote: BuyQuote, of holding: Holding, from account: Account, on date: CalendarDay,
                     investments: InvestmentModel, finance: FinanceModel) async -> Bool {
        guard await investments.add(quote.trade(for: holding, price: holding.price, on: date)) else { return false }
        let savings = finance.categories.first { $0.kind == .expense && $0.budgetGroup == .savings }
        let draft = MovementDraft(accountId: account.id, categoryId: savings?.id, bookedOn: date,
                                  amount: -quote.total, description: "Compra de \(holding.trimmedName)")
        return await finance.add(draft)
    }

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

        let bought = await buy(quote, of: fund, from: s.checking, on: day(2026, 11, 4), investments: investments, finance: s.finance)
        XCTAssertTrue(bought)
        XCTAssertEqual(investments.position(of: fund).quantity, 50)
        XCTAssertEqual(investments.position(of: fund).cost, Money(minor: 50_100))
        XCTAssertEqual(s.finance.balances[s.checking.id], Money(minor: 49_900))
        let storedTrades = try await s.backend.trades(in: s.home.id)
        XCTAssertEqual(storedTrades.count, 1)
        let stored = try await storedBalances(s)
        XCTAssertEqual(stored[s.checking.id], Money(minor: 49_900))
    }

    func testBuyWhenTheCashMovementFails() async throws {
        let (s, investments, fund) = try await investmentSetup()
        let quote = try XCTUnwrap(BuyQuote.byAmount(Money(minor: 50_000), price: fund.price, feeRate: fund.feeRate))
        await s.backend.failCalls("addMovement(_:in:)")

        let bought = await buy(quote, of: fund, from: s.checking, on: day(2026, 11, 4), investments: investments, finance: s.finance)
        XCTAssertFalse(bought)
        XCTAssertEqual(s.finance.error, networkMessage)
        XCTAssertEqual(s.finance.balances[s.checking.id], Money(minor: 100_000), "la cuenta no se movió")
        let stored = try await storedBalances(s)
        XCTAssertEqual(stored[s.checking.id], Money(minor: 100_000))
        let storedTrades = try await s.backend.trades(in: s.home.id)
        // El modelo enseña lo mismo que hay guardado.
        XCTAssertEqual(investments.trades.map(\.id), storedTrades.map(\.id))

        XCTExpectFailure("ORC-107: la compra no se deshace si falla el cargo en la cuenta; quedan participaciones sin pagar") {
            XCTAssertEqual(storedTrades.count, 0, "una compra a medias no debe quedar guardada")
            XCTAssertEqual(investments.position(of: fund).quantity, 0)
        }
    }

    // MARK: Venta

    /// Igual que `SellView.save`: la operación y luego el ingreso en la cuenta.
    private func sell(_ trade: InvestmentTrade, of holding: Holding, into account: Account,
                      investments: InvestmentModel, finance: FinanceModel) async -> Bool {
        guard await investments.add(trade) else { return false }
        let draft = MovementDraft(accountId: account.id, bookedOn: trade.tradedOn, amount: trade.cashImpact,
                                  description: "Venta de \(holding.trimmedName)")
        return await finance.add(draft)
    }

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
        let sold = await sell(sale, of: fund, into: s.checking, investments: investments, finance: s.finance)
        XCTAssertTrue(sold)
        XCTAssertEqual(investments.position(of: fund).quantity, 6)
        // 48 € − 0,50 € − 40 € de coste = 7,50 €.
        XCTAssertEqual(investments.position(of: fund).realized, Money(minor: 750))
        XCTAssertEqual(s.finance.balances[s.checking.id], Money(minor: 104_750))
        let stored = try await storedBalances(s)
        XCTAssertEqual(stored[s.checking.id], Money(minor: 104_750))
        let storedTrades = try await s.backend.trades(in: s.home.id)
        XCTAssertEqual(storedTrades.count, 2)
    }

    func testSellWhenTheCashMovementFails() async throws {
        let (s, investments, fund, sale) = try await sellSetup()
        await s.backend.failCalls("addMovement(_:in:)")

        let sold = await sell(sale, of: fund, into: s.checking, investments: investments, finance: s.finance)
        XCTAssertFalse(sold)
        XCTAssertEqual(s.finance.error, networkMessage)
        XCTAssertEqual(s.finance.balances[s.checking.id], Money(minor: 100_000), "no entró el dinero")
        let stored = try await storedBalances(s)
        XCTAssertEqual(stored[s.checking.id], Money(minor: 100_000))
        let storedTrades = try await s.backend.trades(in: s.home.id)
        XCTAssertEqual(investments.trades.map(\.id).sorted { $0.uuidString < $1.uuidString },
                       storedTrades.map(\.id).sorted { $0.uuidString < $1.uuidString })

        XCTExpectFailure("ORC-107: la venta no se deshace si falla el ingreso en la cuenta; salen participaciones sin cobrar") {
            XCTAssertEqual(storedTrades.count, 1, "una venta a medias no debe quedar guardada")
            XCTAssertEqual(investments.position(of: fund).quantity, 10)
        }
    }
}
