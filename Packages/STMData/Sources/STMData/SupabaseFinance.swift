import Foundation
import STMCore
import Supabase

/// Cuentas, categorías y movimientos sobre Supabase. El RLS del servidor decide
/// qué se ve; aquí no se filtra por seguridad, sólo por lo que pide la pantalla.
extension SupabaseBackend: FinanceService {
    private static let accountColumns = "id,household_id,name,kind,currency,opening_balance_minor,owner_id,archived_at,is_default,include_in_net_worth,created_at,updated_at"
    private static let categoryColumns = "id,household_id,name,kind,budget_group,icon,updated_at"
    static let movementColumns = "id,household_id,account_id,category_id,booked_on,amount_minor,description,notes,import_hash,excluded,reviewed_at,payee,tags,updated_at,transfer_id"
    /// Filas por petición al importar, para no mandar un CSV enorme de golpe.
    private static let importBatchSize = 500

    public func accounts(in householdId: UUID) async throws -> [Account] {
        try await allRows {
            client.from("accounts")
                .select(Self.accountColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("created_at")
                .order("id")
        }
    }

    public func balances(in householdId: UUID) async throws -> [UUID: Money] {
        let rows: [BalanceRow] = try await allRows {
            client.from("account_balances")
                .select("account_id,balance_minor")
                .eq("household_id", value: householdId.uuidString)
                .order("account_id")
        }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.accountId, Money(minor: $0.balanceMinor)) })
    }

    public func createAccount(_ draft: AccountDraft, in householdId: UUID) async throws -> Account {
        if let issue = draft.issue { throw AppError.invalidInput(issue) }
        // `create_account` no repite una cuenta ya guardada con ese id: devuelve la que había.
        return try await saved("create_account", columns: Self.accountColumns, [
            "account": .uuid(draft.id), "household": .uuid(householdId), "label": .string(draft.trimmedName),
            "account_kind": .string(draft.kind.rawValue), "opening": .integer(draft.openingBalance.minor),
            "owner": .uuid(draft.ownerId)
        ])
    }

    public func updateAccount(_ account: Account) async throws -> Account {
        // `update_account` compara la versión y cambia la fila en la misma sentencia; si no coincide falla con STM05.
        try await saved("update_account", columns: Self.accountColumns, [
            "account": .uuid(account.id), "seen": .text(account.updatedAt),
            "label": .string(account.name.trimmingCharacters(in: .whitespacesAndNewlines)),
            "account_kind": .string(account.kind.rawValue), "opening": .integer(account.openingBalance.minor),
            "owner": .uuid(account.ownerId), "archived": .timestamp(account.archivedAt),
            "make_default": .bool(account.isDefault && !account.isArchived), "in_net_worth": .bool(account.includeInNetWorth)
        ])
    }

    public func deleteAccount(_ accountId: UUID) async throws {
        try await mapped {
            try await client.from("accounts")
                .delete()
                .eq("id", value: accountId.uuidString)
                .execute()
        }
    }

    public func categories(in householdId: UUID) async throws -> [BudgetCategory] {
        try await allRows {
            client.from("categories")
                .select(Self.categoryColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("name")
                .order("id")
        }
    }

    public func createCategory(_ category: BudgetCategory) async throws -> BudgetCategory {
        if let issue = category.issue(among: []) { throw AppError.invalidInput(issue) }
        // `create_category` no repite una categoría ya guardada con ese id: devuelve la que había.
        return try await saved("create_category", columns: Self.categoryColumns, [
            "category": .uuid(category.id), "household": .uuid(category.householdId), "label": .string(category.trimmedName),
            "category_kind": .string(category.kind.rawValue),
            "budget": .text(category.kind == .expense ? category.budgetGroup?.rawValue : nil), "icon_name": .text(category.icon)
        ])
    }

    public func updateCategory(_ category: BudgetCategory) async throws -> BudgetCategory {
        if let issue = category.issue(among: []) { throw AppError.invalidInput(issue) }
        // `update_category` compara la versión y cambia la fila en la misma sentencia; si no coincide falla con STM05.
        // Solo nombre, grupo e icono: el tipo de una categoría no se cambia.
        return try await saved("update_category", columns: Self.categoryColumns, [
            "category": .uuid(category.id), "seen": .text(category.updatedAt), "label": .string(category.trimmedName),
            "budget": .text(category.kind == .expense ? category.budgetGroup?.rawValue : nil), "icon_name": .text(category.icon)
        ])
    }

    public func deleteCategory(_ categoryId: UUID) async throws {
        try await mapped {
            try await client.from("categories")
                .delete()
                .eq("id", value: categoryId.uuidString)
                .execute()
        }
    }

    public func resetHousehold(_ householdId: UUID) async throws {
        try await mapped {
            try await client.rpc("reset_household", params: ["target_household": householdId.uuidString])
                .execute()
        }
    }

    public func movements(in householdId: UUID, accountId: UUID?, limit: Int) async throws -> [Movement] {
        try await mapped {
            var query = client.from("transactions")
                .select(Self.movementColumns)
                .eq("household_id", value: householdId.uuidString)
            if let accountId {
                query = query.eq("account_id", value: accountId.uuidString)
            }
            return try await query
                .order("booked_on", ascending: false)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
        }
    }

    /// Páginas por cursor (día e id de la última fila) y no por `range`: si entra o se borra un movimiento entre
    /// página y página, la siguiente no repite ni se salta filas.
    public func movements(in householdId: UUID, accountId: UUID?, search: MovementSearch?, after: Movement?,
                          limit: Int) async throws -> [Movement] {
        try await mapped {
            var query = client.from("transactions")
                .select(Self.movementColumns)
                .eq("household_id", value: householdId.uuidString)
            if let accountId {
                query = query.eq("account_id", value: accountId.uuidString)
            }
            if let search {
                query = query.or(Self.searchFilter(search))
            }
            if let after {
                query = query.or(Self.afterFilter(after))
            }
            return try await query
                .order("booked_on", ascending: false)
                .order("id", ascending: false)
                .limit(limit)
                .execute()
                .value
        }
    }

    /// Lo que va dentro de `or=(…)` para buscar. El texto del usuario va siempre entre comillas (así comas, puntos,
    /// paréntesis y dos puntos no son sintaxis de PostgREST) y con los comodines de LIKE escapados. La etiqueta, los
    /// ids y el importe no llevan nada que escapar: sólo letras, números, «-», «_» o un entero.
    static func searchFilter(_ search: MovementSearch) -> String {
        let pattern = quoted("*" + likeEscaped(search.text) + "*")
        var parts = ["description", "notes", "payee"].map { "\($0).ilike.\(pattern)" }
        if let tag = search.tag { parts.append("tags.cs.{\(tag)}") }
        if !search.categoryIds.isEmpty {
            parts.append("category_id.in.(\(search.categoryIds.map { $0.uuidString.lowercased() }.joined(separator: ",")))")
        }
        if let amount = search.amount {
            parts.append(search.signedAmount ? "amount_minor.eq.\(amount.minor)"
                                             : "amount_minor.in.(\(abs(amount.minor)),\(-abs(amount.minor)))")
        }
        return parts.joined(separator: ",")
    }

    /// Las filas que van detrás de `after` en el orden de la lista: un día anterior, o el mismo día y un id menor.
    static func afterFilter(_ after: Movement) -> String {
        "booked_on.lt.\(after.bookedOn.iso),and(booked_on.eq.\(after.bookedOn.iso),id.lt.\(after.id.uuidString.lowercased()))"
    }

    /// `\`, `%` y `_` se buscan tal cual. PostgREST convierte cada `*` en `%` y no deja escaparlo, así que un `*`
    /// escrito cuenta como «un carácter cualquiera» (`_`): encuentra lo mismo y algo más, nunca menos.
    static func likeEscaped(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "\\", "%", "_": result += "\\" + String(character)
            case "*": result += "_"
            default: result.append(character)
            }
        }
        return result
    }

    /// Un valor entre comillas dobles para un filtro de PostgREST: dentro, `\` y `"` van con `\` delante.
    static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    public func movements(in householdId: UUID, ids: [UUID]) async throws -> [Movement] {
        guard !ids.isEmpty else { return [] }
        return try await allRows {
            client.from("transactions")
                .select(Self.movementColumns)
                .eq("household_id", value: householdId.uuidString)
                .in("id", values: ids.map(\.uuidString))
                .order("id")
        }
    }

    public func movements(in householdId: UUID, accountId: UUID, since: CalendarDay, limit: Int) async throws -> [Movement] {
        try await mapped {
            try await client.from("transactions")
                .select(Self.movementColumns)
                .eq("household_id", value: householdId.uuidString)
                .eq("account_id", value: accountId.uuidString)
                .gte("booked_on", value: since.iso)
                .order("booked_on", ascending: false)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
        }
    }

    public func allMovements(in householdId: UUID) async throws -> [Movement] {
        try await allRows {
            client.from("transactions")
                .select(Self.movementColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("booked_on")
                .order("id")
        }
    }

    /// `create_movement` no repite un movimiento ya guardado con ese id: devuelve el que había.
    public func addMovement(_ draft: MovementDraft, in householdId: UUID) async throws -> Movement {
        if let issue = draft.issue { throw AppError.invalidInput(issue) }
        let rows: [Movement] = try await mapped {
            try await client.rpc("create_movement", params: MovementParams(draft, householdId: householdId))
                .select(Self.movementColumns)
                .execute()
                .value
        }
        guard let saved = rows.first else { throw AppError.unknown("create_movement") }
        return saved
    }

    /// `create_transfer` guarda las dos patas en una sola transacción y no repite una ya guardada.
    public func addTransfer(_ transfer: TransferDraft, in householdId: UUID) async throws -> [Movement] {
        if let issue = transfer.issue { throw AppError.invalidInput(issue) }
        return try await mapped {
            try await client.rpc("create_transfer", params: TransferParams(transfer, householdId: householdId))
                .select(Self.movementColumns)
                .execute()
                .value
        }
    }

    public func updateMovement(_ movement: Movement) async throws -> Movement {
        let draft = MovementDraft(accountId: movement.accountId, categoryId: movement.categoryId, bookedOn: movement.bookedOn,
                                  amount: movement.amount, description: movement.description, notes: movement.notes,
                                  excluded: movement.excluded, payee: movement.payee, tags: movement.tags)
        if let issue = draft.issue { throw AppError.invalidInput(issue) }
        // `update_movement` compara la versión y cambia la fila en la misma sentencia; si no coincide falla con STM05.
        let rows: [Movement] = try await mapped {
            try await client.rpc("update_movement", params: MovementChanges(movement))
                .select(Self.movementColumns)
                .execute()
                .value
        }
        guard let saved = rows.first else { throw AppError.movementChanged }
        return saved
    }

    public func deleteMovement(_ movementId: UUID) async throws {
        try await mapped {
            try await client.from("transactions")
                .delete()
                .eq("id", value: movementId.uuidString)
                .execute()
        }
    }

    /// `delete_transfer` borra las dos patas en una sola transacción, o ninguna (STM07).
    public func deleteTransfer(_ transferId: UUID) async throws {
        try await mapped {
            try await client.rpc("delete_transfer", params: ["transfer": transferId.uuidString]).execute()
        }
    }

    public func importMovements(_ drafts: [MovementDraft], in householdId: UUID) async throws -> ImportResult {
        if let issue = drafts.lazy.compactMap(\.issue).first { throw AppError.invalidInput(issue) }
        var inserted = 0
        for start in stride(from: 0, to: drafts.count, by: Self.importBatchSize) {
            let batch = drafts[start..<min(start + Self.importBatchSize, drafts.count)]
                .map { NewMovementRow($0, householdId: householdId) }
            // ON CONFLICT (account_id, import_hash) DO NOTHING: sólo vuelven las filas nuevas.
            let rows: [IdRow] = try await mapped {
                try await client.from("transactions")
                    .upsert(batch, onConflict: "account_id,import_hash", ignoreDuplicates: true)
                    .select("id")
                    .execute()
                    .value
            }
            inserted += rows.count
        }
        return ImportResult(inserted: inserted, duplicates: drafts.count - inserted)
    }
}

