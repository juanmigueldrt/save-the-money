import XCTest
@testable import STMCore

/// Ciclo de la tarjeta, cargos a fin de mes, revolving y aplazados. Datos inventados.
final class CreditCardTests: XCTestCase {
    let home = UUID()
    let card = UUID()
    let transfer = UUID()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }

    private func move(_ amount: Int, on date: CalendarDay, payment: Bool = false) -> Movement {
        Movement(householdId: home, accountId: card, categoryId: payment ? transfer : nil, bookedOn: date,
                 amount: Money(minor: amount), description: payment ? "Pago de la tarjeta" : "Compra de prueba")
    }

    private func terms(_ mode: CardPaymentMode = .full, fixed: Int? = nil) -> CreditCardTerms {
        CreditCardTerms(accountId: card, householdId: home, creditLimit: Money(minor: 300_000), paymentMode: mode,
                        fixedPayment: fixed.map { Money(minor: $0) })
    }

    private func summary(_ terms: CreditCardTerms, _ movements: [Movement], installments: [CardInstallment] = [],
                         today: CalendarDay) -> CreditCardSummary {
        let balance = Money(minor: movements.map(\.amount.minor).reduce(0, +))
        return CreditCardCalculator.summary(terms: terms, balance: balance, movements: movements, installments: installments,
                                            transferCategories: [transfer], today: today)
    }

    func testCycleDates() {
        let t = terms()
        // Lo gastado en enero entra en el extracto del 1 de febrero y se cobra el 1 de marzo.
        XCTAssertEqual(t.statementClosing(for: day(2027, 1, 1)), day(2027, 2, 1))
        XCTAssertEqual(t.statementClosing(for: day(2027, 1, 31)), day(2027, 2, 1))
        XCTAssertEqual(t.paymentDate(forStatement: day(2027, 2, 1)), day(2027, 3, 1))
        var other = t
        other.statementDay = 25
        other.paymentDelayMonths = 0
        other.paymentDay = 10
        XCTAssertEqual(other.statementClosing(for: day(2027, 1, 24)), day(2027, 1, 25))
        XCTAssertEqual(other.statementClosing(for: day(2027, 1, 25)), day(2027, 2, 25))
        XCTAssertEqual(other.paymentDate(forStatement: day(2027, 1, 25)), day(2027, 1, 10))
        XCTAssertEqual(other.cycleStart(forStatement: day(2027, 2, 25)), day(2027, 1, 25))
    }

    func testFullPaymentEachMonth() {
        let movements = [
            move(-15_000, on: day(2026, 9, 5)),
            move(15_000, on: day(2026, 11, 1), payment: true),   // pago del extracto del 1 de octubre
            move(-20_000, on: day(2026, 10, 10)),
            move(-10_000, on: day(2026, 10, 20)),
            move(2_000, on: day(2026, 10, 25)),                  // devolución
            move(-5_000, on: day(2026, 11, 2)),
        ]
        let s = summary(terms(), movements, today: day(2026, 11, 4))
        XCTAssertEqual(s.used, Money(minor: 33_000))
        XCTAssertEqual(s.available, Money(minor: 267_000))
        XCTAssertEqual(s.openStatement, day(2026, 12, 1))
        XCTAssertEqual(s.spentThisCycle, Money(minor: 5_000))
        XCTAssertEqual(s.payments.count, 6)
        // Octubre (con la devolución) se cobra el 1 de diciembre; noviembre, el 1 de enero.
        XCTAssertEqual(s.next?.due, day(2026, 12, 1))
        XCTAssertEqual(s.next?.amount, Money(minor: 28_000))
        XCTAssertEqual(s.next?.isEstimate, false)
        XCTAssertEqual(s.payments[1].due, day(2027, 1, 1))
        XCTAssertEqual(s.payments[1].amount, Money(minor: 5_000))
        XCTAssertEqual(s.payments[1].isEstimate, true)
        XCTAssertEqual(s.payments[2].amount, .zero)
        XCTAssertEqual(s.interestInPayments, .zero)
        XCTAssertNil(s.payoff)
        XCTAssertFalse(s.isOverAlert)
    }

    func testInstallmentsAddToEachPayment() {
        let purchase = move(-60_000, on: day(2026, 11, 3))
        let movements = [move(-28_000, on: day(2026, 10, 10)), move(-5_000, on: day(2026, 11, 2)), purchase]
        let plan = CardInstallment(householdId: home, accountId: card, movementId: purchase.id, months: 6, rate: 14)
        let s = summary(terms(), movements, installments: [plan], today: day(2026, 11, 4))
        XCTAssertEqual(CardInstallment.payment(principal: Money(minor: 60_000), months: 6, rate: 14), Money(minor: 10_412))
        XCTAssertEqual(s.used, Money(minor: 93_000))
        // La compra aplazada no entra entera: sólo su cuota, desde el extracto de la compra.
        XCTAssertEqual(s.spentThisCycle, Money(minor: 5_000))
        XCTAssertEqual(s.payments[0].amount, Money(minor: 28_000))
        XCTAssertEqual(s.payments[1].amount, Money(minor: 5_000 + 10_412))
        XCTAssertEqual(s.payments[1].installments, Money(minor: 10_412))
        XCTAssertEqual(s.payments[1].interest, Money(minor: 700))
        XCTAssertEqual(s.payments[2].amount, Money(minor: 10_412))
        // Las seis cuotas devuelven justo los 600 €.
        let rows = CreditCardCalculator.amortization(principal: Money(minor: 60_000), months: 6, rate: 14)
        XCTAssertEqual(rows.map(\.principal).reduce(0, +), 60_000)
        XCTAssertEqual(rows.last?.payment, 10_414)
        // Sin interés, cuotas iguales.
        XCTAssertEqual(CardInstallment.payment(principal: Money(minor: 30_000), months: 3, rate: 0), Money(minor: 10_000))
    }

    func testMinimumPaymentWithInterest() throws {
        let movements = [move(-100_000, on: day(2026, 9, 5))]
        let s = summary(terms(.minimum), movements, today: day(2026, 11, 4))
        XCTAssertEqual(s.revolvingBalance, Money(minor: 100_000))
        // 1.000 € al 20 %: 16,67 € de intereses + 3 % (30 €) = 46,67 €.
        XCTAssertEqual(s.next?.amount, Money(minor: 4_667))
        XCTAssertEqual(s.next?.interest, Money(minor: 1_667))
        // Queda 970 €: 16,17 € + 29,10 €.
        XCTAssertEqual(s.payments[1].amount, Money(minor: 4_527))
        XCTAssertGreaterThan(s.interestInPayments.minor, 0)
        let payoff = try XCTUnwrap(s.payoff)
        XCTAssertGreaterThan(payoff.months, 24)
        XCTAssertGreaterThan(payoff.interest.minor, 10_000)
    }

    func testMinimumNeverBelowFloorNorAboveDebt() {
        let t = terms(.minimum)
        // 100 €: 3 € + 1,67 € < 15 € → 15 €.
        XCTAssertEqual(CreditCardCalculator.revolvingStep(capital: 10_000, terms: t).payment, 1_500)
        // 10 €: se paga todo, intereses incluidos.
        let small = CreditCardCalculator.revolvingStep(capital: 1_000, terms: t)
        XCTAssertEqual(small.payment, 1_017)
        XCTAssertEqual(small.remaining, 0)
    }

    func testFixedPaymentPaysOffSooner() throws {
        let movements = [move(-100_000, on: day(2026, 9, 5))]
        let minimum = summary(terms(.minimum), movements, today: day(2026, 11, 4))
        let fixed = summary(terms(.fixed, fixed: 20_000), movements, today: day(2026, 11, 4))
        XCTAssertEqual(fixed.next?.amount, Money(minor: 20_000))
        let a = try XCTUnwrap(minimum.payoff), b = try XCTUnwrap(fixed.payoff)
        XCTAssertLessThan(b.months, a.months)
        XCTAssertLessThan(b.interest, a.interest)
        // Una cuota fija por debajo del mínimo no vale: se paga el mínimo.
        let tooLow = summary(terms(.fixed, fixed: 100), movements, today: day(2026, 11, 4))
        XCTAssertEqual(tooLow.next?.amount, Money(minor: 4_667))
    }

    func testLimitAlertAndReminders() throws {
        let movements = [move(-250_000, on: day(2026, 10, 10))]
        let s = summary(terms(), movements, today: day(2026, 11, 4))
        XCTAssertTrue(s.isOverAlert)
        let alert = try XCTUnwrap(BudgetAlertPlanner.cardAlert(for: s, name: "Tarjeta de prueba"))
        XCTAssertTrue(alert.title.contains("83 %"))
        XCTAssertTrue(alert.id.contains("2026-12-01"))

        let reminders = ReminderPlanner.plan(cards: [(s, "Tarjeta de prueba", Money(minor: 100_000))], today: day(2026, 11, 4))
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.fireOn, day(2026, 11, 29))
        XCTAssertTrue(reminders.first?.id.hasPrefix(ReminderPlanner.cardPrefix) ?? false)
        XCTAssertTrue(reminders.first?.body.contains("sólo hay") ?? false)
    }

    func testTermsValidation() {
        var t = terms()
        XCTAssertNil(t.issue)
        t.paymentMode = .fixed
        XCTAssertNotNil(t.issue)
        t.fixedPayment = Money(minor: 10_000)
        XCTAssertNil(t.issue)
        t.statementDay = 31
        XCTAssertNotNil(t.issue)
        t.statementDay = 1
        t.payFromAccountId = card
        XCTAssertNotNil(t.issue)
    }

    func testCodableRoundTrip() throws {
        var t = terms(.fixed, fixed: 12_345)
        t.revolvingRate = Decimal(string: "21.5")!
        // Sólo se envían las columnas que se pueden cambiar.
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(t)) as? [String: Any])
        XCTAssertNil(sent["account_id"])
        XCTAssertNil(sent["household_id"])
        XCTAssertEqual(sent["fixed_payment_minor"] as? Int, 12_345)
        let json = #"{"account_id":"\#(card.uuidString)","household_id":"\#(home.uuidString)","credit_limit_minor":300000,"statement_day":1,"payment_day":1,"payment_delay_months":1,"payment_mode":"minimum","fixed_payment_minor":null,"min_payment_percent":3.00,"min_payment_minor":1500,"revolving_rate":20.00,"installment_rate":14.00,"pay_from_account_id":null,"remind_days_before":2,"alert_percent":80}"#
        let decoded = try JSONDecoder().decode(CreditCardTerms.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.paymentMode, .minimum)
        XCTAssertEqual(decoded.revolvingRate, 20)
    }

    func testInMemoryRules() async throws {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        let household = try await backend.createHousehold(name: "Casa de prueba")
        let cardAccount = try await backend.createAccount(AccountDraft(name: "Tarjeta", kind: .creditCard), in: household.id)
        let checking = try await backend.createAccount(AccountDraft(name: "Cuenta"), in: household.id)

        let bad = CreditCardTerms(accountId: checking.id, householdId: household.id, creditLimit: Money(minor: 100_000))
        do { _ = try await backend.saveCreditCard(bad); XCTFail("una cuenta corriente no es una tarjeta") } catch {}

        var good = CreditCardTerms(accountId: cardAccount.id, householdId: household.id, creditLimit: Money(minor: 300_000),
                                   payFromAccountId: checking.id)
        _ = try await backend.saveCreditCard(good)
        good.creditLimit = Money(minor: 250_000)
        _ = try await backend.saveCreditCard(good)
        let cards = try await backend.creditCards(in: household.id)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.creditLimit, Money(minor: 250_000))

        let purchase = try await backend.addMovement(
            MovementDraft(accountId: cardAccount.id, bookedOn: CalendarDay(), amount: Money(minor: -60_000), description: "Compra"),
            in: household.id)
        let other = try await backend.addMovement(
            MovementDraft(accountId: checking.id, bookedOn: CalendarDay(), amount: Money(minor: -1_000), description: "Otra"),
            in: household.id)
        let wrong = CardInstallment(householdId: household.id, accountId: cardAccount.id, movementId: other.id, months: 3)
        do { _ = try await backend.saveInstallment(wrong); XCTFail("sólo compras de la tarjeta") } catch {}
        _ = try await backend.saveInstallment(CardInstallment(householdId: household.id, accountId: cardAccount.id,
                                                              movementId: purchase.id, months: 6))
        var count = try await backend.cardInstallments(in: household.id).count
        XCTAssertEqual(count, 1)
        try await backend.deleteMovement(purchase.id)
        count = try await backend.cardInstallments(in: household.id).count
        XCTAssertEqual(count, 0, "al borrar la compra se borra su aplazado")
        try await backend.deleteAccount(checking.id)
        let after = try await backend.creditCards(in: household.id)
        XCTAssertNil(after.first?.payFromAccountId)
    }
}
