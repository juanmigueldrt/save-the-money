import XCTest
@testable import STMCore

/// Descripciones inventadas con la forma de las de los bancos españoles.
final class MerchantTests: XCTestCase {
    let household = UUID()

    func testDisplayIsAlwaysUppercase() {
        XCTAssertEqual(MovementText.display("Compra en farmacia ñandú"), "COMPRA EN FARMACIA ÑANDÚ")
        XCTAssertEqual(MovementText.display("APPLE.COM/BILL"), "APPLE.COM/BILL")
    }

    func testRecognisesTheExamplesJeanGave() {
        XCTAssertEqual(MerchantDirectory.match("COMPRA TARJ. FARMACIA LDO PEREZ")?.name, "Farmacia")
        XCTAssertEqual(MerchantDirectory.match("Apple.com/bill ITUNES.COM")?.name, "Apple")
        XCTAssertEqual(MerchantDirectory.match("GOOGLE *Google One")?.name, "Google One")
        XCTAssertEqual(MerchantDirectory.match("Supermercado La Esquina")?.name, "Supermercado")
        XCTAssertEqual(MerchantDirectory.match("PAGO MOVIL EN MERCADONA, MADRID")?.name, "Mercadona")
    }

    func testLongestKeywordWins() {
        XCTAssertEqual(MerchantDirectory.match("UBER EATS PEDIDO")?.name, "Uber Eats")
        XCTAssertEqual(MerchantDirectory.match("UBER TRIP")?.name, "Uber")
        XCTAssertEqual(MerchantDirectory.match("APPLE STORE GRAN VIA")?.name, "Apple Store")
        XCTAssertEqual(MerchantDirectory.match("Google YouTube Premium")?.name, "YouTube")
    }

    func testMatchesWholeWordsOnly() {
        XCTAssertNil(MerchantDirectory.match("PINEAPPLE JUICE BAR"))
        XCTAssertNil(MerchantDirectory.match("TRANSFERENCIA A JUAN"))
        XCTAssertNil(MerchantDirectory.match(""))
    }

    func testLogoOnlyCarriesTheDomain() {
        let apple = MerchantDirectory.match("APPLE.COM/BILL")
        XCTAssertEqual(apple?.logoURL?.absoluteString, "https://www.google.com/s2/favicons?domain=apple.com&sz=128")
        XCTAssertNil(MerchantDirectory.match("FARMACIA CENTRAL")?.logoURL)
        let fake = "pk_" + "ejemplo"  // inventada; partida para que gitleaks no la tome por real
        XCTAssertEqual(apple?.logoURL(logoDevToken: " \(fake) ")?.absoluteString,
                       "https://img.logo.dev/apple.com?token=\(fake)&size=128&format=png&retina=true")
        // Una clave secreta o vacía no se usa: se queda el favicon de Google.
        XCTAssertEqual(apple?.logoURL(logoDevToken: "sk_secreta"), apple?.logoURL)
        XCTAssertEqual(apple?.logoURL(logoDevToken: ""), apple?.logoURL)
        XCTAssertEqual(apple?.logoURL(logoDevToken: "pega-aqui"), apple?.logoURL)
    }

    func testEveryMerchantPointsToADefaultCategory() {
        let defaults: Set<String> = ["Vivienda", "Supermercado", "Suministros", "Transporte", "Salud", "Seguros",
                                     "Restaurantes", "Ocio", "Compras", "Viajes", "Suscripciones"]
        for merchant in MerchantDirectory.all {
            XCTAssertTrue(defaults.contains(merchant.category), "\(merchant.name) -> \(merchant.category)")
            XCTAssertFalse(merchant.keywords.isEmpty, merchant.name)
        }
    }

