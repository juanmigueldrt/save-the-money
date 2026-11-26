import Foundation

/// Nombre de usuario para iniciar sesión. Supabase Auth necesita un email, así que
/// cada usuario se registra con un email sintético que nunca recibe correo
/// (el dominio `.invalid` está reservado y no existe).
public struct Username: Hashable, Codable, Sendable, CustomStringConvertible {
    public static let authEmailDomain = "savethemoney.invalid"
    public static let allowedLength = 3...30

    public let value: String

    public enum ValidationError: Error, Equatable, Sendable {
        case tooShort, tooLong, invalidCharacters, invalidEdges
    }

    /// Normaliza (minúsculas, sin espacios alrededor) y valida: letras a-z, números, ".", "_" y "-".
    /// Al crear una cuenta (por defecto) también empieza y termina en letra o número; al iniciar sesión
    /// (`forSignIn`) no, porque hay cuentas creadas antes de esa regla y el servidor las acepta.
    public init(_ raw: String, forSignIn: Bool = false) throws(ValidationError) {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count >= Self.allowedLength.lowerBound else { throw .tooShort }
        guard normalized.count <= Self.allowedLength.upperBound else { throw .tooLong }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
        guard normalized.allSatisfy(allowed.contains) else { throw .invalidCharacters }
        if !forSignIn {
            let alphanumeric = Set("abcdefghijklmnopqrstuvwxyz0123456789")
            guard let first = normalized.first, let last = normalized.last,
                  alphanumeric.contains(first), alphanumeric.contains(last) else { throw .invalidEdges }
        }
        value = normalized
    }

    /// Email con el que se registra en Supabase Auth.
    public var authEmail: String { "\(value)@\(Self.authEmailDomain)" }

    public var description: String { value }
}
