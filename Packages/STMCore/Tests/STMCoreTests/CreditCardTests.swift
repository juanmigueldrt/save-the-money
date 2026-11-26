import XCTest
@testable import STMCore

/// Ciclo de la tarjeta, cargos a fin de mes, revolving y aplazados. Datos inventados.
final class CreditCardTests: XCTestCase {
    let home = UUID()
    let card = UUID()
    let transfer = UUID()
    let shopping = UUID()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }

    private func move(_ amount: Int, on date: CalendarDay, payment: Bool = false, refund: Bool = false) -> Movement {
        Movement(householdId: home, accountId: card, categoryId: payment ? transfer : refund ? shopping : nil, bookedOn: date,
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
            move(2_000, on: day(2026, 10, 25), refund: true),    // devolución
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
        XCTAssertEqual(s.uncategorizedCredits, [])
    }

    /// ORC-79: el pago del extracto anterior, importado de un CSV sin categoría, no es una devolución.
    /// El caso del ticket también está en `summaries` de testdata/vectors/card_installments.json.
    func testUncategorizedCreditDoesNotReduceCharges() {
        let credit = move(50_000, on: day(2026, 10, 5))
        let old = move(1_000, on: day(2026, 9, 20))      // extracto ya cobrado: no cambia ningún cargo
        let movements = [move(-51_000, on: day(2026, 9, 12)), old, credit, move(-30_000, on: day(2026, 10, 10))]
        let s = summary(terms(), movements, today: day(2026, 11, 20))
        XCTAssertEqual(s.used, Money(minor: 30_000))
        XCTAssertEqual(s.next?.due, day(2026, 12, 1))
        XCTAssertEqual(s.next?.amount, Money(minor: 30_000))
        XCTAssertEqual(s.next?.purchases, Money(minor: 30_000))
        XCTAssertEqual(s.revolvingBalance, Money(minor: 30_000))
        XCTAssertEqual(s.uncategorizedCredits, [credit.id])

        // En el extracto abierto tampoco baja lo gastado.
        let open = move(2_000, on: day(2026, 11, 10))
        let later = summary(terms(), movements + [move(-5_000, on: day(2026, 11, 5)), open], today: day(2026, 11, 20))
        XCTAssertEqual(later.spentThisCycle, Money(minor: 5_000))
        XCTAssertEqual(later.payments.map(\.amount.minor), [30_000, 5_000, 0, 0, 0, 0])
        XCTAssertEqual(later.uncategorizedCredits, [credit.id, open.id])

        // Al clasificarlo deja de avisar: como pago no toca el cargo; como devolución lo baja.
        var paid = credit
        paid.categoryId = transfer
        let asPayment = summary(terms(), [movements[0], old, paid, movements[3]], today: day(2026, 11, 20))
        XCTAssertEqual(asPayment.next?.amount, Money(minor: 30_000))
        XCTAssertEqual(asPayment.uncategorizedCredits, [])
        var refunded = credit
        refunded.categoryId = shopping
        let asRefund = summary(terms(), [movements[0], old, refunded, movements[3]], today: day(2026, 11, 20))
        XCTAssertEqual(asRefund.next?.amount, .zero)
        XCTAssertEqual(asRefund.uncategorizedCredits, [])
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

    /// ORC-78: la app sólo carga los 500 movimientos más recientes de la tarjeta, y la compra aplazada puede
    /// ser más antigua. Mismos números que `summaries` de testdata/vectors/card_installments.json.
    func testInstallmentSurvivesMoreThan500LaterMovements() {
        let purchase = move(-120_000, on: day(2025, 10, 15))
        let plan = CardInstallment(householdId: home, accountId: card, movementId: purchase.id, months: 24, rate: 14)
        let short = [purchase, move(55_835, on: day(2026, 11, 1), payment: true),
                     move(-30_000, on: day(2026, 10, 10)), move(-5_000, on: day(2026, 11, 5))]
        // 520 movimientos posteriores a la compra, en extractos ya pagados: no cambian lo que se debe.
        let filler = (0..<260).flatMap { _ in
            [move(-1_000, on: day(2026, 3, 10)), move(1_000, on: day(2026, 4, 1), payment: true)]
        }
        let today = day(2026, 11, 20)
        let expected = summary(terms(), short, installments: [plan], today: today)
        XCTAssertEqual(expected.used, Money(minor: 99_165))
        XCTAssertEqual(expected.revolvingBalance, Money(minor: 30_000))
        XCTAssertEqual(expected.payments.map(\.installments.minor), [5_762, 5_762, 5_762, 5_762, 5_762, 5_762])
        XCTAssertEqual(expected.payments.map(\.amount.minor), [35_762, 10_762, 5_762, 5_762, 5_762, 5_762])
        XCTAssertEqual(expected.payments.map(\.interest.minor), [749, 690, 631, 571, 511, 449])
        XCTAssertEqual(expected.unresolvedInstallments, [])

        let recent = Array((short + filler).sorted { $0.bookedOn > $1.bookedOn }.prefix(500))
        XCTAssertFalse(recent.contains(purchase))
        func cardSummary(_ movements: [Movement]) -> CreditCardSummary {
            CreditCardCalculator.summary(terms: terms(), balance: Money(minor: -99_165), movements: movements,
                                         installments: [plan], transferCategories: [transfer], today: today)
        }
        // Sólo con los recientes falta la compra: no se puede calcular el aplazado, y el resumen lo dice.
        let cut = cardSummary(recent)
        XCTAssertEqual(cut.unresolvedInstallments, [plan.id])
        XCTAssertEqual(cut.revolvingBalance, Money(minor: 94_165))
        XCTAssertEqual(cut.payments.map(\.installments.minor), [0, 0, 0, 0, 0, 0])
        // Con la compra pedida aparte (lo que hace la app), sale lo mismo que con el historial corto.
        let full = cardSummary(recent + [purchase])
        XCTAssertEqual(full.unresolvedInstallments, [])
        XCTAssertEqual(full.revolvingBalance, expected.revolvingBalance)
        XCTAssertEqual(full.payments, expected.payments)
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

    func testIgualdadTambienMiraLoGastadoEnElCiclo() {
        let s = summary(terms(), [move(-10_000, on: day(2026, 11, 4))], today: day(2026, 11, 4))
        var otro = s
        otro.spentThisCycle = Money(minor: s.spentThisCycle.minor + 1)
        XCTAssertNotEqual(s, otro)
        XCTAssertEqual(s, s)
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
        // Se cambian las guardadas (con su versión), como hace el formulario.
        good = try await backend.saveCreditCard(good)
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

final class CardPurchaseKindTests: XCTestCase {
    func testRecurringSeriesFromPurchaseStartsPendingNextDay() {
        let day = CalendarDay(year: 2026, month: 11, day: 16)!
        let purchase = Movement(householdId: UUID(), accountId: UUID(), categoryId: UUID(), bookedOn: day,
                                amount: Money(minor: -1299), description: "Plataforma de música")
        let series = RecurringSeries.fromPurchase(purchase)
        XCTAssertEqual(series.name, "Plataforma de música")
        XCTAssertEqual(series.kind, .subscription)
        XCTAssertEqual(series.amount.minor, 1299)
        XCTAssertEqual(series.accountId, purchase.accountId)
        XCTAssertEqual(series.categoryId, purchase.categoryId)
        XCTAssertEqual(series.recurrence, .monthly)
        XCTAssertEqual(series.startsOn, day)
        // El cargo de hoy ya es el movimiento: no sale como pendiente; el del mes que viene, sí.
        XCTAssertTrue(PendingCharges.missing(series: [series], existing: [], today: day).isEmpty)
        let next = PendingCharges.missing(series: [series], existing: [], today: day.adding(months: 1))
        XCTAssertEqual(next.map(\.dueOn), [day.adding(months: 1)])
        XCTAssertEqual(next.first?.amount.minor, -1299)
    }

    func testInstallmentLimits() {
        XCTAssertEqual(CardInstallment.allowedMonths, 2...48)
        XCTAssertNil(CardInstallment(householdId: UUID(), accountId: UUID(), movementId: UUID(), months: 24).issue)
        XCTAssertNotNil(CardInstallment(householdId: UUID(), accountId: UUID(), movementId: UUID(), months: 60).issue)
        XCTAssertEqual(CardPurchaseKind.allCases.map(\.title), ["Normal", "A plazos", "Recurrente"])
    }
}
