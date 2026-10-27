import Foundation

/// Nombre de usuario para iniciar sesión. Supabase Auth necesita un email, así que
/// cada usuario se registra con un email sintético que nunca recibe correo
/// (el dominio `.invalid` está reservado y no existe).
public struct Username: Hashable, Codable, Sendable, CustomStringConvertible {
    public static let authEmailDomain = "savethemoney.invalid"
    public static let allowedLength = 3...30

    public let value: String

    public enum ValidationError: Error, Equatable, Sendable {
        case tooShort, tooLong, invalidCharacters
    }

    /// Normaliza (minúsculas, sin espacios alrededor) y valida: letras a-z, números, ".", "_" y "-".
    public init(_ raw: String) throws(ValidationError) {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count >= Self.allowedLength.lowerBound else { throw .tooShort }
        guard normalized.count <= Self.allowedLength.upperBound else { throw .tooLong }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
        guard normalized.allSatisfy(allowed.contains) else { throw .invalidCharacters }
        value = normalized
    }

    /// Email con el que se registra en Supabase Auth.
    public var authEmail: String { "\(value)@\(Self.authEmailDomain)" }

    public var description: String { value }
}
