import XCTest
@testable import STMCore

/// Vectores de `testdata/vectors/`, compartidos con Android (SharedVectorsTest.kt).
/// Si uno falla aquí y no allí (o al revés), iOS y Android ya no calculan lo mismo.
final class SharedVectorsTests: XCTestCase {
    /// La raíz del repo desde este archivo, para que funcione igual en macOS y en Linux.
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("testdata/vectors")

    private func load<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: Self.directory.appendingPathComponent(name)))
    }

    private func day(_ iso: String) -> CalendarDay {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        return CalendarDay(year: p[0], month: p[1], day: p[2])!
    }

    func testMoneyParsing() throws {
        struct File: Decodable { var vectors: [V] }
        struct V: Decodable { var input: String; var minor: Int? }
        let file: File = try load("money_parse.json")
        XCTAssertFalse(file.vectors.isEmpty)
        for v in file.vectors {
            XCTAssertEqual(Money(parsing: v.input)?.minor, v.minor, "«\(v.input)»")
        }
    }

    func testDecimalParsing() throws {
        struct File: Decodable { var vectors: [Vector] }
        struct Vector: Decodable { var input: String; var maxFractionDigits: Int; var value: String? }
        let file: File = try load("decimal_parse.json")
        XCTAssertFalse(file.vectors.isEmpty)
        for v in file.vectors {
            let expected = try v.value.map { try XCTUnwrap(Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))) }
            XCTAssertEqual(Decimal(parsing: v.input, maxFractionDigits: v.maxFractionDigits), expected,
                           "«\(v.input)» con \(v.maxFractionDigits) decimales")
        }
    }

    func testCardInstallmentsAndStatementDates() throws {
        struct File: Decodable { var installments: [I]; var statementDates: [S] }
        struct I: Decodable { var principal: Int; var months: Int; var rate: Decimal; var payment: Int }
        struct S: Decodable {
            var statementDay: Int; var paymentDay: Int; var paymentDelayMonths: Int
            var purchase: String; var closing: String; var payment: String; var cycleStart: String
        }
        let file: File = try load("card_installments.json")
        XCTAssertFalse(file.installments.isEmpty)
        for v in file.installments {
            let quota = CardInstallment.payment(principal: Money(minor: v.principal), months: v.months, rate: v.rate)
            XCTAssertEqual(quota.minor, v.payment, "\(v.principal) en \(v.months) meses al \(v.rate) %")
        }
        for v in file.statementDates {
            let terms = CreditCardTerms(accountId: UUID(), householdId: UUID(), creditLimit: Money(minor: 100_000),
                                        statementDay: v.statementDay, paymentDay: v.paymentDay,
                                        paymentDelayMonths: v.paymentDelayMonths)
            let closing = terms.statementClosing(for: day(v.purchase))
            XCTAssertEqual(closing.iso, v.closing, "compra \(v.purchase)")
            XCTAssertEqual(terms.paymentDate(forStatement: closing).iso, v.payment, "compra \(v.purchase)")
            XCTAssertEqual(terms.cycleStart(forStatement: closing).iso, v.cycleStart, "compra \(v.purchase)")
        }
    }

    func testCardSummaries() throws {
        struct File: Decodable { var summaries: [Case] }
        struct Case: Decodable {
            var name: String; var today: String; var statementDay: Int; var paymentDay: Int; var paymentDelayMonths: Int
            var balance: Int; var movements: [Move]; var installments: [Plan]
            var used: Int; var revolvingBalance: Int; var unresolved: Int; var payments: [Charge]
        }
        struct Move: Decodable { var key: String; var day: String; var amount: Int; var payment: Bool? }
        struct Plan: Decodable { var movement: String; var months: Int; var rate: Decimal }
        struct Charge: Decodable, Equatable {
            var due: String; var amount: Int; var purchases: Int; var installments: Int; var interest: Int
        }
        let file: File = try load("card_installments.json")
        XCTAssertFalse(file.summaries.isEmpty)
        let home = UUID(), card = UUID(), transfer = UUID()
        for v in file.summaries {
            let terms = CreditCardTerms(accountId: card, householdId: home, creditLimit: Money(minor: 300_000),
                                        statementDay: v.statementDay, paymentDay: v.paymentDay,
                                        paymentDelayMonths: v.paymentDelayMonths)
            var ids: [String: UUID] = [:]
            let movements = v.movements.map { m -> Movement in
                let movement = Movement(householdId: home, accountId: card, categoryId: m.payment == true ? transfer : nil,
                                        bookedOn: day(m.day), amount: Money(minor: m.amount), description: m.key)
                ids[m.key] = movement.id
                return movement
            }
            // Un aplazado cuya compra no está en la lista apunta a un movimiento que no se ha cargado.
            let plans = v.installments.map {
                CardInstallment(householdId: home, accountId: card, movementId: ids[$0.movement] ?? UUID(),
                                months: $0.months, rate: $0.rate)
            }
            let s = CreditCardCalculator.summary(terms: terms, balance: Money(minor: v.balance), movements: movements,
                                                 installments: plans, transferCategories: [transfer], today: day(v.today))
            XCTAssertEqual(s.used.minor, v.used, v.name)
            XCTAssertEqual(s.revolvingBalance.minor, v.revolvingBalance, v.name)
            XCTAssertEqual(s.unresolvedInstallments.count, v.unresolved, v.name)
            let got = s.payments.map {
                Charge(due: $0.due.iso, amount: $0.amount.minor, purchases: $0.purchases.minor,
                       installments: $0.installments.minor, interest: $0.interest.minor)
            }
            XCTAssertEqual(got, v.payments, v.name)
        }
    }

    func testPaymentCalendar() throws {
        struct File: Decodable { var vectors: [V] }
        struct V: Decodable { var name: String; var series: S; var from: String; var through: String; var payments: [P] }
        struct S: Decodable {
            var kind: String; var amount: Int; var every: Int; var unit: String; var startsOn: String
            var endsOn: String?; var introAmount: Int?; var introCharges: Int?
        }
        struct P: Decodable, Equatable { var day: String; var amount: Int }
        let file: File = try load("payment_calendar.json")
        XCTAssertFalse(file.vectors.isEmpty)
        for v in file.vectors {
            let s = v.series
            let series = RecurringSeries(householdId: UUID(), name: "Serie", kind: RecurringKind(rawValue: s.kind)!,
                                         amount: Money(minor: s.amount),
                                         recurrence: Recurrence(every: s.every, unit: RecurrenceUnit(rawValue: s.unit)!),
                                         startsOn: day(s.startsOn), endsOn: s.endsOn.map(day),
                                         introAmount: s.introAmount.map { Money(minor: $0) }, introCharges: s.introCharges)
            let got = PaymentCalendar(series: [series]).payments(from: day(v.from), through: day(v.through))
                .map { P(day: $0.day.iso, amount: $0.amount.minor) }
            XCTAssertEqual(got, v.payments, v.name)
        }
    }

    func testBudgetPeriods() throws {
        struct File: Decodable { var vectors: [V] }
        struct V: Decodable {
            var frequency: String; var day1: Int; var day2: Int?; var anchor: String?
            var day: String; var start: String; var end: String
        }
        let file: File = try load("budget_periods.json")
        XCTAssertFalse(file.vectors.isEmpty)
        for v in file.vectors {
            let schedule = PaySchedule(frequency: PayFrequency(rawValue: v.frequency)!, day1: v.day1, day2: v.day2,
                                       anchor: v.anchor.map(day))
            let period = schedule.period(containing: day(v.day))
            XCTAssertEqual("\(period.start.iso)..\(period.end.iso)", "\(v.start)..\(v.end)", "\(v.frequency) \(v.day1) el \(v.day)")
        }
    }

    func testImportFingerprint() throws {
        struct File: Decodable { var vectors: [V] }
        struct V: Decodable { var name: String; var csv: String; var rows: [R] }
        struct R: Decodable { var hashInput: String; var importHash: String }
        let file: File = try load("import_fingerprint.json")
        XCTAssertFalse(file.vectors.isEmpty)
        for v in file.vectors {
            let table = CSVTable.parse(v.csv)
            let mapping = try XCTUnwrap(CSVMapping.detect(in: table), v.name)
            let hashes = CSVImporter.rows(in: table, mapping: mapping, accountId: UUID()).map { $0.draft?.importHash }
            XCTAssertEqual(hashes, v.rows.map { $0.importHash as String? }, v.name)
        }
    }

    func testTradeTimeline() throws {
        struct File: Decodable { var vectors: [Vector] }
        struct Vector: Decodable { var name: String; var trades: [Entry]; var oversold: Bool }
        struct Entry: Decodable { var day: String; var side: TradeSide; var quantity: String }
        let file: File = try load("trade_timeline.json")
        XCTAssertFalse(file.vectors.isEmpty)
        let holding = UUID()
        for v in file.vectors {
            let trades = try v.trades.map {
                InvestmentTrade(householdId: UUID(), holdingId: holding, tradedOn: day($0.day), side: $0.side,
                                quantity: try XCTUnwrap(Decimal(string: $0.quantity, locale: Locale(identifier: "en_US_POSIX"))),
                                price: 10)
            }
            XCTAssertEqual(Position.isOversold(holding, in: trades), v.oversold, v.name)
        }
    }

    func testSHA256() throws {
        struct File: Decodable { var vectors: [V] }
        struct V: Decodable { var text: String; var `repeat`: Int; var utf8Bytes: Int; var sha256: String }
        let file: File = try load("sha256.json")
        XCTAssertFalse(file.vectors.isEmpty)
        for v in file.vectors {
            let input = String(repeating: v.text, count: v.repeat)
            XCTAssertEqual(input.utf8.count, v.utf8Bytes)
            XCTAssertEqual(SHA256.hex(input), v.sha256, "«\(v.text)» × \(v.repeat)")
        }
    }
}
