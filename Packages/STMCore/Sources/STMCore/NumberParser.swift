import Foundation

/// Un número ya leído por `NumberParser`: sólo cifras, sin signo ni separadores.
struct ParsedNumber {
    var isNegative: Bool
    /// Parte entera sin separadores de miles. Vacía en ",5".
    var integer: String
    /// Decimales tal como se escribieron. Vacía si no había separador decimal.
    var fraction: String
}

/// El único lector de números escritos a mano o leídos de un CSV. Lo usan los importes
/// (`Money(parsing:)`, 2 decimales) y los precios, participaciones y tipos (`Decimal(parsing:)`).
/// Android aplica la misma regla en `parseNumber` (Money.kt); los casos compartidos están en
/// `testdata/vectors/money_parse.json` y `decimal_parse.json`.
///
/// Principio: si el texto es ambiguo, se rechaza en vez de adivinar. Un importe rechazado
/// se ve en pantalla; uno mal leído, no.
///
/// 1. Se quitan los espacios, tabuladores y saltos de línea de los extremos, y después «€»,
///    «EUR», los espacios, U+00A0 y U+202F de cualquier sitio. No se quita nada más:
///    cualquier otra letra o símbolo invalida el texto.
/// 2. Signo: un «-» o U+2212 delante, uno detrás, o unos paréntesis que lo envuelven todo
///    significan negativo. Un «+» delante se ignora. Más de una marca de signo (el «+» cuenta)
///    invalida el texto.
/// 3. Sólo pueden quedar cifras, «,» y «.», con al menos una cifra.
/// 4. Con «,» y «.» a la vez: el que aparece el último es el separador decimal y sólo puede
///    estar una vez; el otro agrupa miles.
/// 5. Con un solo tipo, más de una vez: agrupa miles y no hay decimales.
/// 6. Con un solo tipo, una vez: la «,» es siempre el separador decimal (convención española).
///    El «.» seguido de un número de cifras distinto de 3 es el separador decimal ("12.5", "12.50").
///    El «.» seguido de exactamente 3 cifras depende del campo: si admite menos de 3 decimales
///    (importes, tipos) agrupa miles ("1.250" es 1250); si admite 3 o más (participaciones,
///    precios, comisión) el texto no vale, porque podría ser 1,234 o 1234: se escribe "1,234"
///    o "1234".
/// 7. Los miles tienen que estar bien formados: el primer grupo tiene de 1 a 3 cifras y no
///    empieza por «0», y cada grupo siguiente tiene exactamente 3 ("1,2,3", "0.125", "012.345"
///    y "00.125" no valen).
/// 8. Detrás del separador decimal puede haber como mucho `maxFractionDigits` cifras. Con más
///    el texto no vale; nunca se redondea ("0,125" no es un importe, y es 0,125 como
///    participaciones). Un separador decimal al final, sin cifras detrás, se admite y no añade
///    decimales ("12," es 12 y "5." es 5).
/// 9. La parte entera puede faltar si hay decimales (",5" es 0,5). Un separador solo («,» o «.»)
///    no vale.
/// 10. Más de 15 cifras enteras no valen.
enum NumberParser {
    static func parse(_ text: String, maxFractionDigits: Int) -> ParsedNumber? {
        var s = text.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{00A0}\u{202F}"))
        for ignored in ["€", "EUR", " ", "\u{00A0}", "\u{202F}"] {
            s = s.replacingOccurrences(of: ignored, with: "")
        }
        guard let isNegative = removeSign(from: &s), s.contains(where: \.isASCIIDigit),
              s.allSatisfy({ $0.isASCIIDigit || $0 == "," || $0 == "." }) else { return nil }

        let decimal = decimalSeparator(in: s)
        var integer = s
        var fraction = ""
        if let decimal, let index = s.lastIndex(of: decimal) {
            // Regla 4: el separador decimal sólo puede estar una vez.
            guard s.firstIndex(of: decimal) == index else { return nil }
            integer = String(s[..<index])
            fraction = String(s[s.index(after: index)...])
        }
        guard fraction.count <= maxFractionDigits else { return nil }

        let groups = integer.split(omittingEmptySubsequences: false) { $0 == "," || $0 == "." }
        // Regla 6: sin separador decimal y con dos grupos es un «.» solo con 3 cifras detrás,
        // ambiguo si el campo admite 3 decimales.
        if decimal == nil, groups.count == 2, maxFractionDigits >= 3 { return nil }
        if groups.count > 1 {
            guard (1...3).contains(groups[0].count), groups[0].first != "0",
                  groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        let digits = groups.joined()
        guard digits.count <= 15 else { return nil }
        return ParsedNumber(isNegative: isNegative, integer: digits, fraction: fraction)
    }

    /// Regla 2: quita la marca de signo y dice si el número es negativo. Nil si hay más de una.
    private static func removeSign(from s: inout String) -> Bool? {
        var signs = 0
        var isNegative = false
        if s.count >= 2, s.hasPrefix("("), s.hasSuffix(")") {
            signs += 1; isNegative = true; s = String(s.dropFirst().dropLast())
        }
        if let first = s.first, first.isMinus || first == "+" {
            signs += 1; isNegative = isNegative || first.isMinus; s.removeFirst()
        }
        if let last = s.last, last.isMinus {
            signs += 1; isNegative = true; s.removeLast()
        }
        return signs <= 1 ? isNegative : nil
    }

    /// Reglas 4 a 6: cuál es el separador decimal, si lo hay.
    private static func decimalSeparator(in s: String) -> Character? {
        let commas = s.filter { $0 == "," }.count
        let dots = s.filter { $0 == "." }.count
        if commas > 0, dots > 0 { return s.last { $0 == "," || $0 == "." } }
        if commas == 1 { return "," }
        if dots == 1, s.split(separator: ".", omittingEmptySubsequences: false).last?.count != 3 { return "." }
        return nil
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
    var isMinus: Bool { self == "-" || self == "\u{2212}" }
}
