import Foundation

/// Movimientos en un CSV que Excel en español abre bien a la primera:
/// separador ";", coma decimal, fechas dd/mm/aaaa, saltos de línea CRLF y BOM UTF-8.
public enum MovementsCSV {
    public static let header = ["Fecha", "Cuenta", "Categoría", "Descripción", "Importe", "Moneda", "Notas"]

    public static func text(_ movements: [Movement], accounts: [Account], categories: [BudgetCategory]) -> String {
        let accountNames = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let categoryNames = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let sorted = movements.sorted { ($0.bookedOn, $0.description) < ($1.bookedOn, $1.description) }
        var lines = [header.map(field).joined(separator: ";")]
        for movement in sorted {
            let row = [
                field(dayText(movement.bookedOn)),
                field(accountNames[movement.accountId] ?? ""),
                field(movement.categoryId.flatMap { categoryNames[$0] } ?? ""),
                field(movement.description),
                amountText(movement.amount),
                field(movement.amount.currency),
                field(movement.notes ?? ""),
            ]
            lines.append(row.joined(separator: ";"))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Los bytes del fichero, con BOM para que Excel lo lea como UTF-8 (tildes y "€").
    public static func data(_ movements: [Movement], accounts: [Account], categories: [BudgetCategory]) -> Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(text(movements, accounts: accounts, categories: categories).utf8)
    }

    public static func fileName(on day: CalendarDay = CalendarDay()) -> String {
        "movimientos-\(day.iso).csv"
    }

    /// "1234,56" o "-12,05": sin separador de miles, para que Excel lo tome como número.
    public static func amountText(_ money: Money) -> String {
        let magnitude = money.minor.magnitude
        let cents = magnitude % 100
        return (money.isNegative ? "-" : "") + "\(magnitude / 100)," + (cents < 10 ? "0\(cents)" : "\(cents)")
    }

    public static func dayText(_ day: CalendarDay) -> String {
        String(format: "%02d/%02d/%04d", day.day, day.month, day.year)
    }

    /// Entrecomilla si hace falta y desactiva fórmulas: un texto que empieza por
    /// "=", "+", "-" o "@" se abriría en Excel como fórmula.
    public static func field(_ value: String) -> String {
        var text = value
        if let first = text.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) {
            text = "'" + text
        }
        let needsQuotes = text.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        guard needsQuotes else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Lo que hay que pagar en un mes según los pagos fijos (suscripciones y gastos esenciales),
/// para el PDF de "cuentas a pagar del mes".
public struct MonthlyBills: Hashable, Sendable {
    public struct Line: Hashable, Sendable, Identifiable {
        public var name: String
        public var kind: RecurringKind
        public var due: CalendarDay
        public var amount: Money
        public var accountName: String?
        public var id: String

        public init(name: String, kind: RecurringKind, due: CalendarDay, amount: Money, accountName: String?, id: String) {
            self.name = name
            self.kind = kind
            self.due = due
            self.amount = amount
            self.accountName = accountName
            self.id = id
        }
    }

    public var month: MonthKey
    public var lines: [Line]

    public init(series: [RecurringSeries], month: MonthKey, accounts: [Account] = []) {
        self.month = month
        let accountNames = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let first = month.firstDay
        let last = month.adding(months: 1).firstDay.adding(days: -1)
        var lines: [Line] = []
        for item in series where !item.isArchived && item.kind != .income {
            for due in item.occurrences(from: first, through: last) {
                lines.append(Line(name: item.trimmedName, kind: item.kind, due: due, amount: item.amount(on: due),
                                  accountName: item.accountId.flatMap { accountNames[$0] },
                                  id: "\(item.id.uuidString)-\(due.iso)"))
            }
        }
        lines.sort { ($0.due, $0.name) < ($1.due, $1.name) }
        self.lines = lines
    }

    public var total: Money { lines.reduce(Money.zero) { $0 + $1.amount } }

    public func total(of kind: RecurringKind) -> Money {
        lines.filter { $0.kind == kind }.reduce(Money.zero) { $0 + $1.amount }
    }

    /// Lo que aún queda por pagar desde ese día (incluido).
    public func pending(from today: CalendarDay) -> Money {
        lines.filter { $0.due >= today }.reduce(Money.zero) { $0 + $1.amount }
    }

    public var fileName: String {
        String(format: "pagos-%04d-%02d.pdf", month.year, month.month)
    }
}
