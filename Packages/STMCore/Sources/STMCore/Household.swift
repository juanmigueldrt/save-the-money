import Foundation

/// Hogar compartido. Todo dato de la app cuelga de uno.
public struct Household: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var baseCurrency: String
    public var monthStartDay: Int

    public init(id: UUID = UUID(), name: String, baseCurrency: String = "EUR", monthStartDay: Int = 1) {
        self.id = id
        self.name = name
        self.baseCurrency = baseCurrency
        self.monthStartDay = monthStartDay
    }

    /// El servidor no deja cambiar la moneda de un hogar que ya tiene importes (ORC-71): no se convierten.
    public static let currencyLocked =
        "No se puede cambiar la moneda del hogar mientras tenga cuentas, presupuestos u otros importes guardados."

    /// Días en que puede empezar el mes del hogar: del 1 al 28, que existen en todos los meses (igual que el servidor).
    public static let monthStartDays = 1...28
    public static let monthStartDayInvalid = "El mes del hogar puede empezar entre el día 1 y el 28."
    public static let monthStartDayOwnerOnly = "Solo quien creó el hogar puede cambiar el día en que empieza el mes."
    public static let renameOwnerOnly = "Solo quien creó el hogar puede cambiarle el nombre."

    enum CodingKeys: String, CodingKey {
        case id, name
        case baseCurrency = "base_currency"
        case monthStartDay = "month_start_day"
    }
}

public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    public var title: String {
        switch self {
        case .system: "Automático"
        case .light: "Claro"
        case .dark: "Oscuro"
        }
    }
}

public struct Profile: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var username: String
    public var displayName: String?
    public var theme: AppTheme
    public var defaultHouseholdId: UUID?

    public init(id: UUID = UUID(), username: String, displayName: String? = nil,
                theme: AppTheme = .system, defaultHouseholdId: UUID? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.theme = theme
        self.defaultHouseholdId = defaultHouseholdId
    }

    /// Nombre para mostrar: el visible si lo hay, si no el de usuario.
    public var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return username
    }

    enum CodingKeys: String, CodingKey {
        case id, username, theme
        case displayName = "display_name"
        case defaultHouseholdId = "default_household_id"
    }
}

public enum MemberRole: String, Codable, Sendable {
    case owner, member

    public var title: String { self == .owner ? "Propietario" : "Miembro" }
}

/// Fila de household_members.
public struct Membership: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var householdId: UUID
    public var userId: UUID
    public var role: MemberRole

    public init(id: UUID = UUID(), householdId: UUID, userId: UUID, role: MemberRole) {
        self.id = id
        self.householdId = householdId
        self.userId = userId
        self.role = role
    }

    enum CodingKeys: String, CodingKey {
        case id, role
        case householdId = "household_id"
        case userId = "user_id"
    }
}

/// Miembro tal como se muestra: su perfil y su papel en el hogar.
public struct HouseholdMember: Identifiable, Hashable, Sendable {
    public var profile: Profile
    public var role: MemberRole

    public init(profile: Profile, role: MemberRole) {
        self.profile = profile
        self.role = role
    }

    public var id: UUID { profile.id }
}

public enum InviteStatus: String, Codable, Sendable {
    case pending, accepted, revoked
}

public struct HouseholdInvite: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var householdId: UUID
    public var code: String
    public var status: InviteStatus
    public var expiresAt: Date

    public init(id: UUID = UUID(), householdId: UUID, code: String,
                status: InviteStatus = .pending, expiresAt: Date) {
        self.id = id
        self.householdId = householdId
        self.code = code
        self.status = status
        self.expiresAt = expiresAt
    }

    public var inviteCode: InviteCode? { InviteCode(code) }

    public func isUsable(at now: Date = Date()) -> Bool {
        status == .pending && expiresAt > now
    }

    enum CodingKeys: String, CodingKey {
        case id, code, status
        case householdId = "household_id"
        case expiresAt = "expires_at"
    }
}

/// Un hogar del que te han quitado (ORC-56). Tus datos de ese hogar se guardan hasta `exportUntil`
/// para que puedas exportarlos; después se borran.
public struct RemovedHousehold: Identifiable, Hashable, Codable, Sendable {
    public var householdId: UUID
    public var name: String
    public var exportUntil: Date

    public var id: UUID { householdId }

    /// Días de plazo, los mismos que en el servidor (`private.removed_until`).
    public static let exportDays = 30

    public init(householdId: UUID, name: String, exportUntil: Date) {
        self.householdId = householdId
        self.name = name
        self.exportUntil = exportUntil
    }

    enum CodingKeys: String, CodingKey {
        case name
        case householdId = "household_id"
        case exportUntil = "export_until"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        name = try c.decode(String.self, forKey: .name)
        exportUntil = try c.decode(ServerDate.self, forKey: .exportUntil).date
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(householdId, forKey: .householdId)
        try c.encode(name, forKey: .name)
        try c.encode(ServerDate(exportUntil), forKey: .exportUntil)
    }
}

/// Lo que puede llevarse quien ha sido quitado de un hogar: sus movimientos, con sus cuentas y categorías
/// para poner los nombres en el CSV.
public struct RemovedHouseholdExport: Hashable, Decodable, Sendable {
    public var accounts: [Account]
    public var categories: [BudgetCategory]
    public var movements: [Movement]

    public init(accounts: [Account], categories: [BudgetCategory], movements: [Movement]) {
        self.accounts = accounts
        self.categories = categories
        self.movements = movements
    }
}

public enum LeavingHousehold {
    /// Lo que la app avisa antes de salir de un hogar.
    public static let leaveWarning =
        "Se borrará todo lo que has apuntado en este hogar: cuentas, movimientos, presupuestos, metas, tarjetas, "
        + "inversiones y pagos fijos. No se puede deshacer. Si quieres conservar tus movimientos, expórtalos antes con «Exportar CSV para Excel», en Más opciones."
    /// Lo que la app avisa antes de quitar a un miembro.
    public static let removeWarning =
        "Dejará de tener acceso a este hogar. Sus datos se guardan \(RemovedHousehold.exportDays) días para que pueda "
        + "exportarlos y después se borran. Si le vuelves a invitar antes, los recupera."
}
