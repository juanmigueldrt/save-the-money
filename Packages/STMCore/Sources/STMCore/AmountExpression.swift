import Foundation

/// Importe escrito como una cuenta sencilla: "12,50+3×2" o "100/3".
/// Admite + − × ÷ (y también - * x / :) y paréntesis. Cada número se lee como
/// `Money(parsing:)`, así que "1.234,56" y "12.50" valen igual que en el resto de la app.
/// El resultado se redondea al céntimo (la mitad hacia arriba).
public enum AmountExpression {
    /// Calcula el importe, o nil si el texto no es una cuenta válida (o divide entre cero).
    public static func evaluate(_ text: String, currency: String = "EUR") -> Money? {
        var parser = Parser(tokens: tokenize(text) ?? [])
        guard !parser.tokens.isEmpty, let value = parser.expression(), parser.isAtEnd else { return nil }
        // Fracción de céntimo: se redondea al céntimo más cercano.
        var cents = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &cents, 0, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        guard number.doubleValue.magnitude < 9e15 else { return nil }
        return Money(minor: number.intValue, currency: currency)
    }

    /// true si el texto tiene alguna operación (para enseñar el resultado debajo del campo).
    public static func hasOperation(_ text: String) -> Bool {
        guard let tokens = tokenize(text) else { return false }
        // Un "-" al principio es sólo el signo.
        return tokens.dropFirst().contains { if case .op = $0 { return true } else { return false } }
            || tokens.contains { if case .open = $0 { return true } else { return false } }
    }

    // MARK: Tokens

    enum Token: Equatable {
        case number(Decimal)
        case op(Character)
        case open, close
    }

    static func tokenize(_ text: String) -> [Token]? {
        var tokens: [Token] = []
        var number = ""
        func flush() -> Bool {
            guard !number.isEmpty else { return true }
            defer { number = "" }
            guard let money = Money(parsing: number) else { return false }
            tokens.append(.number(money.decimal))
            return true
        }
        let cleaned = text.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "EUR", with: "")
        for ch in cleaned {
            switch ch {
            case "0"..."9", ",", ".":
                number.append(ch)
            case " ", "\u{00A0}", "\u{202F}":
                continue
            case "+":
                guard flush() else { return nil }; tokens.append(.op("+"))
            case "-", "\u{2212}":
                guard flush() else { return nil }; tokens.append(.op("-"))
            case "*", "×", "x", "X":
                guard flush() else { return nil }; tokens.append(.op("*"))
            case "/", "÷", ":":
                guard flush() else { return nil }; tokens.append(.op("/"))
            case "(":
                guard flush() else { return nil }; tokens.append(.open)
            case ")":
                guard flush() else { return nil }; tokens.append(.close)
            default:
                return nil
            }
        }
        guard flush() else { return nil }
        return tokens
    }

    // MARK: Análisis (precedencia normal: × ÷ antes que + −)

    struct Parser {
        var tokens: [Token]
        var index = 0

        var isAtEnd: Bool { index == tokens.count }

        private var peek: Token? { index < tokens.count ? tokens[index] : nil }

        mutating func expression() -> Decimal? {
            guard var value = term() else { return nil }
            while case .op(let op)? = peek, op == "+" || op == "-" {
                index += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func term() -> Decimal? {
            guard var value = factor() else { return nil }
            while case .op(let op)? = peek, op == "*" || op == "/" {
                index += 1
                guard let rhs = factor() else { return nil }
                if op == "*" {
                    value *= rhs
                } else {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                }
            }
            return value
        }

        mutating func factor() -> Decimal? {
            switch peek {
            case .number(let n)?:
                index += 1
                return n
            case .op("-")?:
                index += 1
                return factor().map { -$0 }
            case .op("+")?:
                index += 1
                return factor()
            case .open?:
                index += 1
                guard let value = expression(), peek == .close else { return nil }
                index += 1
                return value
            default:
                return nil
            }
        }
    }
}

extension Money {
    /// Lo que el usuario escribe en un campo de importe: un número o una cuenta ("12,50+3×2").
    public init?(entered text: String, currency: String = "EUR") {
        if let plain = Money(parsing: text, currency: currency) {
            self = plain
        } else if let result = AmountExpression.evaluate(text, currency: currency) {
            self = result
        } else {
            return nil
        }
    }
}
