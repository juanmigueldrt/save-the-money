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

    func testMonthlyTotalStartsAndEnds() throws {
        struct File: Decodable { var vectors: [Vector] }
        struct Vector: Decodable { var name: String; var day: String; var series: [Serie]; var expected: Int }
        struct Serie: Decodable { var amount: Int; var startsOn: String; var endsOn: String? }
        let file: File = try load("monthly_total.json")
        XCTAssertFalse(file.vectors.isEmpty)
        for v in file.vectors {
            let series = v.series.map { s in
                RecurringSeries(householdId: UUID(), name: "Serie", kind: .subscription, amount: Money(minor: s.amount),
                                startsOn: day(s.startsOn), endsOn: s.endsOn.map { day($0) })
            }
            XCTAssertEqual(series.monthlyTotal(of: .subscription, on: day(v.day)).minor, v.expected, v.name)
        }
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

    func testNetWorthHistory() throws {
        struct File: Decodable { var cases: [Case] }
        struct Case: Decodable {
            var name: String; var through: String; var months: Int; var accounts: [Acc]; var movements: [Move]
            var assets: [Int]; var liabilities: [Int]; var net: [Int]
        }
        struct Acc: Decodable {
            var key: String; var opening: Int; var createdAt: String?; var archivedAt: String?; var includeInNetWorth: Bool?
        }
        struct Move: Decodable { var account: String; var day: String; var amount: Int }
        let file: File = try load("net_worth.json")
        XCTAssertFalse(file.cases.isEmpty)
        let home = UUID()
        func instant(_ text: String?) throws -> Date? { try text.map { try XCTUnwrap(ISO8601DateFormatter().date(from: $0)) } }
        for v in file.cases {
            var ids: [String: UUID] = [:]
            let accounts = try v.accounts.map { a -> Account in
                let account = Account(householdId: home, name: a.key, openingBalance: Money(minor: a.opening),
                                      archivedAt: try instant(a.archivedAt), includeInNetWorth: a.includeInNetWorth ?? true,
                                      createdAt: try instant(a.createdAt))
                ids[a.key] = account.id
                return account
            }
            let movements = try v.movements.map {
                Movement(householdId: home, accountId: try XCTUnwrap(ids[$0.account]), categoryId: nil,
                         bookedOn: day($0.day), amount: Money(minor: $0.amount), description: "Movimiento")
            }
            let through = day(v.through + "-01")
            let history = NetWorth.history(accounts: accounts, movements: movements, months: v.months,
                                           through: MonthKey(year: through.year, month: through.month))
            XCTAssertEqual(history.map(\.assets.minor), v.assets, v.name)
            XCTAssertEqual(history.map(\.liabilities.minor), v.liabilities, v.name)
            XCTAssertEqual(history.map(\.net.minor), v.net, v.name)
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
            var used: Int; var revolvingBalance: Int; var unresolved: Int; var uncategorized: Int; var payments: [Charge]
        }
        struct Move: Decodable { var key: String; var day: String; var amount: Int; var payment: Bool?; var refund: Bool? }
        struct Plan: Decodable { var movement: String; var months: Int; var rate: Decimal }
        struct Charge: Decodable, Equatable {
            var due: String; var amount: Int; var purchases: Int; var installments: Int; var interest: Int
        }
        let file: File = try load("card_installments.json")
        XCTAssertFalse(file.summaries.isEmpty)
        let home = UUID(), card = UUID(), transfer = UUID(), shopping = UUID()
        for v in file.summaries {
            let terms = CreditCardTerms(accountId: card, householdId: home, creditLimit: Money(minor: 300_000),
                                        statementDay: v.statementDay, paymentDay: v.paymentDay,
                                        paymentDelayMonths: v.paymentDelayMonths)
            var ids: [String: UUID] = [:]
            let movements = v.movements.map { m -> Movement in
                let movement = Movement(householdId: home, accountId: card, categoryId: m.payment == true ? transfer : m.refund == true ? shopping : nil,
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
            XCTAssertEqual(s.uncategorizedCredits.count, v.uncategorized, v.name)
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

    func testReportPeriods() throws {
        struct File: Decodable { var monthStartDay: Int; var today: String; var movements: [Apunte]; var vectors: [Caso] }
        struct Apunte: Decodable { var day: String; var minor: Int }
        struct Caso: Decodable {
            var preset: String; var range: [String]; var total: Int; var months: [Month]
            var previousRange: [String]; var previousTotal: Int
        }
        struct Month: Decodable { var month: String; var minor: Int }
        let file: File = try load("report_periods.json")
        XCTAssertFalse(file.vectors.isEmpty)
        let home = UUID(), account = UUID()
        let movements = file.movements.map {
            Movement(householdId: home, accountId: account, categoryId: nil, bookedOn: day($0.day),
                     amount: Money(minor: $0.minor), description: "Gasto")
        }
        let today = day(file.today)
        for v in file.vectors {
            let preset = try XCTUnwrap(ReportPeriod(rawValue: v.preset), v.preset)
            let range = preset.range(today: today, monthStartDay: file.monthStartDay)
            XCTAssertEqual("\(range.lowerBound.iso)..\(range.upperBound.iso)", v.range.joined(separator: ".."), v.preset)
            let report = SpendingReport(movements: movements, categories: [], range: range, monthStartDay: file.monthStartDay)
            XCTAssertEqual(report.total.minor, v.total, v.preset)
            let months = report.byMonth.map { String(format: "%04ld-%02ld=%ld", $0.month.year, $0.month.month, $0.amount.minor) }
            XCTAssertEqual(months, v.months.map { "\($0.month)=\($0.minor)" }, v.preset)

            let previous = preset.previousRange(today: today, monthStartDay: file.monthStartDay)
            XCTAssertEqual("\(previous.lowerBound.iso)..\(previous.upperBound.iso)", v.previousRange.joined(separator: ".."), v.preset)
            let previousReport = SpendingReport(movements: movements, categories: [], range: previous,
                                                monthStartDay: file.monthStartDay)
            XCTAssertEqual(previousReport.total.minor, v.previousTotal, v.preset)
        }
    }

    func testHouseholdMonth() throws {
        struct File: Decodable {
            var today: String; var categories: [Categoria]; var movements: [Apunte]
            var spent: [Gasto]; var rise: [Subida]; var filters: [Filtro]
        }
        struct Categoria: Decodable { var id: String; var name: String; var kind: String }
        struct Apunte: Decodable { var id: String; var day: String; var category: String; var minor: Int }
        struct Gasto: Decodable { var monthStartDay: Int; var minor: Int }
        struct Subida: Decodable { var monthStartDay: Int; var title: String?; var percent: Int?; var previous: String? }
        struct Filtro: Decodable { var dates: String; var monthStartDay: Int; var ids: [String] }
        let file: File = try load("household_month.json")
        let home = UUID(), account = UUID()
        var categoryIds: [String: UUID] = [:]
        var categories: [BudgetCategory] = []
        for c in file.categories {
            let id = UUID()
            categoryIds[c.id] = id
            categories.append(BudgetCategory(id: id, householdId: home, name: c.name,
                                             kind: try XCTUnwrap(CategoryKind(rawValue: c.kind))))
        }
        var names: [UUID: String] = [:]
        let movements = file.movements.map { m -> Movement in
            let id = UUID()
            names[id] = m.id
            return Movement(id: id, householdId: home, accountId: account, categoryId: categoryIds[m.category],
                            bookedOn: day(m.day), amount: Money(minor: m.minor), description: m.id)
        }
        let today = day(file.today)
        for g in file.spent {
            let spent = MonthSummary.spent(movements: movements, categories: categories, today: today,
                                           monthStartDay: g.monthStartDay)
            XCTAssertEqual(spent.minor, g.minor, "inicio \(g.monthStartDay)")
        }
        for s in file.rise {
            let month = MonthKey.containing(today, startDay: s.monthStartDay)
            let rise = BiggestRise.find(movements: movements, categories: categories, month: month,
                                        monthStartDay: s.monthStartDay)
            XCTAssertEqual(rise?.title, s.title, "inicio \(s.monthStartDay)")
            XCTAssertEqual(rise?.percent, s.percent, "inicio \(s.monthStartDay)")
            XCTAssertEqual(rise.map { String(format: "%04ld-%02ld", $0.previous.year, $0.previous.month) }, s.previous,
                           "inicio \(s.monthStartDay)")
        }
        for f in file.filters {
            let filter = MovementFilter(dates: try XCTUnwrap(MovementDateFilter(rawValue: f.dates), f.dates))
            let kept = filter.apply(to: movements, categories: categories, today: today, monthStartDay: f.monthStartDay)
            XCTAssertEqual(kept.compactMap { names[$0.id] }, f.ids, "\(f.dates) inicio \(f.monthStartDay)")
        }
    }

    func testImportFingerprint() throws {
        struct File: Decodable { var vectors: [Vector] }
        struct Vector: Decodable { var name: String; var csv: String; var rows: [Row] }
        struct Row: Decodable { var hashInput: String?; var importHash: String? }
        let file: File = try load("import_fingerprint.json")
        XCTAssertFalse(file.vectors.isEmpty)
        for v in file.vectors {
            let table = CSVTable.parse(v.csv)
            let mapping = try XCTUnwrap(CSVMapping.detect(in: table), v.name)
            let hashes = CSVImporter.rows(in: table, mapping: mapping, accountId: UUID()).map { $0.draft?.importHash }
            XCTAssertEqual(hashes, v.rows.map(\.importHash), v.name)
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
