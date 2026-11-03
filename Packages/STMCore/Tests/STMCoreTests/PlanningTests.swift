import XCTest
@testable import STMCore

/// Pagos recurrentes, metas y avisos. Datos inventados.
final class PlanningTests: XCTestCase {
    let home = UUID()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }

    func testDayArithmetic() {
        XCTAssertEqual(day(1970, 1, 1).ordinal, 0)
        XCTAssertEqual(CalendarDay(ordinal: day(2026, 11, 2).ordinal), day(2026, 11, 2))
        XCTAssertEqual(day(2026, 12, 30).adding(days: 3), day(2027, 1, 2))
        XCTAssertEqual(day(2028, 2, 28).adding(days: 1), day(2028, 2, 29))
        XCTAssertEqual(day(2026, 1, 31).adding(months: 1), day(2026, 2, 28))
        XCTAssertEqual(day(2026, 11, 1).days(until: day(2026, 12, 1)), 30)
        XCTAssertEqual(day(2026, 11, 5).longTitle, "5 de noviembre")
    }

    func testMonthlySeriesKeepsDayAfterShortMonths() {
        let rent = RecurringSeries(householdId: home, name: "Alquiler", kind: .essential, amount: Money(minor: 80_000),
                                   startsOn: day(2027, 1, 31))
        XCTAssertEqual(rent.occurrences(from: day(2027, 1, 1), through: day(2027, 4, 30)),
                       [day(2027, 1, 31), day(2027, 2, 28), day(2027, 3, 31), day(2027, 4, 30)])
        XCTAssertEqual(rent.nextDue(onOrAfter: day(2027, 3, 1)), day(2027, 3, 31))
        XCTAssertEqual(rent.signedAmount, Money(minor: -80_000))
    }

    func testOtherFrequenciesAndEndDate() {
        let gym = RecurringSeries(householdId: home, name: "Gimnasio", amount: Money(minor: 1_000),
                                  recurrence: Recurrence(every: 2, unit: .week), startsOn: day(2026, 11, 2),
                                  endsOn: day(2026, 12, 1))
        XCTAssertEqual(gym.occurrences(from: day(2026, 11, 1), through: day(2026, 12, 31)),
                       [day(2026, 11, 2), day(2026, 11, 16), day(2026, 11, 30)])
        XCTAssertNil(gym.nextDue(onOrAfter: day(2026, 12, 2)))
        XCTAssertEqual(gym.monthlyAmount, Money(minor: 2_167)) // 26 al año / 12

        let insurance = RecurringSeries(householdId: home, name: "Seguro", kind: .essential, amount: Money(minor: 24_000),
                                        recurrence: Recurrence(every: 1, unit: .year), startsOn: day(2024, 3, 15))
        XCTAssertEqual(insurance.nextDue(onOrAfter: day(2026, 11, 2)), day(2027, 3, 15))
        XCTAssertEqual(insurance.monthlyAmount, Money(minor: 2_000))
        XCTAssertEqual(Recurrence(every: 3, unit: .month).title, "Cada trimestre")
    }

    func testSeriesValidation() {
        var series = RecurringSeries(householdId: home, name: "  ", amount: Money(minor: 100), startsOn: day(2026, 11, 1))
        XCTAssertEqual(series.issue, "Ponle un nombre.")
        series.name = "Música"
        series.amount = .zero
        XCTAssertNotNil(series.issue)
        series.amount = Money(minor: 999)
        series.endsOn = day(2026, 10, 1)
        XCTAssertEqual(series.issue, "No puede terminar antes de empezar.")
        series.endsOn = nil
        XCTAssertNil(series.issue)
    }

    func testUpcomingAndMonthlyTotals() {
        let today = day(2026, 11, 2)
        let list = [
            RecurringSeries(householdId: home, name: "Música", amount: Money(minor: 999), startsOn: day(2026, 1, 10)),
            RecurringSeries(householdId: home, name: "Luz", kind: .essential, amount: Money(minor: 6_000), startsOn: day(2026, 1, 3)),
            RecurringSeries(householdId: home, name: "Nómina", kind: .income, amount: Money(minor: 200_000), startsOn: day(2026, 1, 28)),
            RecurringSeries(householdId: home, name: "Vieja", amount: Money(minor: 500), startsOn: day(2026, 1, 5),
                            archivedAt: Date()),
        ]
        XCTAssertEqual(list.upcoming(from: today, days: 30).map(\.series.name), ["Luz", "Música", "Nómina"])
        XCTAssertEqual(list.monthlyTotal(of: .subscription, on: today), Money(minor: 999))
        XCTAssertEqual(list.monthlyTotal(of: .income, on: today), Money(minor: 200_000))
    }

    func testReminderPlan() {
        let today = day(2026, 11, 2)
        let music = RecurringSeries(householdId: home, name: "Música", amount: Money(minor: 999), startsOn: day(2026, 1, 3),
                                    remindDaysBefore: 1)
        let silent = RecurringSeries(householdId: home, name: "Sin aviso", amount: Money(minor: 100), startsOn: day(2026, 1, 3),
                                     remindDaysBefore: nil)
        let plan = ReminderPlanner.plan([music, silent], today: today, horizonDays: 45)
        XCTAssertEqual(plan.map(\.fireOn), [day(2026, 11, 2), day(2026, 12, 2)])
        XCTAssertEqual(plan.first?.title, "Mañana: Música")
        XCTAssertEqual(plan.first?.body, "Se cobran \(Money(minor: 999).formatted()) el 3 de noviembre.")
        XCTAssertTrue(plan.allSatisfy { $0.id.hasPrefix(ReminderPlanner.prefix) })
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
        XCTAssertEqual(ReminderPlanner.plan([music], today: today, horizonDays: 400, limit: 5).count, 5)
    }

    func testGoalProgressWithPlan() {
        let goal = Goal(householdId: home, name: "Fondo de emergencia", target: Money(minor: 300_000),
                        starting: Money(minor: 50_000), monthlyPlan: Money(minor: 25_000), targetOn: day(2027, 5, 1))
        let contributions = [
            GoalContribution(householdId: home, goalId: goal.id, amount: Money(minor: 25_000), madeOn: day(2026, 10, 1)),
            GoalContribution(householdId: home, goalId: goal.id, amount: Money(minor: -5_000), madeOn: day(2026, 10, 20)),
            GoalContribution(householdId: home, goalId: UUID(), amount: Money(minor: 99_999), madeOn: day(2026, 10, 1)),
        ]
        let progress = GoalProgress(goal: goal, contributions: contributions, today: day(2026, 11, 2))
        XCTAssertEqual(progress.saved, Money(minor: 70_000))
        XCTAssertEqual(progress.remaining, Money(minor: 230_000))
        XCTAssertEqual(progress.monthsLeft, 10) // 230.000 / 25.000 = 9,2 -> 10
        XCTAssertEqual(progress.projectedMonth, MonthKey(year: 2027, month: 9))
        XCTAssertEqual(progress.neededMonthly, Money(minor: 38_334)) // 230.000 en 6 meses
        XCTAssertEqual(progress.isOnTrack, false)
        XCTAssertEqual(progress.fraction, 70_000.0 / 300_000.0, accuracy: 0.0001)
    }

    func testGoalPaceFromHistoryAndReached() {
        let debt = Goal(householdId: home, name: "Tarjeta", kind: .debt, target: Money(minor: 120_000))
        let paid = (8...10).map { month in
            GoalContribution(householdId: home, goalId: debt.id, amount: Money(minor: 20_000), madeOn: day(2026, month, 5))
        }
        let progress = GoalProgress(goal: debt, contributions: paid, today: day(2026, 11, 2))
        XCTAssertEqual(progress.monthlyPace, Money(minor: 20_000))
        XCTAssertEqual(progress.monthsLeft, 3)
        XCTAssertNil(progress.isOnTrack)

        let none = GoalProgress(goal: debt, contributions: [], today: day(2026, 11, 2))
        XCTAssertNil(none.monthlyPace)
        XCTAssertNil(none.projectedMonth)

        let done = GoalProgress(goal: debt, contributions: [
            GoalContribution(householdId: home, goalId: debt.id, amount: Money(minor: 130_000), madeOn: day(2026, 11, 1)),
        ], today: day(2026, 11, 2))
        XCTAssertTrue(done.isReached)
        XCTAssertEqual(done.remaining, .zero)
        XCTAssertEqual(done.fraction, 1)
    }

    func testCodingUsesServerColumns() throws {
        let json = """
        {"id":"7B0B4C53-5A1E-4D5B-9C1E-6B1E1A0F0001","household_id":"7B0B4C53-5A1E-4D5B-9C1E-6B1E1A0F0002",
         "name":"Música","kind":"subscription","amount_minor":999,"account_id":null,"category_id":null,
         "every":1,"unit":"month","starts_on":"2026-11-05","ends_on":null,"remind_days_before":2,"archived_at":null}
        """
        let series = try JSONDecoder().decode(RecurringSeries.self, from: Data(json.utf8))
        XCTAssertEqual(series.amount, Money(minor: 999))
        XCTAssertEqual(series.startsOn, day(2026, 11, 5))
        XCTAssertEqual(series.remindDaysBefore, 2)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(series)) as! [String: Any]
        XCTAssertEqual(encoded["amount_minor"] as? Int, 999)
        XCTAssertNil(encoded["id"])
        XCTAssertNil(encoded["household_id"])
    }

    func testInMemoryKeepsHouseholdsApart() async throws {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        let house = try await backend.createHousehold(name: "Casa")
        let goal = try await backend.createGoal(Goal(householdId: house.id, name: " Viaje ", target: Money(minor: 100_000)))
        XCTAssertEqual(goal.name, "Viaje")
        _ = try await backend.addContribution(GoalContribution(householdId: house.id, goalId: goal.id,
                                                               amount: Money(minor: 10_000), madeOn: day(2026, 11, 1)))
        _ = try await backend.createRecurring(RecurringSeries(householdId: house.id, name: "Música",
                                                              amount: Money(minor: 999), startsOn: day(2026, 11, 5)))
        try await backend.signOut()

        _ = try await backend.signUp(username: Username("carla"), password: "contrasena-de-prueba", displayName: nil)
        let other = try await backend.createHousehold(name: "Otro")
        do {
            _ = try await backend.goals(in: house.id)
            XCTFail("Carla no debe ver metas ajenas")
        } catch {}
        do {
            _ = try await backend.addContribution(GoalContribution(householdId: other.id, goalId: goal.id,
                                                                   amount: Money(minor: 1), madeOn: day(2026, 11, 1)))
            XCTFail("no se aporta a una meta de otro hogar")
        } catch {}
        let mine = try await backend.recurringSeries(in: other.id)
        XCTAssertTrue(mine.isEmpty)
    }

    func testIntroPrice() throws {
        // 3 meses a 6,99 € y luego 11,99 €. Datos inventados.
        var video = RecurringSeries(householdId: UUID(), name: "Plataforma de vídeo", amount: Money(minor: 1199),
                                    startsOn: day(2026, 11, 5), introAmount: Money(minor: 699), introCharges: 3)
        XCTAssertNil(video.issue)
        XCTAssertEqual(video.amount(on: day(2026, 11, 5)), Money(minor: 699))
        XCTAssertEqual(video.amount(on: day(2027, 1, 5)), Money(minor: 699))
        XCTAssertEqual(video.amount(on: day(2027, 2, 5)), Money(minor: 1199))
        XCTAssertEqual(video.introEndsOn, day(2027, 1, 5))
        XCTAssertEqual(video.monthlyAmount(on: day(2026, 12, 1)), Money(minor: 699))
        XCTAssertEqual(video.monthlyAmount(on: day(2027, 1, 6)), Money(minor: 1199))
        XCTAssertEqual([video].monthlyTotal(of: .subscription, on: day(2027, 1, 6)), Money(minor: 1199))

        let charges = [video].upcoming(from: day(2026, 12, 20), days: 60)
        XCTAssertEqual(charges.map(\.amount), [Money(minor: 699), Money(minor: 1199)])
        XCTAssertEqual(charges.map(\.isIntro), [true, false])
        XCTAssertEqual(charges.first?.signedAmount, Money(minor: -699))

        let bills = MonthlyBills(series: [video], month: MonthKey(year: 2027, month: 2))
        XCTAssertEqual(bills.total, Money(minor: 1199))

        let reminders = ReminderPlanner.plan([video], today: day(2027, 1, 1))
        XCTAssertTrue(reminders.first?.body.contains("último cargo con precio de oferta") ?? false)

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(video)) as! [String: Any]
        XCTAssertEqual(encoded["intro_amount_minor"] as? Int, 699)
        XCTAssertEqual(encoded["intro_charges"] as? Int, 3)

        video.introCharges = nil
        XCTAssertNotNil(video.issue, "precio de oferta sin duración")
        video.introCharges = 40
        XCTAssertNotNil(video.issue)
    }
}
