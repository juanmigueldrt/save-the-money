import XCTest
@testable import STMCore

/// Fase D: cargos pendientes de los pagos fijos, emparejar con lo importado, resumen semanal
/// y avisos de hábito. Datos inventados.
final class PhaseDTests: XCTestCase {
    private let home = UUID()
    private let account = UUID()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }

    private func series(_ name: String = "Plataforma de vídeo", amount: Int = 1299, starts: CalendarDay,
                        pendingFrom: CalendarDay? = nil, kind: RecurringKind = .subscription) -> RecurringSeries {
        RecurringSeries(householdId: home, name: name, kind: kind, amount: Money(minor: amount), accountId: account,
                        startsOn: starts, pendingFrom: pendingFrom)
    }

    private func movement(_ minor: Int, on date: CalendarDay, _ text: String = "CARGO",
                          accountId: UUID? = nil, category: UUID? = nil) -> Movement {
        Movement(householdId: home, accountId: accountId ?? account, categoryId: category, bookedOn: date,
                 amount: Money(minor: minor), description: text)
    }

    func testMissingChargesStartAtPendingFromAndSkipKnown() {
        let item = series(starts: day(2026, 1, 31), pendingFrom: day(2026, 10, 1))
        let today = day(2026, 12, 2)
        let missing = PendingCharges.missing(series: [item], existing: [], today: today)
        // Desde el 1 de octubre: 31 oct y 30 nov (último día de un mes de 30).
        XCTAssertEqual(missing.map(\.dueOn), [day(2026, 10, 31), day(2026, 11, 30)])
        XCTAssertEqual(missing.first?.amount.minor, -1299, "un gasto se apunta en negativo")
        let again = PendingCharges.missing(series: [item], existing: missing, today: today)
        XCTAssertTrue(again.isEmpty, "lo ya apuntado no se repite")

        var off = item
        off.createsPending = false
        XCTAssertTrue(PendingCharges.missing(series: [off], existing: [], today: today).isEmpty)
        let income = series("Nómina", amount: 150_000, starts: day(2026, 11, 28), pendingFrom: day(2026, 11, 1), kind: .income)
        XCTAssertEqual(PendingCharges.missing(series: [income], existing: [], today: today).first?.amount.minor, 150_000)
    }

    func testMissingChargesLookBackAtMostTwoMonths() {
        let item = series(starts: day(2025, 1, 5), pendingFrom: day(2025, 1, 1))
        let missing = PendingCharges.missing(series: [item], existing: [], today: day(2026, 11, 20))
        XCTAssertEqual(missing.map(\.dueOn), [day(2026, 9, 5), day(2026, 10, 5), day(2026, 11, 5)].filter {
            $0 >= day(2026, 11, 20).adding(days: -PendingCharges.lookbackDays)
        })
    }

    func testMatchesImportedMovementInsteadOfDuplicating() {
        let item = series(starts: day(2026, 11, 5), pendingFrom: day(2026, 11, 1))
        let charge = RecurringCharge(householdId: home, seriesId: item.id, dueOn: day(2026, 11, 5), amount: Money(minor: -1299))
        let exact = movement(-1299, on: day(2026, 11, 7), "COMPRA")
        let farAway = movement(-1299, on: day(2026, 11, 20))
        let otherAccount = movement(-1299, on: day(2026, 11, 5), accountId: UUID())
        let found = PendingCharges.matches(charges: [charge], series: [item], movements: [farAway, otherAccount, exact])
        XCTAssertEqual(found.map(\.movement), [exact.id])

        // Importe distinto (subida de precio) pero con el nombre en el concepto.
        let raised = movement(-1399, on: day(2026, 11, 5), "PLATAFORMA VIDEO SL")
        XCTAssertEqual(PendingCharges.matches(charges: [charge], series: [item], movements: [raised]).map(\.movement), [raised.id])
        let unrelated = movement(-1399, on: day(2026, 11, 5), "SUPERMERCADO")
        XCTAssertTrue(PendingCharges.matches(charges: [charge], series: [item], movements: [unrelated]).isEmpty)

        // Un movimiento que ya confirma otro cargo no se vuelve a usar.
        var linked = charge
        linked.status = .confirmed
        linked.transactionId = exact.id
        let next = RecurringCharge(householdId: home, seriesId: item.id, dueOn: day(2026, 11, 6), amount: Money(minor: -1299))
        XCTAssertTrue(PendingCharges.matches(charges: [linked, next], series: [item], movements: [exact]).isEmpty)
    }

    func testConfirmSkipAndPendingListInMemory() async throws {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        let household = try await backend.createHousehold(name: "Casa")
        let checking = try await backend.createAccount(AccountDraft(name: "Cuenta"), in: household.id)
        let item = try await backend.createRecurring(RecurringSeries(householdId: household.id, name: "Gimnasio",
                                                                    amount: Money(minor: 3000), accountId: checking.id,
                                                                    startsOn: day(2026, 10, 1), pendingFrom: day(2026, 10, 1)))
        let missing = PendingCharges.missing(series: [item], existing: [], today: day(2026, 11, 15))
        let created = try await backend.createCharges(missing + missing)
        XCTAssertEqual(created.count, 2, "los repetidos se ignoran")
        let balanceBefore = try await backend.balances(in: household.id)[checking.id]
        XCTAssertEqual(balanceBefore?.minor, 0, "un pendiente no toca el saldo")

        let movement = try await backend.confirmCharge(created[0].id, with: MovementDraft(
            accountId: checking.id, bookedOn: created[0].dueOn, amount: Money(minor: -3200), description: "Gimnasio"))
        _ = try await backend.updateCharge(created[1], status: .skipped, transactionId: nil)
        let charges = try await backend.recurringCharges(in: household.id)
        XCTAssertEqual(charges.first { $0.id == created[0].id }?.transactionId, movement.id)
        XCTAssertEqual(charges.first { $0.id == created[0].id }?.amount.minor, -3200)
        XCTAssertTrue(PendingCharges.pending(charges: charges, series: [item]).isEmpty)
        let balanceAfter = try await backend.balances(in: household.id)[checking.id]
        XCTAssertEqual(balanceAfter?.minor, -3200)

        do {
            _ = try await backend.confirmCharge(created[0].id, with: MovementDraft(
                accountId: checking.id, bookedOn: created[0].dueOn, amount: Money(minor: -3200), description: "Otra vez"))
            XCTFail("no se confirma dos veces")
        } catch {}
    }

    func testWeeklySummary() {
        let food = BudgetCategory(householdId: home, name: "Comida", kind: .expense, budgetGroup: .needs)
        let salary = BudgetCategory(householdId: home, name: "Nómina", kind: .income)
        let transfer = BudgetCategory(householdId: home, name: "Traspaso", kind: .transfer)
        // Hoy es miércoles 18 nov 2026: la semana del resumen es la del 9 al 15.
        let today = day(2026, 11, 18)
        XCTAssertEqual(today.weekdayIndex, 2)
        XCTAssertEqual(today.startOfWeek, day(2026, 11, 16))
        let movements = [
            movement(-5000, on: day(2026, 11, 10), "SUPER", category: food.id),
            movement(-2000, on: day(2026, 11, 15), "CENA", category: food.id),
            movement(-9000, on: day(2026, 11, 12), "LIBRERIA"),
            movement(-100_000, on: day(2026, 11, 11), "A AHORRO", category: transfer.id),
            movement(200_000, on: day(2026, 11, 13), "NOMINA", category: salary.id),
            movement(-8000, on: day(2026, 11, 4), "SEMANA ANTERIOR", category: food.id),
            movement(-3000, on: day(2026, 11, 17), "ESTA SEMANA", category: food.id),
        ]
        let summary = WeeklySummary(movements: movements, categories: [food, salary, transfer], today: today, heatmapWeeks: 2)
        XCTAssertEqual(summary.week.start, day(2026, 11, 9))
        XCTAssertEqual(summary.week.spent.minor, 16_000, "sin traspasos ni la semana en curso")
        XCTAssertEqual(summary.week.income.minor, 200_000)
        XCTAssertEqual(summary.previous.spent.minor, 8_000)
        XCTAssertEqual(summary.change.percent, 100)
        XCTAssertEqual(summary.biggest.map(\.description), ["LIBRERIA", "SUPER", "CENA"])
        XCTAssertEqual(summary.topCategories.first?.title, "Sin categoría")
        XCTAssertEqual(summary.heatmap.count, 2)
        XCTAssertEqual(summary.heatmap[1][3].day, day(2026, 11, 12))
        XCTAssertEqual(summary.heatmap[1][3].intensity, 1)
        XCTAssertEqual(summary.title, "9 nov – 15 nov")
        XCTAssertTrue(summary.notificationBody.hasPrefix("Gastaste"))
    }

    func testHabitReminders() {
        let today = day(2026, 11, 18)
        XCTAssertEqual(HabitReminderPlanner.logReminders(today: today, hour: 21, weekly: false, days: 3).count, 3)
        let sundays = HabitReminderPlanner.logReminders(today: today, hour: 21, weekly: true, days: 14)
        XCTAssertEqual(sundays.map(\.fireOn), [day(2026, 11, 22), day(2026, 11, 29)])
        let weekly = HabitReminderPlanner.weeklySummary(today: today, weeks: 2)
        XCTAssertEqual(weekly.map(\.fireOn), [day(2026, 11, 23), day(2026, 11, 30)])
        XCTAssertTrue(weekly.allSatisfy { $0.id.hasPrefix(HabitReminderPlanner.prefix) })
    }

    func testSeriesCodingKeepsPendingFields() throws {
        let item = series(starts: day(2026, 11, 5), pendingFrom: day(2026, 11, 1))
        let data = try JSONEncoder().encode(item)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["creates_pending"] as? Bool, true)
        XCTAssertNotNil(json["pending_from"])
    }
}
