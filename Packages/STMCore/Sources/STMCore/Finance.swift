import Foundation

public enum AccountKind: String, Codable, CaseIterable, Sendable {
    case checking, savings, creditCard = "credit_card", cash, investment, loan, other

    public var title: String {
        switch self {
        case .checking: "Cuenta corriente"
        case .savings: "Ahorro"
        case .creditCard: "Tarjeta de crédito"
        case .cash: "Efectivo"
        case .investment: "Inversión"
        case .loan: "Préstamo"
        case .other: "Otra"
        }
    }

    public var systemImage: String {
        switch self {
        case .checking: "building.columns"
        case .savings: "banknote"
        case .creditCard: "creditcard"
        case .cash: "eurosign"
        case .investment: "chart.line.uptrend.xyaxis"
        case .loan: "doc.text"
        case .other: "wallet.pass"
        }
    }

    /// Tarjetas y préstamos son deudas: su saldo suele ser negativo.
    public var isLiability: Bool { self == .creditCard || self == .loan }
}

/// Cuenta de un hogar. `ownerId` nil significa compartida.
public struct Account: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var householdId: UUID
    public var name: String
    public var kind: AccountKind
    public var currency: String
    public var openingBalance: Money
    public var ownerId: UUID?
    public var archivedAt: Date?
    /// Cuándo se dio de alta (`created_at`): el saldo inicial es el que tenía ese día.
    /// Nil si no se sabe (cuentas en memoria): entonces el saldo inicial cuenta desde siempre.
    public var createdAt: Date?
    /// La que sale elegida al apuntar un movimiento.
    public var isDefault: Bool
    /// Si suma en el patrimonio neto.
    public var includeInNetWorth: Bool

    public init(id: UUID = UUID(), householdId: UUID, name: String, kind: AccountKind = .checking,
                currency: String = "EUR", openingBalance: Money = .zero, ownerId: UUID? = nil,
                archivedAt: Date? = nil, isDefault: Bool = false, includeInNetWorth: Bool = true,
                createdAt: Date? = nil) {
        self.id = id
        self.householdId = householdId
        self.name = name
        self.kind = kind
        self.currency = currency
        self.openingBalance = openingBalance
        self.ownerId = ownerId
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.isDefault = isDefault
        self.includeInNetWorth = includeInNetWorth
    }

    public var isArchived: Bool { archivedAt != nil }
    public var isShared: Bool { ownerId == nil }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, currency
        case householdId = "household_id"
        case openingBalanceMinor = "opening_balance_minor"
        case ownerId = "owner_id"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case isDefault = "is_default"
        case includeInNetWorth = "include_in_net_worth"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(AccountKind.self, forKey: .kind)
        currency = try c.decode(String.self, forKey: .currency)
        openingBalance = Money(minor: try c.decode(Int.self, forKey: .openingBalanceMinor), currency: currency)
        ownerId = try c.decodeIfPresent(UUID.self, forKey: .ownerId)
        archivedAt = try c.decodeIfPresent(ServerDate.self, forKey: .archivedAt)?.date
        createdAt = try c.decodeIfPresent(ServerDate.self, forKey: .createdAt)?.date
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        includeInNetWorth = try c.decodeIfPresent(Bool.self, forKey: .includeInNetWorth) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(householdId, forKey: .householdId)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(currency, forKey: .currency)
        try c.encode(openingBalance.minor, forKey: .openingBalanceMinor)
        try c.encode(ownerId, forKey: .ownerId)
        try c.encodeIfPresent(archivedAt.map(ServerDate.init), forKey: .archivedAt)
        try c.encodeIfPresent(createdAt.map(ServerDate.init), forKey: .createdAt)
        try c.encode(isDefault, forKey: .isDefault)
        try c.encode(includeInNetWorth, forKey: .includeInNetWorth)
    }
}

public enum CategoryKind: String, Codable, CaseIterable, Sendable {
    case income, expense, transfer

    public var title: String {
        switch self {
        case .income: "Ingreso"
        case .expense: "Gasto"
        case .transfer: "Transferencia"
        }
    }
}

