import XCTest
import STMCore
@testable import SaveTheMoney

/// ORC-132: los movimientos de la tarjeta se cargan por fecha (desde el ciclo del extracto sin cobrar más antiguo),
/// no los N más recientes. Datos inventados.
@MainActor
final class CreditCardLoadTests: XCTestCase {
    private struct Setup {
        let services: AppServices
        let home: Household
        let card: Account
    }

    private func setup() async throws -> Setup {
        let services = AppServices.demo()
        let session = SessionModel(services: services)
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        try await session.createHousehold(name: "Casa de prueba")
        guard case .ready(_, let home) = session.state else {
            XCTFail("sin hogar")
            throw CancellationError()
        }
        let card = try await services.finance.createAccount(AccountDraft(name: "Tarjeta", kind: .creditCard), in: home.id)
        // Extracto el día 1, se cobra el día 1 del mes siguiente, pago total.
        _ = try await services.creditCards.saveCreditCard(
            CreditCardTerms(accountId: card.id, householdId: home.id, creditLimit: Money(minor: 300_000)))
        return Setup(services: services, home: home, card: card)
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) throws -> CalendarDay { try XCTUnwrap(CalendarDay(year: y, month: m, day: d)) }

    @discardableResult
    private func add(_ minor: Int, on date: CalendarDay, in s: Setup) async throws -> Movement {
        try await s.services.finance.addMovement(
            MovementDraft(accountId: s.card.id, bookedOn: date, amount: Money(minor: minor), description: "Compra de prueba"),
            in: s.home.id)
    }

    private func loadedCards(_ s: Setup, today: CalendarDay) async -> CreditCardModel {
        let finance = FinanceModel(household: s.home, service: s.services.finance)
        await finance.load()
        let cards = CreditCardModel(household: s.home, service: s.services.creditCards, finance: s.services.finance,
                                    today: { today })
        await cards.load(accounts: finance.accounts, balances: finance.balances, categories: finance.categories)
        return cards
    }

    /// Hoy 2026-11-20: sin cobrar están el extracto del 1-11 (se cobra el 1-12) y el abierto (se cierra el 1-12).
    /// 600 compras de 1 € en el ciclo abierto y una de 300 € del ciclo anterior: con los 500 más recientes faltaban
    /// 100 compras del ciclo abierto y la de 300 €.
    func testMoreThan500MovementsInTheUnpaidStatements() async throws {
        let s = try await setup()
        let today = try day(2026, 11, 20)
        _ = try await add(-30_000, on: try day(2026, 10, 10), in: s)
        for _ in 0..<600 { _ = try await add(-100, on: try day(2026, 11, 5), in: s) }
        // Una compra de un extracto ya cobrado: no hace falta cargarla.
        let paid = try await add(-7_000, on: try day(2026, 9, 15), in: s)

        let cards = await loadedCards(s, today: today)
        XCTAssertNil(cards.error)
        let summary = try XCTUnwrap(cards.summary(for: s.card))
        XCTAssertEqual(summary.spentThisCycle, Money(minor: 60_000))
        XCTAssertEqual(summary.payments.map(\.amount.minor), [30_000, 60_000, 0, 0, 0, 0])
        XCTAssertFalse(summary.movementsTruncated)
        XCTAssertFalse(cards.movements(of: s.card).contains { $0.id == paid.id }, "sólo desde el ciclo sin cobrar más antiguo")
    }

    /// Si los extractos sin cobrar tienen más movimientos que el tope, el resumen lo dice.
    func testTooManyMovementsAreFlagged() async throws {
        let s = try await setup()
        let today = try day(2026, 11, 20)
        for _ in 0..<CreditCardModel.cycleLimit { _ = try await add(-100, on: try day(2026, 11, 5), in: s) }
        let cards = await loadedCards(s, today: today)
        XCTAssertEqual(cards.summary(for: s.card)?.movementsTruncated, true)
    }

    /// Un aplazado guardado en otro dispositivo para una compra antigua: al cambiar los aplazados aquí se carga su compra.
    func testInstallmentFromAnotherDeviceLoadsItsPurchase() async throws {
        let s = try await setup()
        let today = try day(2026, 11, 20)
        let old = try await add(-120_000, on: try day(2025, 10, 15), in: s)
        let recent = try await add(-6_000, on: try day(2026, 11, 2), in: s)
        let cards = await loadedCards(s, today: today)

        let plan = try await s.services.creditCards.saveInstallment(
            CardInstallment(householdId: s.home.id, accountId: s.card.id, movementId: old.id, months: 24, rate: 14))
        let deferred = await cards.deferPurchase(recent, months: 3, in: s.card)
        XCTAssertTrue(deferred)
        XCTAssertTrue(cards.installments.contains { $0.id == plan.id })
        XCTAssertEqual(cards.summary(for: s.card)?.unresolvedInstallments, [])
        XCTAssertTrue(cards.movements(of: s.card).contains { $0.id == old.id })
    }
}