// MARK: Filas que se envían. Nunca llevan id, household_id en updates ni created_by:
// el servidor no deja escribirlos.

private struct BalanceRow: Decodable {
    var accountId: UUID
    var balanceMinor: Int

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case balanceMinor = "balance_minor"
    }
}

private struct IdRow: Decodable {
    var id: UUID
}

/// Parámetros de `create_transfer`. La categoría se manda aunque sea nula: la función no tiene valor por defecto.
private struct TransferParams: Encodable, Sendable {
    var transfer: UUID
    var household: UUID
    var fromAccount: UUID
    var toAccount: UUID
    var booked: CalendarDay
    var amount: Int
    var category: UUID?
    var fromLabel: String
    var toLabel: String

    init(_ draft: TransferDraft, householdId: UUID) {
        transfer = draft.id
        household = householdId
        fromAccount = draft.fromAccountId
        toAccount = draft.toAccountId
        booked = draft.bookedOn
        amount = draft.amount.minor
        category = draft.categoryId
        fromLabel = draft.fromDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        toLabel = draft.toDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(transfer, forKey: .transfer)
        try c.encode(household, forKey: .household)
        try c.encode(fromAccount, forKey: .fromAccount)
        try c.encode(toAccount, forKey: .toAccount)
        try c.encode(booked, forKey: .booked)
        try c.encode(amount, forKey: .amount)
        try c.encode(category, forKey: .category)
        try c.encode(fromLabel, forKey: .fromLabel)
        try c.encode(toLabel, forKey: .toLabel)
    }

