import Foundation

/// Código para unirse a un hogar, como "4K9Q2X". Lo genera el servidor;
/// la app sólo lo normaliza, lo valida y lo convierte en enlace o QR.
public struct InviteCode: Hashable, Codable, Sendable, CustomStringConvertible {
    /// Sin 0/O ni 1/I/L para que no se confundan al dictarlo.
    public static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    public static let length = 6
    public static let linkScheme = "savethemoney"

    public let value: String

    /// Acepta "4k9 q2x", "4K9-Q2X" o un enlace `savethemoney://unirse/4K9Q2X`.
    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), url.scheme == Self.linkScheme {
            text = url.lastPathComponent
        }
        let cleaned = text.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count == Self.length, cleaned.allSatisfy(Self.alphabet.contains) else { return nil }
        value = cleaned
    }

    /// Enlace que codifica el QR.
    public var link: URL { URL(string: "\(Self.linkScheme)://unirse/\(value)")! }

    /// "4K9 Q2X", como se muestra en pantalla.
    public var display: String { "\(value.prefix(3)) \(value.suffix(3))" }

    public var description: String { value }
}