    func testSuggestsTheUsersCategoryOnlyForExpenses() {
        let health = BudgetCategory(householdId: household, name: "Salud", kind: .expense, budgetGroup: .needs)
        let subs = BudgetCategory(householdId: household, name: "suscripciones", kind: .expense, budgetGroup: .wants)
        let income = BudgetCategory(householdId: household, name: "Salud", kind: .income)
        let categories = [income, health, subs]
        XCTAssertEqual(MerchantDirectory.suggestedCategory(for: "Farmacia", isExpense: true, in: categories), health)
        XCTAssertEqual(MerchantDirectory.suggestedCategory(for: "GOOGLE ONE", isExpense: true, in: categories), subs)
        XCTAssertNil(MerchantDirectory.suggestedCategory(for: "Farmacia", isExpense: false, in: categories))
        XCTAssertNil(MerchantDirectory.suggestedCategory(for: "MERCADONA", isExpense: true, in: categories))
    }

    func testCategorizeKeepsChosenCategoriesAndHashes() {
        let account = UUID()
        let food = BudgetCategory(householdId: household, name: "Supermercado", kind: .expense, budgetGroup: .needs)
        let other = BudgetCategory(householdId: household, name: "Ocio", kind: .expense, budgetGroup: .wants)
        let day = CalendarDay(year: 2026, month: 10, day: 3)!
        let rows = [
            CSVImportRow(line: 2, draft: MovementDraft(accountId: account, bookedOn: day, amount: Money(minor: -2350),
                                                       description: "Lidl Avda Sol", importHash: "a"), issue: nil),
            CSVImportRow(line: 3, draft: MovementDraft(accountId: account, categoryId: other.id, bookedOn: day,
                                                       amount: Money(minor: -900), description: "Lidl", importHash: "b"),
                         issue: nil),
            CSVImportRow(line: 4, draft: nil, issue: .invalidAmount)
        ]
        let result = MerchantDirectory.categorize(rows, with: [food, other])
        XCTAssertEqual(result[0].draft?.categoryId, food.id)
        XCTAssertEqual(result[0].draft?.description, "Lidl Avda Sol")
        XCTAssertEqual(result[0].draft?.importHash, "a")
        XCTAssertEqual(result[1].draft?.categoryId, other.id)
        XCTAssertNil(result[2].draft)
    }

    func testLearnsFromTheUsersOwnChoices() {
        let account = UUID()
        let gym = BudgetCategory(householdId: household, name: "Ocio", kind: .expense, budgetGroup: .wants)
        let health = BudgetCategory(householdId: household, name: "Salud", kind: .expense, budgetGroup: .needs)
        func movement(_ text: String, _ category: BudgetCategory?, day: Int) -> Movement {
            Movement(householdId: household, accountId: account, categoryId: category?.id,
                     bookedOn: CalendarDay(year: 2026, month: 10, day: day)!, amount: Money(minor: -3000), description: text)
        }
        let learner = CategoryLearner(movements: [
            movement("RECIBO GIMNASIO BARRIO 0012345", health, day: 1),
            movement("RECIBO GIMNASIO BARRIO 0067890", gym, day: 5),
            movement("FARMACIA CENTRAL", gym, day: 2),
            movement("SIN CATEGORIA", nil, day: 3),
        ])
        let categories = [gym, health]
        // Números distintos, mismo concepto: gana la elección más reciente.
        XCTAssertEqual(MerchantDirectory.suggestedCategory(for: "Recibo gimnasio barrio 0099999", isExpense: true,
                                                           in: categories, learned: learner), gym)
        // Lo aprendido manda sobre la categoría por defecto del comercio.
        XCTAssertEqual(MerchantDirectory.suggestedCategory(for: "FARMACIA LA PLAZA", isExpense: true,
                                                           in: categories, learned: learner), gym)
        XCTAssertEqual(MerchantDirectory.suggestedCategory(for: "FARMACIA LA PLAZA", isExpense: true,
                                                           in: categories), health)
        XCTAssertNil(learner.categoryId(for: "SIN CATEGORIA"))
        XCTAssertNil(learner.categoryId(for: "12345 67890"))
    }
}
