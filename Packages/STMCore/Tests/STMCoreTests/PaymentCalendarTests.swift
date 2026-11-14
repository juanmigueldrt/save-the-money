import XCTest
@testable import STMCore

/// Datos inventados.
final class PaymentCalendarTests: XCTestCase {
    let household = UUID()
    let bank = UUID()
    let card = UUID()

    func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }

    func testWeekdayAndGrid() {
        XCTAssertEqual(day(2026, 11, 14).weekdayFromMonday, 5) // sábado
        XCTAssertEqual(day(2026, 11, 16).weekdayFromMonday, 0) // lunes
        XCTAssertEqual(day(1970, 1, 1).weekdayFromMonday, 3)   // jueves
        XCTAssertEqual(day(2026, 11, 14).weekdayTitle, "Sábado, 14 de noviembre")

        let weeks = PaymentCalendar().month(MonthKey(year: 2026, month: 11)).weeks
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(weeks.first?.prefix(6).compactMap { $0 }.count, 0) // el 1 de noviembre de 2026 es domingo
        XCTAssertEqual(weeks.first?[6], day(2026, 11, 1))
        XCTAssertEqual(weeks.flatMap { $0 }.compactMap { $0 }.count, 30)
    }

    func testJoinsSeriesCardsAndPlans() {
        let rent = RecurringSeries(householdId: household, name: "Alquiler", kind: .essential,
                                   amount: Money(minor: 80_000), startsOn: day(2026, 1, 5))
        let salary = RecurringSeries(householdId: household, name: "Nómina", kind: .income,
                                     amount: Money(minor: 200_000), startsOn: day(2026, 1, 28))
        let gym = RecurringSeries(householdId: household, name: "Gimnasio", kind: .subscription,
                                  amount: Money(minor: 3_000), recurrence: Recurrence(every: 1, unit: .week),
                                  startsOn: day(2026, 11, 2))
        let old = RecurringSeries(householdId: household, name: "Antigua", amount: Money(minor: 999),
                                  startsOn: day(2026, 1, 1), archivedAt: Date())
        let payment = CardPayment(due: day(2026, 12, 1), statement: day(2026, 11, 1), amount: Money(minor: 45_000),
                                  purchases: Money(minor: 45_000), installments: .zero, interest: .zero, isEstimate: true)
        let plan = InvestmentPlan(householdId: household, holdingId: UUID(), amount: Money(minor: 10_000),
                                  startsOn: day(2026, 3, 10))
        let calendar = PaymentCalendar(series: [rent, salary, gym, old],
                                       cardPayments: [(name: "Visa", accountId: card, payment: payment)],
                                       plans: [(name: "Fondo indexado", plan: plan)])

        let november = calendar.month(MonthKey(year: 2026, month: 11))
        XCTAssertEqual(november.payments(on: day(2026, 11, 5)).map(\.title), ["Alquiler"])
        XCTAssertEqual(november.payments(on: day(2026, 11, 5)).first?.amount, Money(minor: -80_000))
        XCTAssertEqual(november.payments(on: day(2026, 11, 28)).first?.source, .income)
        XCTAssertEqual(november.payments(on: day(2026, 11, 10)).first?.source, .investment)
        XCTAssertEqual(november.payments.filter { $0.title == "Gimnasio" }.count, 5) // 2, 9, 16, 23 y 30
        XCTAssertFalse(november.payments.contains { $0.title == "Antigua" })
        XCTAssertEqual(november.totalOut, Money(minor: 80_000 + 5 * 3_000 + 10_000))
        XCTAssertEqual(november.totalIn, Money(minor: 200_000))

        let december = calendar.month(MonthKey(year: 2026, month: 12))
        let cardDay = december.payments(on: day(2026, 12, 1))
        XCTAssertEqual(cardDay.first?.source, .creditCard)
        XCTAssertEqual(cardDay.first?.amount, Money(minor: -45_000))
        XCTAssertEqual(cardDay.first?.isEstimate, true)

        let next = calendar.next(after: day(2026, 11, 28), limit: 3)
        XCTAssertEqual(next.map(\.day), [day(2026, 11, 30), day(2026, 12, 1), day(2026, 12, 5)])
        XCTAssertEqual(next.map(\.source), [.subscription, .creditCard, .essential])
    }

    func testPausedPlansDoNotShow() {
        var plan = InvestmentPlan(householdId: household, holdingId: UUID(), amount: Money(minor: 5_000),
                                  startsOn: day(2026, 1, 1))
        plan.pausedAt = Date()
        let calendar = PaymentCalendar(plans: [(name: "Fondo", plan: plan)])
        XCTAssertTrue(calendar.month(MonthKey(year: 2026, month: 11)).payments.isEmpty)
    }

    func testImportMarks() {
        func row(_ line: Int, _ d: CalendarDay, _ minor: Int, _ text: String) -> CSVImportRow {
            CSVImportRow(line: line, draft: MovementDraft(accountId: bank, bookedOn: d, amount: Money(minor: minor),
                                                          description: text, importHash: "h\(line)"), issue: nil)
        }
        let rows = [
            row(2, day(2026, 10, 3), -1_299, "STREAMING EJEMPLO"),
            row(3, day(2026, 10, 5), -6_000, "Luz  Eléctrica Ficticia"),
            row(4, day(2026, 10, 7), -4_520, "SUPERMERCADO EJEMPLO"),
            row(5, day(2026, 10, 28), 200_000, "NOMINA EMPRESA FICTICIA"),
            row(6, day(2026, 11, 3), -1_299, "streaming ejemplo"),
            row(7, day(2026, 10, 9), -900, "CAFETERIA"),
            CSVImportRow(line: 8, draft: nil, issue: "Importe vacío o no válido"),
        ]
        let existing = [RecurringSeries(householdId: household, name: "Cafetería", amount: Money(minor: 900),
                                        startsOn: day(2026, 1, 1))]
        let marks: [Int: CSVRowMark] = [
            2: .subscription, 3: .essential, 4: .creditCard(accountId: card),
            5: .essential, // un ingreso no se marca
            6: .subscription, // mismo concepto que la fila 2: no se repite
            7: .essential,   // ya hay una serie con ese nombre
        ]
        let plan = CSVImportPlan.make(rows: rows, marks: marks, householdId: household, existing: existing)

        XCTAssertEqual(plan.drafts.count, 6)
        XCTAssertEqual(plan.drafts.first { $0.importHash == "h4" }?.accountId, card)
        XCTAssertEqual(plan.drafts.filter { $0.accountId == bank }.count, 5)
        XCTAssertEqual(plan.newSeries.map(\.name), ["STREAMING EJEMPLO", "Luz Eléctrica Ficticia"])
        let streaming = plan.newSeries[0]
        XCTAssertEqual(streaming.kind, .subscription)
        XCTAssertEqual(streaming.amount, Money(minor: 1_299))
        XCTAssertEqual(streaming.startsOn, day(2026, 10, 3))
        XCTAssertEqual(streaming.recurrence, .monthly)
        XCTAssertEqual(streaming.accountId, bank)
        XCTAssertEqual(streaming.remindDaysBefore, 1)
        XCTAssertNil(streaming.issue)
        XCTAssertEqual(plan.newSeries[1].kind, .essential)
    }
}