    private enum CodingKeys: String, CodingKey {
        case transfer, household, booked, amount, category
        case fromAccount = "from_account"
        case toAccount = "to_account"
        case fromLabel = "from_label"
        case toLabel = "to_label"
    }
}

/// Parámetros de `create_movement`. La categoría se manda aunque sea nula: la función no tiene valor por defecto.
private struct MovementParams: Encodable, Sendable {
    var draft: MovementDraft
    var householdId: UUID

    init(_ draft: MovementDraft, householdId: UUID) {
        self.draft = draft
        self.householdId = householdId
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(draft.id, forKey: .movement)
        try c.encode(householdId, forKey: .household)
        try c.encode(draft.accountId, forKey: .account)
        try c.encode(draft.categoryId, forKey: .category)
        try c.encode(draft.bookedOn, forKey: .booked)
        try c.encode(draft.amount.minor, forKey: .amount)
        try c.encode(draft.description.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .label)
        try c.encode(draft.notes, forKey: .note)
        try c.encode(draft.excluded, forKey: .isExcluded)
        try c.encode(Payee.clean(draft.payee), forKey: .payeeName)
        try c.encode(draft.tags, forKey: .tagList)
    }

    private enum CodingKeys: String, CodingKey {
        case movement, household, account, category, booked, amount, label, note
        case isExcluded = "is_excluded"
        case payeeName = "payee_name"
        case tagList = "tag_list"
    }
}