public struct BudgetCategory: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var householdId: UUID
    public var name: String
    public var kind: CategoryKind
    public var budgetGroup: BudgetGroup?
    public var icon: String?

    public init(id: UUID = UUID(), householdId: UUID, name: String, kind: CategoryKind = .expense,
                budgetGroup: BudgetGroup? = nil, icon: String? = nil) {
        self.id = id
        self.householdId = householdId
        self.name = name
        self.kind = kind
        self.budgetGroup = budgetGroup
        self.icon = icon
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, icon
        case householdId = "household_id"
        case budgetGroup = "budget_group"
    }

    public static let maxNameLength = 40

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Qué falla antes de guardarla, mirando también las demás categorías del hogar.
    public func issue(among others: [BudgetCategory]) -> String? {
        if trimmedName.isEmpty { return "Ponle un nombre a la categoría." }
        if trimmedName.count > Self.maxNameLength { return "El nombre es demasiado largo (máximo \(Self.maxNameLength) letras)." }
        if kind != .expense && budgetGroup != nil { return "Sólo los gastos van en un grupo del 50/30/20." }
        let repeated = others.contains {
            $0.id != id && $0.householdId == householdId && $0.kind == kind
                && $0.trimmedName.lowercased() == trimmedName.lowercased()
        }
        if repeated { return "Ya hay una categoría de \(kind.title.lowercased()) con ese nombre." }
        return nil
    }

    /// Las mismas que crea el servidor para cada hogar nuevo.
    public static func defaults(for householdId: UUID) -> [BudgetCategory] {
        let rows: [(String, CategoryKind, BudgetGroup?, String)] = [
            ("Nómina", .income, nil, "banknote"),
            ("Otros ingresos", .income, nil, "plus.circle"),
            ("Vivienda", .expense, .needs, "house"),
            ("Supermercado", .expense, .needs, "cart"),
            ("Suministros", .expense, .needs, "bolt"),
            ("Transporte", .expense, .needs, "car"),
            ("Salud", .expense, .needs, "cross.case"),
            ("Seguros", .expense, .needs, "shield"),
            ("Impuestos", .expense, .needs, "building.columns"),
            ("Multas y sanciones", .expense, .needs, "exclamationmark.triangle"),
            ("Tasas y trámites", .expense, .needs, "doc.text"),
            ("Restaurantes", .expense, .wants, "fork.knife"),
            ("Ocio", .expense, .wants, "ticket"),
            ("Compras", .expense, .wants, "bag"),
            ("Viajes", .expense, .wants, "airplane"),
            ("Suscripciones", .expense, .wants, "repeat"),
            ("Ahorro", .expense, .savings, "banknote"),
            ("Inversión", .expense, .savings, "chart.line.uptrend.xyaxis"),
            ("Deudas", .expense, .savings, "creditcard"),
            ("Transferencia entre cuentas", .transfer, nil, "arrow.left.arrow.right"),
        ]
        return rows.map { BudgetCategory(householdId: householdId, name: $0.0, kind: $0.1, budgetGroup: $0.2, icon: $0.3) }
    }
}

/// Movimiento de una cuenta. Importe negativo = gasto, positivo = ingreso.
public struct Movement: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var householdId: UUID
    public var accountId: UUID
    public var categoryId: UUID?
    public var bookedOn: CalendarDay
    public var amount: Money
    public var description: String
    public var notes: String?
    public var importHash: String?
    /// No cuenta en presupuesto, informes ni flujo (sí en el saldo).
    public var excluded: Bool
    /// Cuándo se marcó como revisado; nil = sin revisar.
    public var reviewedAt: Date?
    /// A quién se paga o quién paga.
    public var payee: String?
    /// Etiquetas en minúsculas, sin «#».
    public var tags: [String]

    public init(id: UUID = UUID(), householdId: UUID, accountId: UUID, categoryId: UUID? = nil,
                bookedOn: CalendarDay, amount: Money, description: String, notes: String? = nil,
                importHash: String? = nil, excluded: Bool = false, reviewedAt: Date? = nil,
                payee: String? = nil, tags: [String] = []) {
        self.id = id
        self.householdId = householdId
        self.accountId = accountId
        self.categoryId = categoryId
        self.bookedOn = bookedOn
        self.amount = amount
        self.description = description
        self.notes = notes
        self.importHash = importHash
        self.excluded = excluded
        self.reviewedAt = reviewedAt
        self.payee = payee
        self.tags = tags
    }

    public var isExpense: Bool { amount.isNegative }
    public var isReviewed: Bool { reviewedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, description, notes
        case householdId = "household_id"
        case accountId = "account_id"
        case categoryId = "category_id"
        case bookedOn = "booked_on"
        case amountMinor = "amount_minor"
        case importHash = "import_hash"
        case excluded, payee, tags
        case reviewedAt = "reviewed_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        accountId = try c.decode(UUID.self, forKey: .accountId)
        excluded = try c.decodeIfPresent(Bool.self, forKey: .excluded) ?? false
        reviewedAt = try c.decodeIfPresent(ServerDate.self, forKey: .reviewedAt)?.date
        payee = try c.decodeIfPresent(String.self, forKey: .payee)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        categoryId = try c.decodeIfPresent(UUID.self, forKey: .categoryId)
        bookedOn = try c.decode(CalendarDay.self, forKey: .bookedOn)
        amount = Money(minor: try c.decode(Int.self, forKey: .amountMinor))
        description = try c.decode(String.self, forKey: .description)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        importHash = try c.decodeIfPresent(String.self, forKey: .importHash)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(householdId, forKey: .householdId)
        try c.encode(accountId, forKey: .accountId)
        try c.encode(categoryId, forKey: .categoryId)
        try c.encode(bookedOn, forKey: .bookedOn)
        try c.encode(amount.minor, forKey: .amountMinor)
        try c.encode(description, forKey: .description)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(importHash, forKey: .importHash)
        try c.encode(excluded, forKey: .excluded)
        try c.encodeIfPresent(reviewedAt.map(ServerDate.init), forKey: .reviewedAt)
        try c.encode(payee, forKey: .payee)
        try c.encode(tags, forKey: .tags)
    }
}

