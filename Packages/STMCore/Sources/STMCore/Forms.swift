import Foundation

/// Validación del formulario de crear cuenta, antes de llamar al servidor.
public struct SignUpForm: Equatable, Sendable {
    public static let minimumPasswordLength = 10

    public var username = ""
    public var displayName = ""
    public var password = ""
    public var passwordConfirmation = ""

    public init(username: String = "", displayName: String = "", password: String = "", passwordConfirmation: String = "") {
        self.username = username
        self.displayName = displayName
        self.password = password
        self.passwordConfirmation = passwordConfirmation
    }

    public enum Issue: Equatable, Sendable {
        case username(Username.ValidationError)
        case passwordTooShort
        case passwordsDoNotMatch

        public var message: String {
            switch self {
            case .username(.tooShort): "El usuario necesita al menos 3 caracteres."
            case .username(.tooLong): "El usuario puede tener como mucho 30 caracteres."
            case .username(.invalidCharacters): "Usa solo letras sin tilde, números, punto, guion o guion bajo."
            case .passwordTooShort: "La contraseña necesita al menos \(SignUpForm.minimumPasswordLength) caracteres."
            case .passwordsDoNotMatch: "Las contraseñas no coinciden."
            }
        }
    }

    /// Primer problema que impide enviar el formulario, o nil si está bien.
    public var firstIssue: Issue? {
        do {
            _ = try Username(username)
        } catch {
            return .username(error)
        }
        if password.count < Self.minimumPasswordLength { return .passwordTooShort }
        if password != passwordConfirmation { return .passwordsDoNotMatch }
        return nil
    }

    public var trimmedDisplayName: String? {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : String(name.prefix(60))
    }
}

/// Nombre del hogar: entre 1 y 80 caracteres, sin espacios alrededor.
public enum HouseholdName {
    public static func validated(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(name.count) else { return nil }
        return name
    }
}
