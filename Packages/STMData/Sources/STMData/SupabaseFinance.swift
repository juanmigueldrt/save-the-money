import Foundation
import STMCore
import Supabase

/// Cuentas, categorías y movimientos sobre Supabase. El RLS del servidor decide
/// qué se ve; aquí no se filtra por seguridad, sólo por lo que pide la pantalla.
extension SupabaseBackend: FinanceService {
    private static let accountColumns = "id,household_id,name,kind,currency,opening_balance_minor,owner_id,archived_at,is_default,include_in_net_worth"
    private static let categoryColumns = "id,household_id,name,kind,budget_group,icon"
    static let movementColumns = "id,household_id,account_id,category_id,booked_on,amount_minor,description,notes,import_hash,excluded,reviewed_at,payee,tags"
    /// Filas por petición al importar, para no mandar un CSV enorme de golpe.
    private static let importBatchSize = 500

    public func accounts(in householdId: UUID) async throws -> [Account] {
        try await mapped {
            try await client.from("accounts")
                .select(Self.accountColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("created_at")
                .execute()
                .value
        }
    }

    public func balances(in householdId: UUID) async throws -> [UUID: Money] {
        let rows: [BalanceRow] = try await mapped {
            try await client.from("account_balances")
                .select("account_id,balance_minor")
                .eq("household_id", value: householdId.uuidString)
                .execute()
                .value
        }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.accountId, Money(minor: $0.balanceMinor)) })
    }

    public func createAccount(_ draft: AccountDraft, in householdId: UUID) async throws -> Account {
        if let issue = draft.issue { throw AppError.invalidInput(issue) }
        let row = NewAccountRow(householdId: householdId, name: draft.trimmedName, kind: draft.kind,
                                openingBalanceMinor: draft.openingBalance.minor, ownerId: draft.ownerId)
        return try await mapped {
            try await client.from("accounts")
                .insert(row)
                .select(Self.accountColumns)
                .single()
                .execute()
                .value
        }
    }

    public func updateAccount(_ account: Account) async throws -> Account {
        let changes = AccountChanges(account)
        return try await mapped {
            try await client.from("accounts")
                .update(changes)
                .eq("id", value: account.id.uuidString)
                .select(Self.accountColumns)
                .single()
                .execute()
                .value
        }
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
        try await mapped {
            try await client.from("categories")
                .select(Self.categoryColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("name")
                .execute()
                .value
        }
    }

    public func createCategory(_ category: BudgetCategory) async throws -> BudgetCategory {
        if let issue = category.issue(among: []) { throw AppError.invalidInput(issue) }
        return try await mapped {
            try await client.from("categories")
                .insert(CategoryRow(category, includeHousehold: true))
                .select(Self.categoryColumns)
                .single()
                .execute()
                .value
        }
    }

    public func updateCategory(_ category: BudgetCategory) async throws -> BudgetCategory {
        if let issue = category.issue(among: []) { throw AppError.invalidInput(issue) }
        return try await mapped {
            try await client.from("categories")
                .update(CategoryRow(category, includeHousehold: false))
                .eq("id", value: category.id.uuidString)
                .select(Self.categoryColumns)
                .single()
                .execute()
                .value
        }
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

    public func movements(in householdId: UUID, ids: [UUID]) async throws -> [Movement] {
        guard !ids.isEmpty else { return [] }
        return try await mapped {
            try await client.from("transactions")
                .select(Self.movementColumns)
                .eq("household_id", value: householdId.uuidString)
                .in("id", values: ids.map(\.uuidString))
                .execute()
                .value
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
        // El servidor devuelve como mucho 1000 filas por petición (max_rows).
        let pageSize = 1000
        var all: [Movement] = []
        while true {
            let start = all.count
            let page: [Movement] = try await mapped {
                try await client.from("transactions")
                    .select(Self.movementColumns)
                    .eq("household_id", value: householdId.uuidString)
                    .order("booked_on")
                    .order("id")
                    .range(from: start, to: start + pageSize - 1)
                    .execute()
                    .value
            }
            all += page
            if page.count < pageSize { return all }
        }
    }

    public func addMovement(_ draft: MovementDraft, in householdId: UUID) async throws -> Movement {
        if let issue = draft.issue { throw AppError.invalidInput(issue) }
        return try await mapped {
            try await client.from("transactions")
                .insert(NewMovementRow(draft, householdId: householdId))
                .select(Self.movementColumns)
                .single()
                .execute()
                .value
        }
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
        return try await mapped {
            try await client.from("transactions")
                .update(MovementChanges(movement))
                .eq("id", value: movement.id.uuidString)
                .select(Self.movementColumns)
                .single()
                .execute()
                .value
        }
    }

    public func deleteMovement(_ movementId: UUID) async throws {
        try await mapped {
            try await client.from("transactions")
                .delete()
                .eq("id", value: movementId.uuidString)
                .execute()
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

private struct NewAccountRow: Encodable, Sendable {
    var householdId: UUID
    var name: String
    var kind: AccountKind
    var openingBalanceMinor: Int
    var ownerId: UUID?

    enum CodingKeys: String, CodingKey {
        case name, kind
        case householdId = "household_id"
        case openingBalanceMinor = "opening_balance_minor"
        case ownerId = "owner_id"
    }
}

private struct AccountChanges: Encodable, Sendable {
    var name: String
    var kind: AccountKind
    var openingBalanceMinor: Int
    var ownerId: UUID?
    var archivedAt: String?
    var isDefault: Bool
    var includeInNetWorth: Bool

    init(_ account: Account) {
        isDefault = account.isDefault && !account.isArchived
        includeInNetWorth = account.includeInNetWorth
        name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        kind = account.kind
        openingBalanceMinor = account.openingBalance.minor
        ownerId = account.ownerId
        archivedAt = account.archivedAt.map { ISO8601DateFormatter().string(from: $0) }
    }

    enum CodingKeys: String, CodingKey {
        case name, kind
        case openingBalanceMinor = "opening_balance_minor"
        case ownerId = "owner_id"
        case archivedAt = "archived_at"
        case isDefault = "is_default"
        case includeInNetWorth = "include_in_net_worth"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(openingBalanceMinor, forKey: .openingBalanceMinor)
        // null explícito para poder volver a compartida o desarchivar.
        try c.encode(ownerId, forKey: .ownerId)
        try c.encode(archivedAt, forKey: .archivedAt)
        try c.encode(isDefault, forKey: .isDefault)
        try c.encode(includeInNetWorth, forKey: .includeInNetWorth)
    }
}

/// Columnas de una categoría que se pueden escribir. Al insertar va el hogar y el tipo;
/// al cambiarla, sólo nombre, grupo e icono (es lo que permite el servidor).
private struct CategoryRow: Encodable, Sendable {
    var category: BudgetCategory
    var includeHousehold: Bool

    init(_ category: BudgetCategory, includeHousehold: Bool) {
        self.category = category
        self.includeHousehold = includeHousehold
    }

    enum CodingKeys: String, CodingKey {
        case name, kind, icon
        case householdId = "household_id"
        case budgetGroup = "budget_group"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if includeHousehold {
            try c.encode(category.householdId, forKey: .householdId)
            try c.encode(category.kind, forKey: .kind)
        }
        try c.encode(category.trimmedName, forKey: .name)
        try c.encode(category.kind == .expense ? category.budgetGroup : nil, forKey: .budgetGroup)
        try c.encode(category.icon, forKey: .icon)
    }
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

private struct MovementChanges: Encodable, Sendable {
    var movement: Movement

    init(_ movement: Movement) { self.movement = movement }

    enum CodingKeys: String, CodingKey {
        case description, notes, excluded, payee, tags
        case accountId = "account_id"
        case categoryId = "category_id"
        case bookedOn = "booked_on"
        case amountMinor = "amount_minor"
        case reviewedAt = "reviewed_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(movement.accountId, forKey: .accountId)
        try c.encode(movement.categoryId, forKey: .categoryId)
        try c.encode(movement.bookedOn, forKey: .bookedOn)
        try c.encode(movement.amount.minor, forKey: .amountMinor)
        try c.encode(movement.description.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .description)
        try c.encode(movement.notes, forKey: .notes)
        try c.encode(movement.excluded, forKey: .excluded)
        try c.encode(movement.reviewedAt.map { ISO8601DateFormatter().string(from: $0) }, forKey: .reviewedAt)
        try c.encode(Payee.clean(movement.payee), forKey: .payee)
        try c.encode(movement.tags, forKey: .tags)
    }
}
