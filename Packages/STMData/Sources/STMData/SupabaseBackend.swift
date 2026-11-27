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

    /// La sesión guardada en el Llavero, aunque haya caducado: sin red no se puede renovar,
    /// pero sigue siendo de esta persona. Si el servidor la rechaza, supabase-swift la borra.
    public func currentUserId() async -> UUID? {
        client.auth.currentSession?.user.id
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

    /// supabase-swift 2.55.8 no envía `current_password` y el proyecto puede pedir un inicio de sesión
    /// reciente («secure password change»). Por eso se vuelve a iniciar sesión con la actual:
    /// la comprueba (con el límite de intentos del servidor) y deja una sesión nueva con la que el
    /// cambio vale con ese ajuste encendido o apagado. Si la actual no es, supabase-swift no toca la
    /// sesión guardada. Tras el cambio, el servidor cierra todas las demás sesiones de la cuenta.
    public func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let email = client.auth.currentSession?.user.email else { throw AppError.notSignedIn }
        do {
            _ = try await mapped { try await client.auth.signIn(email: email, password: currentPassword) }
        } catch AppError.invalidCredentials {
            throw AppError.wrongCurrentPassword
        }
        try await mapped { _ = try await client.auth.update(user: UserAttributes(password: newPassword)) }
    }

    public func deleteAccount(currentPassword: String) async throws {
        guard let email = client.auth.currentSession?.user.email else { throw AppError.notSignedIn }
        do {
            _ = try await mapped { try await client.auth.signIn(email: email, password: currentPassword) }
        } catch AppError.invalidCredentials {
            throw AppError.wrongCurrentPassword
        }
        try await mapped { try await client.rpc("delete_my_account").execute() }
        // El usuario ya no existe en el servidor: sólo queda quitar la sesión guardada en este dispositivo.
        try? await client.auth.signOut(scope: .local)
    }

    public func signOut() async throws {
        try await mapped { try await client.auth.signOut() }
    }

    // MARK: HouseholdService

    private static let profileColumns = "id,username,display_name,theme,default_household_id"
    private static let householdColumns = "id,name,base_currency,month_start_day"
    private static let inviteColumns = "id,household_id,code,status,expires_at"

    /// Renueva la sesión si ha caducado. Sólo es «sin sesión» si ya no hay ninguna guardada
    /// (no la había o el servidor la rechazó y supabase-swift la borró); si sigue guardada, el
    /// fallo es de red o del servidor y no debe mandar al login.
    private func userId() async throws -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch {
            guard client.auth.currentSession != nil else { throw AppError.notSignedIn }
            if !Task.isCancelled { ErrorLog.record(error, in: #function) }
            throw error is URLError ? AppError.network : AppError.unknown("auth")
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
        try await allRows {
            client.from("households")
                .select(Self.householdColumns)
                .order("created_at")
                .order("id")
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
        let memberships: [Membership] = try await allRows {
            client.from("household_members")
                .select("id,household_id,user_id,role")
                .eq("household_id", value: householdId.uuidString)
                .order("id")
        }
        guard !memberships.isEmpty else { return [] }
        let profiles: [Profile] = try await allRows {
            client.from("profiles")
                .select(Self.profileColumns)
                .in("id", values: memberships.map(\.userId.uuidString))
                .order("id")
        }
        let byId = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        return memberships.compactMap { membership in
            byId[membership.userId].map { HouseholdMember(profile: $0, role: membership.role) }
        }
    }

    public func pendingInvites(for householdId: UUID) async throws -> [HouseholdInvite] {
        let now = ISO8601DateFormatter().string(from: Date())
        return try await allRows {
            client.from("household_invites")
                .select(Self.inviteColumns)
                .eq("household_id", value: householdId.uuidString)
                .eq("status", value: InviteStatus.pending.rawValue)
                .gt("expires_at", value: now)
                .order("created_at", ascending: false)
                .order("id")
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
        // Un código que no sirve devuelve null en vez de un error, para que el servidor guarde el intento fallido.
        let joined: Household? = try await mapped {
            try await client.rpc("accept_invite", params: ["invite_code": code.value])
                .execute()
                .value
        }
        guard let joined else { throw AppError.invalidOrExpiredInvite }
        return joined
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

    public func renameHousehold(_ householdId: UUID, to name: String) async throws -> Household {
        guard let valid = HouseholdName.validated(name) else {
            throw AppError.invalidInput(String(localized: "El nombre del hogar tiene que tener entre 1 y 80 letras.", bundle: .module))
        }
        // RLS: sólo el dueño puede actualizar; si no lo es, no vuelve ninguna fila.
        let rows: [Household] = try await mapped {
            try await client.from("households")
                .update(["name": valid])
                .eq("id", value: householdId.uuidString)
                .select(Self.householdColumns)
                .execute()
                .value
        }
        return try Self.changedHousehold(rows, ownerOnly: Household.renameOwnerOnly)
    }

    public func setMonthStartDay(_ householdId: UUID, to day: Int) async throws -> Household {
        guard Household.monthStartDays.contains(day) else { throw AppError.invalidInput(Household.monthStartDayInvalid) }
        // RLS: sólo el dueño puede actualizar; si no lo es, no vuelve ninguna fila.
        let rows: [Household] = try await mapped {
            try await client.from("households")
                .update(["month_start_day": day])
                .eq("id", value: householdId.uuidString)
                .select(Self.householdColumns)
                .execute()
                .value
        }
        return try Self.changedHousehold(rows, ownerOnly: Household.monthStartDayOwnerOnly)
    }

    /// La fila que devuelve el servidor tras un cambio del hogar. Sin fila, el cambio no era del dueño (RLS).
    static func changedHousehold(_ rows: [Household], ownerOnly message: String) throws -> Household {
        guard let household = rows.first else { throw AppError.invalidInput(message) }
        return household
    }

    public func removeMember(_ userId: UUID, from householdId: UUID) async throws {
        try await mapped {
            try await client.from("household_members")
                .delete()
                .eq("household_id", value: householdId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()
        }
    }

    public func transferHousehold(_ householdId: UUID, to userId: UUID) async throws {
        try await mapped {
            try await client.rpc("transfer_household",
                                 params: ["target_household": householdId.uuidString, "new_owner": userId.uuidString])
                .execute()
        }
    }

    public func removedHouseholds() async throws -> [RemovedHousehold] {
        try await mapped {
            try await client.rpc("removed_households").execute().value
        }
    }

    public func removedHouseholdExport(_ householdId: UUID) async throws -> RemovedHouseholdExport {
        try await mapped {
            try await client.rpc("removed_household_export", params: ["target_household": householdId.uuidString])
                .execute()
                .value
        }
    }

    // MARK: Errores

    /// Ejecuta la llamada y convierte cualquier error en un AppError con mensaje en español.
    /// El fallo se registra antes de traducirlo (ORC-72), con `ErrorLog`: sin datos del usuario.
    @discardableResult
    func mapped<T>(_ function: String = #function, _ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as AppError {
            throw error
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { ErrorLog.record(error, in: function) }
            switch error {
            case let error as PostgrestError: throw Self.appError(postgresCode: error.code, message: error.message)
            case is URLError: throw AppError.network
            default: throw Self.appError(authMessage: String(describing: error))
            }
        }
    }

    // MARK: Altas y cambios con función (ORC-142)

    /// Llama a una función `create_…` o `update_…` y devuelve la fila guardada. Los parámetros van todos, también
    /// los nulos: las funciones de cambio no tienen valores por defecto.
    func saved<Row: Decodable & Sendable>(_ call: RpcCall, columns: String) async throws -> Row {
        let rows: [Row] = try await mapped(call.function) {
            try await client.rpc(call.function, params: call.params).select(columns).execute().value
        }
        guard let row = rows.first else { throw AppError.unknown(call.function) }
        return row
    }

    // MARK: Paginación

    /// Filas por petición: el servidor devuelve como mucho 1000 (`max_rows` en supabase/config.toml).
    static let pageSize = 1000

    /// Todas las filas de una consulta, pedidas por páginas. `query` crea la consulta de cada página
    /// y debe ordenar por una clave única (`id` al final) para que las páginas no salten ni repitan filas.
    /// Un error en cualquier página hace fallar la carga entera: nunca se devuelve una lista a medias.
    func allRows<Row: Decodable & Sendable>(
        _ function: String = #function, _ query: () -> PostgrestTransformBuilder
    ) async throws -> [Row] {
        try await Self.allPages { from, to in
            try await mapped(function) { try await query().range(from: from, to: to).execute().value }
        }
    }

    /// El bucle de `allRows`, aparte para probarlo sin servidor: pide páginas hasta que una llega incompleta.
    static func allPages<Row>(_ page: (_ from: Int, _ to: Int) async throws -> [Row]) async throws -> [Row] {
        var all: [Row] = []
        while true {
            let rows = try await page(all.count, all.count + pageSize - 1)
            all += rows
            if rows.count < pageSize { return all }
        }
    }

    /// Como `allPages`, pero cada página se pide a partir de la última fila de la anterior (cursor) y no con `range`:
    /// el servidor no vuelve a recorrer las páginas ya leídas, y un alta o un borrado a mitad de la carga no hace
    /// saltar ni repetir filas. `page` debe ordenar por una clave única y devolver como mucho `pageSize` filas.
    static func allPagesByCursor<Row>(_ page: (_ last: Row?) async throws -> [Row]) async throws -> [Row] {
        var all: [Row] = []
        while true {
            let rows = try await page(all.last)
            all += rows
            if rows.count < pageSize { return all }
        }
    }

    static func appError(postgresCode: String?, message: String) -> AppError {
        switch postgresCode {
        case "P0002": .invalidOrExpiredInvite
        case "23505":
            // profiles.username es único: Postgres nombra la restricción en el mensaje.
            if message.contains("already a member") { .alreadyMember } else if message.contains("categories_household_name_idx") {
                .invalidInput(String(localized: "Ya hay una categoría con ese nombre.", bundle: .module))
            } else if message.contains("profiles_username_key") { .usernameTaken } else {
                .invalidInput(String(localized: "Ya hay un registro igual guardado. Revisa el formulario.", bundle: .module))
            }
        case "28000", "PGRST301": .notSignedIn
        case "23503", "23514", "22P02": .invalidInput(String(localized: "Algún dato no es válido. Revisa el formulario.", bundle: .module))
        // create_transfer: la transferencia ya estaba guardada con otra cuenta, otro importe u otro día.
        case "STM01": .invalidInput(TransferDraft.storedWithOtherData)
        // El trigger de investment_trades: la posición quedaría en negativo en alguna fecha.
        case "STM02": .validation(.trade(.notEnoughShares))
        case "STM03": .validation(.trade(.neededByLaterSale))
        // accept_invite: demasiados códigos fallidos; el mensaje acaba en «retry in N min».
        // update_movement: el movimiento cambió (o se borró) después de leerlo.
        case "STM05": .movementChanged
        case "STM04": .tooManyInviteAttempts(minutes: message.split(separator: " ").lazy.compactMap { Int($0) }.first ?? 15)
        // El trigger de households: no se cambia base_currency con importes guardados.
        case "STM06": .invalidInput(Household.currencyLocked)
        // Transferencias: la otra pata no se pudo cambiar o borrar a la vez.
        case "STM07": .invalidInput(TransferDraft.otherLegLocked)
        // El trigger de household_members: el propietario no sale con otros miembros dentro.
        case "STM08": .invalidInput(LeavingHousehold.ownerMustTransfer)
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
        // Antes que «password should be»: el mensaje de same_password también lo contiene.
        if text.contains("same_password") || text.contains("should be different from the old") {
            return .invalidInput(ChangePasswordForm.Issue.samePassword.message)
        }
        if text.contains("weak_password") || text.contains("password should be") {
            return .weakPassword
        }
        if text.contains("over_request_rate_limit") || text.contains("rate limit") {
            return .tooManyAttempts
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

/// Una llamada a una función `create_…` o `update_…` del servidor: su nombre y sus parámetros. Las claves tienen que
/// ser exactamente los nombres de los parámetros de la función: PostgREST no encuentra la función si sobra o falta
/// alguno sin valor por defecto. `RpcEscriturasTests` las compara con `testdata/vectors/rpc_escrituras.json`, el
/// mismo fichero que usa `supabase/tests/api/escrituras_idempotentes.py` contra el PostgREST local.
struct RpcCall: Sendable {
    let function: String
    let params: [String: AnyJSON]
}

/// Valores para los parámetros de las funciones del servidor, con los nulos explícitos.
extension AnyJSON {
    static func uuid(_ value: UUID?) -> AnyJSON { value.map { .string($0.uuidString) } ?? .null }
    static func text(_ value: String?) -> AnyJSON { value.map { .string($0) } ?? .null }
    static func int(_ value: Int?) -> AnyJSON { value.map { .integer($0) } ?? .null }
    static func day(_ value: CalendarDay?) -> AnyJSON { value.map { .string($0.iso) } ?? .null }
    static func timestamp(_ value: Date?) -> AnyJSON { value.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null }
    /// Como texto, para no pasar por `Double`: Postgres lo convierte a `numeric` sin perder decimales.
    static func decimal(_ value: Decimal?) -> AnyJSON { value.map { .string(NSDecimalNumber(decimal: $0).stringValue) } ?? .null }
}
