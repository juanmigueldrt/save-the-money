import Foundation

/// Importe en unidades menores (céntimos). Nunca se usa `Double` para dinero.
public struct Money: Hashable, Codable, Sendable {
    public var minor: Int
    public var currency: String

    public init(minor: Int, currency: String = "EUR") {
        self.minor = minor
        self.currency = currency
    }

    public static func zero(_ currency: String = "EUR") -> Money {
        Money(minor: 0, currency: currency)
    }

    /// Valor decimal exacto, p. ej. 1234 céntimos -> 12.34.
    public var decimal: Decimal { Decimal(minor) / 100 }

    public var isNegative: Bool { minor < 0 }

    /// Convierte texto escrito por el usuario o leído de un CSV ("1.234,56", "-12,5", "12.50 €").
    /// Devuelve nil si no es un importe válido.
    public init?(parsing text: String, currency: String = "EUR") {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "EUR", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }

        var negative = false
        if s.hasPrefix("-") { negative = true; s.removeFirst() }
        else if s.hasPrefix("+") { s.removeFirst() }
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        if s.hasSuffix("-") { negative = true; s.removeLast() }

        // El último separador ("," o ".") seguido de 1 o 2 dígitos es el decimal;
        // el resto son separadores de miles.
        let lastComma = s.lastIndex(of: ",")
        let lastDot = s.lastIndex(of: ".")
        let decimalSep: Character?
        switch (lastComma, lastDot) {
        case let (c?, d?): decimalSep = c > d ? "," : "."
        case let (c?, nil): decimalSep = s.distance(from: c, to: s.endIndex) - 1 <= 2 ? "," : nil
        case let (nil, d?): decimalSep = s.distance(from: d, to: s.endIndex) - 1 <= 2 ? "." : nil
        case (nil, nil): decimalSep = nil
        }

        var integerPart = s
        var fractionPart = ""
        if let sep = decimalSep, let idx = s.lastIndex(of: sep) {
            integerPart = String(s[..<idx])
            fractionPart = String(s[s.index(after: idx)...])
        }
        integerPart.removeAll { $0 == "." || $0 == "," }
        guard !integerPart.isEmpty || !fractionPart.isEmpty,
              integerPart.allSatisfy(\.isASCIIDigit),
              fractionPart.allSatisfy(\.isASCIIDigit),
              fractionPart.count <= 2 else { return nil }

        let fraction = fractionPart.padding(toLength: 2, withPad: "0", startingAt: 0)
        guard let whole = Int(integerPart.isEmpty ? "0" : integerPart),
              let cents = Int(fraction) else { return nil }
        let (scaled, overflow1) = whole.multipliedReportingOverflow(by: 100)
        let (total, overflow2) = scaled.addingReportingOverflow(cents)
        guard !overflow1, !overflow2 else { return nil }
        self.init(minor: negative ? -total : total, currency: currency)
    }

    /// Texto en formato español: "1.234,56 €".
    public func formatted(locale: Locale = Locale(identifier: "es_ES")) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currency
        return formatter.string(from: decimal as NSDecimalNumber) ?? "\(decimal) \(currency)"
    }
}

extension Money: Comparable {
    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currency == rhs.currency, "No se comparan monedas distintas")
        return lhs.minor < rhs.minor
    }
}

extension Money: AdditiveArithmetic {
    public static var zero: Money { Money(minor: 0) }

    public static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "No se suman monedas distintas")
        return Money(minor: lhs.minor + rhs.minor, currency: lhs.currency)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "No se restan monedas distintas")
        return Money(minor: lhs.minor - rhs.minor, currency: lhs.currency)
    }

    public static prefix func - (value: Money) -> Money {
        Money(minor: -value.minor, currency: value.currency)
    }
}

extension Money {
    /// Reparte el importe según porcentajes que suman 100, sin perder céntimos:
    /// el resto del redondeo va a las primeras partes.
    public func split(percentages: [Int]) -> [Money] {
        precondition(percentages.reduce(0, +) == 100, "Los porcentajes deben sumar 100")
        let base = percentages.map { minor * $0 / 100 }
        var remainder = minor - base.reduce(0, +)
        let step = remainder >= 0 ? 1 : -1
        var result = base
        var i = 0
        while remainder != 0 {
            result[i % result.count] += step
            remainder -= step
            i += 1
        }
        return result.map { Money(minor: $0, currency: currency) }
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
