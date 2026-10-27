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