/// Lo que se apunta o se importa, antes de tener id en el servidor.
public struct MovementDraft: Hashable, Sendable {
    public var accountId: UUID
    public var categoryId: UUID?
    public var bookedOn: CalendarDay
    public var amount: Money
    public var description: String
    public var notes: String?
    public var importHash: String?
    public var excluded: Bool
    public var payee: String?
    public var tags: [String]

    public init(accountId: UUID, categoryId: UUID? = nil, bookedOn: CalendarDay, amount: Money,
                description: String, notes: String? = nil, importHash: String? = nil,
                excluded: Bool = false, payee: String? = nil, tags: [String] = []) {
        self.accountId = accountId
        self.categoryId = categoryId
        self.bookedOn = bookedOn
        self.amount = amount
        self.description = description
        self.notes = notes
        self.importHash = importHash
        self.excluded = excluded
        self.payee = payee
        self.tags = tags
    }

    /// Problema que impide guardarlo, en español, o nil si es válido.
    public var issue: String? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "Escribe un concepto." }
        if text.count > 200 { return "El concepto es demasiado largo (máximo 200 caracteres)." }
        if amount.minor == 0 { return "El importe no puede ser cero." }
        if let notes, notes.count > 500 { return "Las notas son demasiado largas (máximo 500 caracteres)." }
        if let payee, payee.trimmingCharacters(in: .whitespacesAndNewlines).count > 80 {
            return "El beneficiario es demasiado largo (máximo 80 caracteres)."
        }
        if let issue = MovementTags.issue(tags) { return issue }
        return nil
    }
}

public struct AccountDraft: Hashable, Sendable {
    public var name: String
    public var kind: AccountKind
    public var openingBalance: Money
    public var ownerId: UUID?

    public init(name: String = "", kind: AccountKind = .checking, openingBalance: Money = .zero, ownerId: UUID? = nil) {
        self.name = name
        self.kind = kind
        self.openingBalance = openingBalance
        self.ownerId = ownerId
    }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var issue: String? {
        if trimmedName.isEmpty { return "Ponle un nombre a la cuenta." }
        if trimmedName.count > 60 { return "El nombre es demasiado largo (máximo 60 caracteres)." }
        return nil
    }
}

/// Resultado de una importación de CSV.
public struct ImportResult: Hashable, Sendable {
    public var inserted: Int
    public var duplicates: Int

    public init(inserted: Int, duplicates: Int) {
        self.inserted = inserted
        self.duplicates = duplicates
    }
}

/// Fecha de calendario sin hora ni zona ("2026-10-28"), como la columna `date` de Postgres.
public struct CalendarDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1, day <= CalendarDay.daysIn(month: month, year: year),
              (1900...2999).contains(year) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Calendario gregoriano en la zona del usuario: el del dispositivo puede ser budista, japonés o islámico.
    public static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Hoy (o la fecha dada) en el calendario gregoriano y zona del usuario.
    public init(_ date: Date = Date(), calendar: Calendar = CalendarDay.gregorian) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year!
        month = parts.month!
        day = parts.day!
    }

    /// Lee "2026-10-28".
    public init?(iso text: String) {
        let parts = text.prefix(10).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { iso }

    /// Medianoche de ese día en el calendario dado, para DatePicker y formateo.
    public func date(calendar: Calendar = CalendarDay.gregorian) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let day = CalendarDay(iso: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "fecha no válida"))
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(iso)
    }
}

/// Fecha con hora tal como la envía Postgres ("2026-10-28T10:00:00.123+00:00").
struct ServerDate: Codable {
    var date: Date

    init(_ date: Date) { self.date = date }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: text) ?? plain.date(from: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "fecha no válida"))
        }
        self.date = date
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(ISO8601DateFormatter().string(from: date))
    }
}

/// «Actualizar saldo»: escribes lo que hay de verdad en la cuenta y se apunta un ajuste por la diferencia.
public enum BalanceAdjustment {
    public static let description = "AJUSTE DE SALDO"

    /// El movimiento de ajuste, o nil si el saldo ya coincide.
    /// Va con la categoría de transferencia (si la hay) para que no cuente como gasto ni ingreso.
    public static func draft(account: Account, current: Money, actual: Money, on day: CalendarDay,
                             categories: [BudgetCategory]) -> MovementDraft? {
        let difference = actual.minor - current.minor
        guard difference != 0 else { return nil }
        let transfer = categories.first { $0.kind == .transfer && $0.householdId == account.householdId }
            ?? categories.first { $0.kind == .transfer }
        return MovementDraft(accountId: account.id, categoryId: transfer?.id, bookedOn: day,
                             amount: Money(minor: difference, currency: account.currency),
                             description: description)
    }
}
