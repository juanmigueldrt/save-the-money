import XCTest
@testable import STMCore

/// ORC-104: cada modelo se codifica con todas las columnas que lee, así se puede guardar y volver a leer igual
/// (caché local, cola sin conexión). Cada uno con todos los opcionales puestos y con todos a nil. Datos inventados.
final class CodableSimetricoTests: XCTestCase {
    private let home = UUID(), account = UUID(), other = UUID()
    private let seen = "2026-11-01T10:00:00.123456+00:00"

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d)! }

    /// Una fecha como las que llegan del servidor, con milisegundos.
    private func date(_ text: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try XCTUnwrap(formatter.date(from: text))
    }

    private func dec(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    private func assertRoundTrip<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let again = try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(again, value, file: file, line: line)
    }

    func testCuentasCategoriasYMovimientos() throws {
        try assertRoundTrip(Account(householdId: home, name: " Corriente ", kind: .savings, currency: "USD",
                                    openingBalance: Money(minor: -1_250, currency: "USD"), ownerId: other,
                                    archivedAt: date("2026-10-28T10:00:00.123+00:00"), isDefault: true,
                                    includeInNetWorth: false, createdAt: date("2026-01-02T03:04:05.678+00:00"),
                                    updatedAt: seen))
        try assertRoundTrip(Account(householdId: home, name: "Corriente"))
        try assertRoundTrip(BudgetCategory(householdId: home, name: "Ocio", budgetGroup: .wants, icon: "gamecontroller",
                                           updatedAt: seen))
        try assertRoundTrip(BudgetCategory(householdId: home, name: "Ocio"))
        try assertRoundTrip(Movement(householdId: home, accountId: account, categoryId: other, bookedOn: day(2026, 10, 3),
                                     amount: Money(minor: -4_520), description: " Compra ", notes: "nota",
                                     importHash: "abc", excluded: true, reviewedAt: date("2026-10-04T08:00:00.001+00:00"),
                                     payee: "Tienda", tags: ["casa", "mes"], updatedAt: seen, transferId: UUID()))
        try assertRoundTrip(Movement(householdId: home, accountId: account, bookedOn: day(2026, 10, 3),
                                     amount: Money(minor: 100), description: "Compra"))
    }

    func testPresupuestosExtraYTarjetas() throws {
        try assertRoundTrip(ExtraBudget(householdId: home, name: " Viaje ", limit: Money(minor: 50_000),
                                        startsOn: day(2026, 12, 1), endsOn: day(2026, 12, 15), categoryIds: [other],
                                        accountIds: [account], isFavorite: true, updatedAt: seen))
        try assertRoundTrip(ExtraBudget(householdId: home, name: "Viaje", limit: Money(minor: 50_000), startsOn: day(2026, 12, 1)))
        try assertRoundTrip(CreditCardTerms(accountId: account, householdId: home, creditLimit: Money(minor: 300_000),
                                            statementDay: 25, paymentDay: 5, paymentDelayMonths: 2, paymentMode: .fixed,
                                            fixedPayment: Money(minor: 12_345), minPaymentPercent: dec("3.5"),
                                            minPayment: Money(minor: 2_000), revolvingRate: dec("21.12345678"),
                                            installmentRate: dec("0.1"), payFromAccountId: other, remindDaysBefore: 3,
                                            alertPercent: 75, updatedAt: seen))
        try assertRoundTrip(CreditCardTerms(accountId: account, householdId: home, creditLimit: Money(minor: 300_000),
                                            remindDaysBefore: nil, alertPercent: nil))
        try assertRoundTrip(CardInstallment(householdId: home, accountId: account, movementId: other, months: 6,
                                            rate: dec("13.75"), updatedAt: seen))
        try assertRoundTrip(CardInstallment(householdId: home, accountId: account, movementId: other, months: 6))
    }

    func testMetasYAportaciones() throws {
        try assertRoundTrip(Goal(householdId: home, name: " Viaje ", kind: .debt, target: Money(minor: 100_000),
                                 starting: Money(minor: 5_000), monthlyPlan: Money(minor: 10_000), targetOn: day(2027, 6, 1),
                                 accountId: account, icon: "airplane", completedAt: date("2026-11-02T10:00:00.500+00:00"),
                                 archivedAt: date("2026-11-03T10:00:00.000+00:00"), updatedAt: seen))
        try assertRoundTrip(Goal(householdId: home, name: "Viaje", target: Money(minor: 100_000)))
        try assertRoundTrip(GoalContribution(householdId: home, goalId: other, amount: Money(minor: -500),
                                             madeOn: day(2026, 11, 1), note: "retirada"))
        try assertRoundTrip(GoalContribution(householdId: home, goalId: other, amount: Money(minor: 500), madeOn: day(2026, 11, 1)))
    }

    func testInversiones() throws {
        try assertRoundTrip(Holding(householdId: home, name: " Fondo ", symbol: " VWCE ", kind: .etf, assetClass: .fixedIncome,
                                    currency: "USD", accountId: account, ownerId: other, price: dec("101.12345678"),
                                    priceOn: day(2026, 11, 1), feeRate: dec("0.15"), note: "nota",
                                    archivedAt: date("2026-11-02T10:00:00.250+00:00"), updatedAt: seen))
        try assertRoundTrip(Holding(householdId: home, name: "Fondo"))
        try assertRoundTrip(HoldingPrice(householdId: home, holdingId: other, pricedOn: day(2026, 11, 1), price: dec("0.00000001")))
        try assertRoundTrip(InvestmentTrade(householdId: home, holdingId: other, tradedOn: day(2026, 11, 2), side: .sell,
                                            quantity: dec("0.12345678"), price: dec("99.123456"), fee: Money(minor: 25),
                                            note: "venta"))
        try assertRoundTrip(InvestmentTrade(householdId: home, holdingId: other, tradedOn: day(2026, 11, 2), quantity: 1, price: 10))
        try assertRoundTrip(InvestmentPlan(householdId: home, holdingId: other, accountId: account, amount: Money(minor: 15_000),
                                           recurrence: Recurrence(every: 2, unit: .week), startsOn: day(2026, 11, 5),
                                           endsOn: day(2027, 11, 5), expectedAnnualReturn: dec("6.5"), remindDaysBefore: 3,
                                           pausedAt: date("2026-11-02T10:00:00.001+00:00"),
                                           archivedAt: date("2026-11-03T10:00:00.999+00:00"), updatedAt: seen))
        try assertRoundTrip(InvestmentPlan(householdId: home, holdingId: other, amount: Money(minor: 15_000),
                                           startsOn: day(2026, 11, 5), remindDaysBefore: nil))
    }

    func testPagosFijosCargosYScore() throws {
        try assertRoundTrip(RecurringSeries(householdId: home, name: " Música ", kind: .essential, amount: Money(minor: 1_199),
                                            accountId: account, categoryId: other, recurrence: Recurrence(every: 3, unit: .month),
                                            startsOn: day(2026, 11, 5), endsOn: day(2027, 11, 5), remindDaysBefore: 2,
                                            archivedAt: date("2026-11-04T10:00:00.010+00:00"), introAmount: Money(minor: 699),
                                            introCharges: 3, createsPending: false, pendingFrom: day(2026, 11, 1),
                                            updatedAt: seen))
        try assertRoundTrip(RecurringSeries(householdId: home, name: "Música", amount: Money(minor: 1_199),
                                            startsOn: day(2026, 11, 5), remindDaysBefore: nil))
        try assertRoundTrip(RecurringCharge(householdId: home, seriesId: other, dueOn: day(2026, 11, 5),
                                            amount: Money(minor: -1_199), status: .confirmed, transactionId: account,
                                            updatedAt: seen))
        try assertRoundTrip(RecurringCharge(householdId: home, seriesId: other, dueOn: day(2026, 11, 5), amount: Money(minor: -1_199)))
        try assertRoundTrip(CreditScore(score: 720, maxScore: 850, provider: " Buró ", recordedOn: day(2026, 11, 1), note: "  "))
        try assertRoundTrip(CreditScore(score: 720, recordedOn: day(2026, 11, 1)))
    }

    func testHogar() throws {
        try assertRoundTrip(Household(name: "Casa", baseCurrency: "USD", monthStartDay: 25))
        try assertRoundTrip(Profile(username: "ana", displayName: "Ana", theme: .dark, defaultHouseholdId: home))
        try assertRoundTrip(Profile(username: "ana"))
        try assertRoundTrip(Membership(householdId: home, userId: other, role: .member))
        try assertRoundTrip(HouseholdInvite(householdId: home, code: "ABCD-EFGH", status: .revoked,
                                            expiresAt: date("2026-11-08T10:00:00.000+00:00")))
    }

    /// Una fila tal como llega del servidor (microsegundos, numéricos como número o texto) vuelve igual tras guardarla.
    func testUnaFilaDelServidorVuelveIgual() throws {
        let json = """
        {"id":"7B0B4C53-5A1E-4D5B-9C1E-6B1E1A0F0011","household_id":"7B0B4C53-5A1E-4D5B-9C1E-6B1E1A0F0012",
         "name":"Fondo de prueba","symbol":null,"kind":"etf","asset_class":"fixed_income","currency":"EUR",
         "account_id":null,"owner_id":null,"price":101.123456,"price_on":"2026-11-01","fee_rate":"0.150",
         "note":null,"archived_at":"2026-10-28T10:00:00.123456+00:00","updated_at":"\(seen)"}
        """
        let holding = try JSONDecoder().decode(Holding.self, from: Data(json.utf8))
        try assertRoundTrip(holding)
        XCTAssertEqual(holding.updatedAt, seen)
    }
}
