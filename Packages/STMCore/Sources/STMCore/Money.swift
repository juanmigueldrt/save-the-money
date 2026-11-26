import Foundation

/// Importe en unidades menores (céntimos). Nunca se usa `Double` para dinero.
public struct Money: Hashable, Codable, Sendable {
    public var minor: Int
    public var currency: String

    public init(minor: Int, currency: String = "EUR") {
        self.minor = minor
        self.currency = currency
    }

    /// Valor decimal exacto, p. ej. 1234 céntimos -> 12.34.
    public var decimal: Decimal { Decimal(minor) / 100 }

    public var isNegative: Bool { minor < 0 }

    /// Convierte texto escrito por el usuario o leído de un CSV ("1.234,56", "-12,5", "12.50 €").
    /// Devuelve nil si no es un importe válido. La regla completa está en `NumberParser`.
    public init?(parsing text: String, currency: String = "EUR") {
        guard let number = NumberParser.parse(text, maxFractionDigits: 2),
              let whole = Int(number.integer.isEmpty ? "0" : number.integer),
              let cents = Int(number.fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) else { return nil }
        // Como mucho 15 cifras enteras: en céntimos cabe de sobra en un Int.
        let total = whole * 100 + cents
        self.init(minor: number.isNegative ? -total : total, currency: currency)
    }

    /// Texto en formato español: "1.234,56 €". Respeta `Money.display` (modo incógnito y redondeo).
    public func formatted(locale: Locale = Locale(identifier: "es_ES")) -> String {
        formatted(locale: locale, options: Money.display)
    }

    /// Igual, con unas opciones concretas (p. ej. `.standard` para un PDF o un archivo).
    public func formatted(locale: Locale = Locale(identifier: "es_ES"), options: MoneyDisplayOptions) -> String {
        if isMixed { return Money.mixedText }
        return Money.withFormatter(locale: locale, currency: currency, roundsToUnits: options.roundsToUnits) { formatter in
            if options.hidesAmounts { return "•••• " + (formatter.currencySymbol ?? currency) }
            let text = formatter.string(from: decimal as NSDecimalNumber) ?? "\(decimal) \(currency)"
            // Signo menos tipográfico (U+2212), como pide el manual, en vez del guion.
            return text.replacingOccurrences(of: "-", with: "\u{2212}")
        }
    }

    private struct FormatterKey: Hashable {
        var locale: Locale
        var currency: String
        var roundsToUnits: Bool
    }

    private static let formattersLock = NSLock()
    /// Un formateador por configuración regional, moneda y redondeo: crearlo era lo caro de cada importe.
    /// `NumberFormatter` no es `Sendable`: solo se toca con el candado cogido (crearlo, configurarlo y
    /// usarlo), así que nunca lo usan dos hilos a la vez y nadie lo cambia después de guardarlo.
    nonisolated(unsafe) private static var formatters: [FormatterKey: NumberFormatter] = [:]

    private static func withFormatter(locale: Locale, currency: String, roundsToUnits: Bool,
                                      _ body: (NumberFormatter) -> String) -> String {
        formattersLock.lock()
        defer { formattersLock.unlock() }
        let key = FormatterKey(locale: locale, currency: currency, roundsToUnits: roundsToUnits)
        if let formatter = formatters[key] { return body(formatter) }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currency
        if roundsToUnits {
            formatter.maximumFractionDigits = 0
            formatter.minimumFractionDigits = 0
        }
        formatters[key] = formatter
        return body(formatter)
    }
}

extension Money: Comparable {
    public static func < (lhs: Money, rhs: Money) -> Bool {
        // Monedas distintas no se comparan por importe: se ordenan por moneda, sin cerrar la app.
        lhs.currency == rhs.currency ? lhs.minor < rhs.minor : lhs.currency < rhs.currency
    }
}

extension Money: AdditiveArithmetic {
    public static var zero: Money { Money(minor: 0) }

    /// Suma sin mezclar monedas. Con monedas distintas el resultado es `Money.mixed`, que en
    /// pantalla sale como «Varias monedas» en vez de una cifra falsa; nunca cierra la app.
    /// Un cero no tiene moneda que mezclar: `0 € + 5 $` son `5 $`. Para sumar monedas
    /// distintas hay que convertir antes con `converted(to:rate:)`.
    public static func + (lhs: Money, rhs: Money) -> Money {
        combined(lhs, rhs.minor, rhs)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        combined(lhs, -rhs.minor, rhs)
    }

    private static func combined(_ lhs: Money, _ added: Int, _ rhs: Money) -> Money {
        if lhs.isMixed || rhs.isMixed { return .mixed }
        if lhs.currency == rhs.currency { return Money(minor: lhs.minor + added, currency: lhs.currency) }
        if added == 0 { return lhs }
        if lhs.minor == 0 { return Money(minor: added, currency: rhs.currency) }
        return .mixed
    }

    public static prefix func - (value: Money) -> Money {
        Money(minor: -value.minor, currency: value.currency)
    }
}

extension Money {
    /// Moneda del resultado de sumar o restar monedas distintas sin convertir. No es un código
    /// ISO (la base solo admite tres mayúsculas), así que ninguna cuenta puede tenerla.
    public static let mixedCurrency = "*"
    /// Lo que se enseña en vez de un importe cuando se han mezclado monedas.
    public static let mixedText = "Varias monedas"
    /// «No es un importe»: lo devuelven `+` y `-` con monedas distintas, y se contagia a lo que se le sume.
    public static let mixed = Money(minor: 0, currency: mixedCurrency)

    public var isMixed: Bool { currency == Money.mixedCurrency }

    /// Conversión explícita: el importe por el tipo de cambio (unidades de `currency` por cada
    /// unidad de la moneda de origen), redondeado al céntimo más cercano (0,5 se aleja del cero).
    public func converted(to currency: String, rate: Decimal) -> Money {
        let cents = (Decimal(minor) * rate).rounded(scale: 0)
        return Money(minor: NSDecimalNumber(decimal: cents).intValue, currency: currency)
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