private struct NewMovementRow: Encodable, Sendable {
    var householdId: UUID
    var accountId: UUID
    var categoryId: UUID?
    var bookedOn: CalendarDay
    var amountMinor: Int
    var description: String
    var notes: String?
    var importHash: String?
    var excluded: Bool
    var payee: String?
    var tags: [String]

    init(_ draft: MovementDraft, householdId: UUID) {
        excluded = draft.excluded
        payee = Payee.clean(draft.payee)
        tags = draft.tags
        self.householdId = householdId
        accountId = draft.accountId
        categoryId = draft.categoryId
        bookedOn = draft.bookedOn
        amountMinor = draft.amount.minor
        description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        notes = draft.notes
        importHash = draft.importHash
    }

    enum CodingKeys: String, CodingKey {
        case description, notes
        case householdId = "household_id"
        case accountId = "account_id"
        case categoryId = "category_id"
        case bookedOn = "booked_on"
        case amountMinor = "amount_minor"
        case importHash = "import_hash"
        case excluded, payee, tags
    }

    // Todas las filas de un lote deben llevar las mismas claves para PostgREST,
    // así que los opcionales se mandan como null en vez de omitirse.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(householdId, forKey: .householdId)
        try c.encode(accountId, forKey: .accountId)
        try c.encode(categoryId, forKey: .categoryId)
        try c.encode(bookedOn, forKey: .bookedOn)
        try c.encode(amountMinor, forKey: .amountMinor)
        try c.encode(description, forKey: .description)
        try c.encode(notes, forKey: .notes)
        try c.encode(importHash, forKey: .importHash)
        try c.encode(excluded, forKey: .excluded)
        try c.encode(payee, forKey: .payee)
        try c.encode(tags, forKey: .tags)
    }
}

/// Parámetros de `update_movement`. Todos van siempre, también los nulos: la función no tiene valores por defecto.
private struct MovementChanges: Encodable, Sendable {
    var movement: Movement

    init(_ movement: Movement) { self.movement = movement }

    enum CodingKeys: String, CodingKey {
        case movement, seen, account, category, booked, amount, label, note, reviewed
        case isExcluded = "is_excluded"
        case payeeName = "payee_name"
        case tagList = "tag_list"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(movement.id, forKey: .movement)
        // El `updated_at` tal cual llegó del servidor: es la versión que se leyó.
        try c.encode(movement.updatedAt, forKey: .seen)
        try c.encode(movement.accountId, forKey: .account)
        try c.encode(movement.categoryId, forKey: .category)
        try c.encode(movement.bookedOn, forKey: .booked)
        try c.encode(movement.amount.minor, forKey: .amount)
        try c.encode(movement.description.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .label)
        try c.encode(movement.notes, forKey: .note)
        try c.encode(movement.excluded, forKey: .isExcluded)
        try c.encode(movement.reviewedAt.map { ISO8601DateFormatter().string(from: $0) }, forKey: .reviewed)
        try c.encode(Payee.clean(movement.payee), forKey: .payeeName)
        try c.encode(movement.tags, forKey: .tagList)
    }
}
