import Foundation
import STMCore
import Supabase

/// Servicios de la app sobre Supabase. Toda la seguridad la pone el servidor
/// (RLS y funciones); aquí sólo se llama a la API y se traducen los errores.
public struct SupabaseBackend: AuthService, HouseholdService {
    let client: SupabaseClient

    public init(url: URL, anonKey: String) {
        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }

    // MARK: AuthService

    public func currentUserId() async -> UUID? {
        try? await client.auth.session.user.id
    }

    public func signUp(username: Username, password: String, displayName: String?) async throws -> UUID {
        var metadata: [String: AnyJSON] = ["username": .string(username.value)]
        if let displayName { metadata["display_name"] = .string(displayName) }
        return try await mapped {
            try await client.auth.signUp(email: username.authEmail, password: password, data: metadata).user.id
        }
    }

    public func signIn(username: Username, password: String) async throws -> UUID {
        try await mapped {
            try await client.auth.signIn(email: username.authEmail, password: password).user.id
        }
    }

    public func signOut() async throws {
        try await mapped { try await client.auth.signOut() }
    }

    // MARK: HouseholdService

    private static let profileColumns = "id,username,display_name,theme,default_household_id"
    private static let householdColumns = "id,name,base_currency,month_start_day"
    private static let inviteColumns = "id,household_id,code,status,expires_at"

    private func userId() async throws -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch {
            throw AppError.notSignedIn
        }
    }

    public func myProfile() async throws -> Profile {
        let id = try await userId()
        return try await mapped {
            try await client.from("profiles")
                .select(Self.profileColumns)
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value
        }
    }

    public func updateProfile(displayName: String?, theme: AppTheme) async throws -> Profile {
        let id = try await userId()
        let changes = ProfileChanges(displayName: displayName, theme: theme)
        return try await mapped {
            try await client.from("profiles")
                .update(changes)
                .eq("id", value: id.uuidString)
                .select(Self.profileColumns)
                .single()
                .execute()
                .value
        }
    }

    public func households() async throws -> [Household] {
        try await mapped {
            try await client.from("households")
                .select(Self.householdColumns)
                .order("created_at")
                .execute()
                .value
        }
    }

    public func createHousehold(name: String) async throws -> Household {
        try await mapped {
            try await client.rpc("create_household", params: ["household_name": name])
                .execute()
                .value
        }
    }

    public func members(of householdId: UUID) async throws -> [HouseholdMember] {
        try await mapped {
            let memberships: [Membership] = try await client.from("household_members")
                .select("id,household_id,user_id,role")
                .eq("household_id", value: householdId.uuidString)
                .execute()
                .value
            guard !memberships.isEmpty else { return [] }
            let profiles: [Profile] = try await client.from("profiles")
                .select(Self.profileColumns)
                .in("id", values: memberships.map(\.userId.uuidString))
                .execute()
                .value
            let byId = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            return memberships.compactMap { membership in
                byId[membership.userId].map { HouseholdMember(profile: $0, role: membership.role) }
            }
        }
    }

    public func pendingInvites(for householdId: UUID) async throws -> [HouseholdInvite] {
        let now = ISO8601DateFormatter().string(from: Date())
        return try await mapped {
            try await client.from("household_invites")
                .select(Self.inviteColumns)
                .eq("household_id", value: householdId.uuidString)
                .eq("status", value: InviteStatus.pending.rawValue)
                .gt("expires_at", value: now)
                .order("created_at", ascending: false)
                .execute()
                .value
        }
    }

    public func createInvite(for householdId: UUID) async throws -> HouseholdInvite {
        try await mapped {
            try await client.rpc("create_invite", params: ["target_household": householdId.uuidString])
                .execute()
                .value
        }
    }

    public func revokeInvite(_ inviteId: UUID) async throws {
        try await mapped {
            try await client.from("household_invites")
                .update(["status": InviteStatus.revoked.rawValue])
                .eq("id", value: inviteId.uuidString)
                .execute()
        }
    }

    public func acceptInvite(_ code: InviteCode) async throws -> Household {
        try await mapped {
            try await client.rpc("accept_invite", params: ["invite_code": code.value])
                .execute()
                .value
        }
    }

    public func leave(householdId: UUID) async throws {
        let id = try await userId()
        try await mapped {
            try await client.from("household_members")
                .delete()
                .eq("household_id", value: householdId.uuidString)
                .eq("user_id", value: id.uuidString)
                .execute()
        }
    }

    // MARK: Errores

    /// Ejecuta la llamada y convierte cualquier error en un AppError con mensaje en español.
    /// Nunca se registran datos del usuario: sólo el tipo de error.
    @discardableResult
    func mapped<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as AppError {
            throw error
        } catch let error as PostgrestError {
            throw Self.appError(postgresCode: error.code, message: error.message)
        } catch is URLError {
            throw AppError.network
        } catch {
            throw Self.appError(authMessage: String(describing: error))
        }
    }

    static func appError(postgresCode: String?, message: String) -> AppError {
        switch postgresCode {
        case "P0002": .invalidOrExpiredInvite
        case "23505": message.contains("already a member") ? .alreadyMember : .usernameTaken
        case "28000", "PGRST301": .notSignedIn
        case "23503", "23514", "22P02": .invalidInput("Algún dato no es válido. Revisa el formulario.")
        default: .unknown(postgresCode ?? "postgrest")
        }
    }

    static func appError(authMessage: String) -> AppError {
        let text = authMessage.lowercased()
        if text.contains("invalid login credentials") || text.contains("invalid_credentials") {
            return .invalidCredentials
        }
        if text.contains("already registered") || text.contains("user_already_exists") || text.contains("duplicate key") {
            return .usernameTaken
        }
        if text.contains("weak_password") || text.contains("password should be") {
            return .weakPassword
        }
        if text.contains("session") && (text.contains("missing") || text.contains("not found")) {
            return .notSignedIn
        }
        return .unknown("auth")
    }
}

private struct ProfileChanges: Encodable, Sendable {
    var displayName: String?
    var theme: AppTheme

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case theme
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Se envía null de forma explícita para poder borrar el nombre visible.
        try container.encode(displayName, forKey: .displayName)
        try container.encode(theme, forKey: .theme)
    }
}
