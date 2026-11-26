import XCTest
import STMCore
@testable import SaveTheMoney

/// ORC-84: la tarjeta guarda su copia de las cuentas. Al crear, editar o archivar una cuenta de tarjeta, lo que
/// muestra la tarjeta tiene que cambiar sin volver a cargar a mano. Datos inventados.
@MainActor
final class CreditCardAccountRefreshTests: XCTestCase {
    private struct Setup {
        let services: AppServices
        let home: Household
        let finance: FinanceModel
        let cards: CreditCardModel
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
        let finance = FinanceModel(household: home, service: services.finance)
        await finance.load()
        let cards = CreditCardModel(household: home, service: services.creditCards, finance: services.finance)
        return Setup(services: services, home: home, finance: finance, cards: cards)
    }

    /// Lo que haría RootView al cambiar: vuelve a cargar la tarjeta con lo último de FinanceModel.
    private func reload(_ s: Setup) async {
        await s.cards.load(accounts: s.finance.accounts, balances: s.finance.balances, categories: s.finance.categories)
    }

    private func createCard(_ s: Setup) async throws -> Account {
        let created = await s.finance.createAccount(AccountDraft(name: "Tarjeta", kind: .creditCard))
        XCTAssertTrue(created)
        let card = try XCTUnwrap(s.finance.accounts.first { $0.kind == .creditCard })
        _ = try await s.services.creditCards.saveCreditCard(
            CreditCardTerms(accountId: card.id, householdId: s.home.id, creditLimit: Money(minor: 300_000)))
        return card
    }

    func testCreatingCardAccountChangesInputs() async throws {
        let s = try await setup()
        await reload(s)
        XCTAssertTrue(s.cards.cardAccounts.isEmpty)
        let before = CreditCardModel.Inputs(finance: s.finance)

        _ = try await createCard(s)

        XCTAssertNotEqual(CreditCardModel.Inputs(finance: s.finance), before, "la lista de cuentas cambia al crear")
        await reload(s)
        XCTAssertEqual(s.cards.cardAccounts.map(\.name), ["Tarjeta"])
    }

    func testEditingOpeningBalanceUpdatesSummary() async throws {
        let s = try await setup()
        let card = try await createCard(s)
        await reload(s)
        XCTAssertEqual(s.cards.summary(for: card)?.used, Money(minor: 0))
        let before = CreditCardModel.Inputs(finance: s.finance)

        var edited = card
        edited.openingBalance = Money(minor: -45_000)
        let updated = await s.finance.updateAccount(edited)
        XCTAssertTrue(updated)

        XCTAssertNotEqual(CreditCardModel.Inputs(finance: s.finance), before, "el saldo inicial cambia la cuenta")
        await reload(s)
        XCTAssertEqual(s.cards.summary(for: card)?.used, Money(minor: 45_000))
    }

    func testArchivingCardAccountRemovesItsSummary() async throws {
        let s = try await setup()
        let card = try await createCard(s)
        await reload(s)
        XCTAssertNotNil(s.cards.summary(for: card))
        let before = CreditCardModel.Inputs(finance: s.finance)

        var archived = card
        archived.archivedAt = Date()
        let archivedOK = await s.finance.updateAccount(archived)
        XCTAssertTrue(archivedOK)

        XCTAssertNotEqual(CreditCardModel.Inputs(finance: s.finance), before, "archivar cambia la cuenta")
        await reload(s)
        XCTAssertTrue(s.cards.cardAccounts.isEmpty)
        XCTAssertNil(s.cards.summary(for: card))
    }
}
