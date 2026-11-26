import XCTest
@testable import STMCore

/// iOS guarda como mucho 64 avisos pendientes por app: entre todos los planificadores no deben pasar de ahí.
final class ReminderLimitTests: XCTestCase {
    let home = UUID()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }

    func testTodosLosAvisosJuntosNoPasanDe64() {
        let today = day(2026, 11, 2)

        // 60 pagos semanales con aviso: muchos más de los que caben.
        let series = (0..<60).map { _ in
            RecurringSeries(householdId: home, name: "Pago de prueba", amount: Money(minor: 1_000),
                            recurrence: Recurrence(every: 1, unit: .week), startsOn: today, remindDaysBefore: 1)
        }
        let recurring = ReminderPlanner.plan(series, today: today)

        let holding = Holding(householdId: home, name: "Fondo de prueba", price: 10)
        let plans = (0..<20).map { _ in
            InvestmentPlan(householdId: home, holdingId: holding.id, amount: Money(minor: 5_000),
                           recurrence: Recurrence(every: 1, unit: .week), startsOn: today)
        }
        let investments = ReminderPlanner.plan(plans, holdings: [holding], today: today)

        let card = UUID()
        let terms = CreditCardTerms(accountId: card, householdId: home, creditLimit: Money(minor: 300_000))
        let purchase = Movement(householdId: home, accountId: card, bookedOn: day(2026, 10, 10),
                                amount: Money(minor: -50_000), description: "Compra de prueba")
        let base = CreditCardCalculator.summary(terms: terms, balance: purchase.amount, movements: [purchase],
                                                installments: [], transferCategories: [], today: today)
        let cards = (0..<20).map { _ in
            var summary = base
            summary.terms.accountId = UUID()
            return (summary: summary, name: "Tarjeta de prueba", payFromBalance: Money?.none)
        }
        let cardReminders = ReminderPlanner.plan(cards: cards, today: today)

        // Recordatorio diario para apuntar gastos y resumen de los lunes: el máximo de los hábitos.
        let habits = HabitReminderPlanner.logReminders(today: today, hour: 21, weekly: false)
            + HabitReminderPlanner.weeklySummary(today: today)

        XCTAssertEqual(investments.count, 10)
        XCTAssertEqual(cardReminders.count, 10)
        XCTAssertEqual(habits.count, 24)
        XCTAssertEqual(recurring.count, 20, "los pagos fijos se quedan con lo que dejan libre los demás")
        XCTAssertLessThanOrEqual(recurring.count + investments.count + cardReminders.count + habits.count, 64)
    }
}
