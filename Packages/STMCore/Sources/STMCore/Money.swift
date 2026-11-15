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

    /// Texto en formato español: "1.234,56 €". Respeta `Money.display` (modo incógnito y redondeo).
    public func formatted(locale: Locale = Locale(identifier: "es_ES")) -> String {
        formatted(locale: locale, options: Money.display)
    }

    /// Igual, con unas opciones concretas (p. ej. `.standard` para un PDF o un archivo).
    public func formatted(locale: Locale = Locale(identifier: "es_ES"), options: MoneyDisplayOptions) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currency
        if options.hidesAmounts {
            return "•••• " + (formatter.currencySymbol ?? currency)
        }
        if options.roundsToUnits {
            formatter.maximumFractionDigits = 0
            formatter.minimumFractionDigits = 0
        }
        let text = formatter.string(from: decimal as NSDecimalNumber) ?? "\(decimal) \(currency)"
        // Signo menos tipográfico (U+2212), como pide el manual, en vez del guion.
        return text.replacingOccurrences(of: "-", with: "\u{2212}")
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

/// Cómo se enseñan los importes en la app (Más opciones > Vista).
public struct MoneyDisplayOptions: Hashable, Sendable {
    /// Modo incógnito: todos los importes salen como "•••• €".
    public var hidesAmounts: Bool
    /// Sin céntimos: "1.235 €" en vez de "1.234,56 €".
    public var roundsToUnits: Bool

    public init(hidesAmounts: Bool = false, roundsToUnits: Bool = false) {
        self.hidesAmounts = hidesAmounts
        self.roundsToUnits = roundsToUnits
    }

    /// Sin ocultar ni redondear, para PDF, CSV y pruebas.
    public static let standard = MoneyDisplayOptions()
}

extension Money {
    private static let displayLock = NSLock()
    nonisolated(unsafe) private static var storedDisplay = MoneyDisplayOptions.standard

    /// Opciones de vista activas. La app las cambia desde Más opciones; por defecto, `.standard`.
    public static var display: MoneyDisplayOptions {
        get { displayLock.lock(); defer { displayLock.unlock() }; return storedDisplay }
        set { displayLock.lock(); storedDisplay = newValue; displayLock.unlock() }
    }

    /// "+12,50 €" / "−12,50 €": con signo también en positivo (opción «Mostrar +»).
    public func signedText(options: MoneyDisplayOptions = Money.display) -> String {
        let magnitude = Money(minor: abs(minor), currency: currency).formatted(options: options)
        if options.hidesAmounts || minor == 0 { return magnitude }
        return (minor < 0 ? "\u{2212}" : "+") + magnitude
    }
}
