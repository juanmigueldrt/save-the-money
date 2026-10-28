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

    public init(id: UUID = UUID(), householdId: UUID, name: String, kind: AccountKind = .checking,
                currency: String = "EUR", openingBalance: Money = .zero, ownerId: UUID? = nil,
                archivedAt: Date? = nil) {
        self.id = id
        self.householdId = householdId
        self.name = name
        self.kind = kind
        self.currency = currency
        self.openingBalance = openingBalance
        self.ownerId = ownerId
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }
    public var isShared: Bool { ownerId == nil }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, currency
        case householdId = "household_id"
        case openingBalanceMinor = "opening_balance_minor"
        case ownerId = "owner_id"
        case archivedAt = "archived_at"
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

    public init(id: UUID = UUID(), householdId: UUID, accountId: UUID, categoryId: UUID? = nil,
                bookedOn: CalendarDay, amount: Money, description: String, notes: String? = nil,
                importHash: String? = nil) {
        self.id = id
        self.householdId = householdId
        self.accountId = accountId
        self.categoryId = categoryId
        self.bookedOn = bookedOn
        self.amount = amount
        self.description = description
        self.notes = notes
        self.importHash = importHash
    }

    public var isExpense: Bool { amount.isNegative }

    enum CodingKeys: String, CodingKey {
        case id, description, notes
        case householdId = "household_id"
        case accountId = "account_id"
        case categoryId = "category_id"
        case bookedOn = "booked_on"
        case amountMinor = "amount_minor"
        case importHash = "import_hash"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        accountId = try c.decode(UUID.self, forKey: .accountId)
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

    public init(accountId: UUID, categoryId: UUID? = nil, bookedOn: CalendarDay, amount: Money,
                description: String, notes: String? = nil, importHash: String? = nil) {
        self.accountId = accountId
        self.categoryId = categoryId
        self.bookedOn = bookedOn
        self.amount = amount
        self.description = description
        self.notes = notes
        self.importHash = importHash
    }

    /// Problema que impide guardarlo, en español, o nil si es válido.
    public var issue: String? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "Escribe un concepto." }
        if text.count > 200 { return "El concepto es demasiado largo (máximo 200 caracteres)." }
        if amount.minor == 0 { return "El importe no puede ser cero." }
        if let notes, notes.count > 500 { return "Las notas son demasiado largas (máximo 500 caracteres)." }
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

    /// Hoy (o la fecha dada) en el calendario y zona del usuario.
    public init(_ date: Date = Date(), calendar: Calendar = .current) {
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
    public func date(calendar: Calendar = .current) -> Date {
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
