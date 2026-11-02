import Foundation

// MARK: Días

extension CalendarDay {
    /// Días desde el 1 de enero de 1970 (algoritmo civil de H. Hinnant), para sumar días sin `Calendar`.
    public var ordinal: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public init(ordinal: Int) {
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        self = CalendarDay(year: y, month: m, day: d)!
    }

    public func adding(days: Int) -> CalendarDay { CalendarDay(ordinal: ordinal + days) }

    public func days(until other: CalendarDay) -> Int { other.ordinal - ordinal }

    /// El mismo día unos meses después; si ese mes es más corto, su último día (31 ene + 1 mes = 28 feb).
    public func adding(months: Int) -> CalendarDay {
        let key = MonthKey(self).adding(months: months)
        let last = CalendarDay.daysIn(month: key.month, year: key.year)
        return CalendarDay(year: key.year, month: key.month, day: min(day, last))!
    }

    /// "5 de noviembre".
    public var longTitle: String {
        let names = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
                     "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
        return "\(day) de \(names[month - 1])"
    }
}

// MARK: Pagos recurrentes

public enum RecurringKind: String, Codable, CaseIterable, Sendable {
    case subscription, essential, income

    public var title: String {
        switch self {
        case .subscription: "Suscripción"
        case .essential: "Gasto esencial"
        case .income: "Ingreso fijo"
        }
    }

    public var pluralTitle: String {
        switch self {
        case .subscription: "Suscripciones"
        case .essential: "Gastos esenciales"
        case .income: "Ingresos fijos"
        }
    }

    public var systemImage: String {
        switch self {
        case .subscription: "play.rectangle"
        case .essential: "bolt.house"
        case .income: "banknote"
        }
    }
}

public enum RecurrenceUnit: String, Codable, CaseIterable, Sendable {
    case week, month, year
}

/// Cada cuánto se repite un pago: cada `every` semanas, meses o años.
public struct Recurrence: Hashable, Codable, Sendable {
    public var every: Int
    public var unit: RecurrenceUnit

    public init(every: Int = 1, unit: RecurrenceUnit = .month) {
        self.every = every
        self.unit = unit
    }

    public static let monthly = Recurrence(every: 1, unit: .month)

    /// Opciones del selector de la app.
    public static let common: [Recurrence] = [
        Recurrence(every: 1, unit: .week), Recurrence(every: 2, unit: .week),
        .monthly, Recurrence(every: 2, unit: .month), Recurrence(every: 3, unit: .month),
        Recurrence(every: 6, unit: .month), Recurrence(every: 1, unit: .year),
    ]

    public var title: String {
        switch (unit, every) {
        case (.week, 1): "Cada semana"
        case (.week, let n): "Cada \(n) semanas"
        case (.month, 1): "Cada mes"
        case (.month, 3): "Cada trimestre"
        case (.month, 6): "Cada semestre"
        case (.month, let n): "Cada \(n) meses"
        case (.year, 1): "Cada año"
        case (.year, let n): "Cada \(n) años"
        }
    }

    /// El cargo número `n` (0 es el primero) de una serie que empieza en `start`.
    /// Los mensuales se cuentan siempre desde el primero, para que un día 31 no
    /// se quede en 28 para siempre después de febrero.
    public func occurrence(_ n: Int, from start: CalendarDay) -> CalendarDay {
        switch unit {
        case .week: start.adding(days: 7 * every * n)
        case .month: start.adding(months: every * n)
        case .year: start.adding(months: 12 * every * n)
        }
    }

    /// Cuántas veces al año se repite, como fracción (52/2 = 26 para cada 2 semanas).
    var perYear: Double {
        switch unit {
        case .week: 52.0 / Double(every)
        case .month: 12.0 / Double(every)
        case .year: 1.0 / Double(every)
        }
    }
}

/// Un pago o ingreso que se repite: una suscripción, el alquiler, la nómina...
/// Se comparte con todo el hogar.
public struct RecurringSeries: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var householdId: UUID
    public var name: String
    public var kind: RecurringKind
    /// Siempre en positivo; `signedAmount` le pone el signo.
    public var amount: Money
    public var accountId: UUID?
    public var categoryId: UUID?
    public var recurrence: Recurrence
    public var startsOn: CalendarDay
    public var endsOn: CalendarDay?
    /// Días de antelación del aviso; nil, sin aviso.
    public var remindDaysBefore: Int?
    public var archivedAt: Date?

    public init(id: UUID = UUID(), householdId: UUID, name: String, kind: RecurringKind = .subscription,
                amount: Money, accountId: UUID? = nil, categoryId: UUID? = nil,
                recurrence: Recurrence = .monthly, startsOn: CalendarDay, endsOn: CalendarDay? = nil,
                remindDaysBefore: Int? = 1, archivedAt: Date? = nil) {
        self.id = id
        self.householdId = householdId
        self.name = name
        self.kind = kind
        self.amount = amount
        self.accountId = accountId
        self.categoryId = categoryId
        self.recurrence = recurrence
        self.startsOn = startsOn
        self.endsOn = endsOn
        self.remindDaysBefore = remindDaysBefore
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }
    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Negativo para gastos, positivo para ingresos.
    public var signedAmount: Money { kind == .income ? amount : -amount }

    /// Lo que supone al mes, en promedio (una cuota anual de 120 € son 10 € al mes).
    public var monthlyAmount: Money {
        Money(minor: Int((Double(amount.minor) * recurrence.perYear / 12).rounded()), currency: amount.currency)
    }

    public var issue: String? {
        if trimmedName.isEmpty { return "Ponle un nombre." }
        if trimmedName.count > 60 { return "El nombre es demasiado largo." }
        if amount.minor <= 0 { return "El importe tiene que ser mayor que cero." }
        if !(1...52).contains(recurrence.every) { return "La frecuencia no es válida." }
        if let endsOn, endsOn < startsOn { return "No puede terminar antes de empezar." }
        if let days = remindDaysBefore, !(0...14).contains(days) { return "El aviso puede ser de 0 a 14 días antes." }
        return nil
    }

    /// Días de cargo entre dos fechas, ambas incluidas.
    public func occurrences(from: CalendarDay, through: CalendarDay) -> [CalendarDay] {
        let last = endsOn.map { min($0, through) } ?? through
        guard from <= last else { return [] }
        var n = firstIndex(onOrAfter: from)
        var result: [CalendarDay] = []
        while true {
            let day = recurrence.occurrence(n, from: startsOn)
            if day > last { break }
            if day >= from { result.append(day) }
            n += 1
        }
        return result
    }

    /// El próximo cargo desde ese día (incluido), si la serie no ha terminado.
    public func nextDue(onOrAfter day: CalendarDay) -> CalendarDay? {
        let n = firstIndex(onOrAfter: day)
        for i in n...(n + 2) {
            let due = recurrence.occurrence(i, from: startsOn)
            if due >= day { return endsOn.map { due <= $0 ? due : nil } ?? due }
        }
        return nil
    }

    /// Una estimación por debajo del índice del primer cargo en o después de `day`,
    /// para no recorrer años de cargos uno a uno.
    private func firstIndex(onOrAfter day: CalendarDay) -> Int {
        guard day > startsOn else { return 0 }
        let estimate: Int
        switch recurrence.unit {
        case .week: estimate = startsOn.days(until: day) / (7 * recurrence.every)
        case .month, .year:
            let months = (day.year - startsOn.year) * 12 + (day.month - startsOn.month)
            let step = recurrence.unit == .month ? recurrence.every : 12 * recurrence.every
            estimate = months / step
        }
        return max(0, estimate - 1)
    }
}

/// Un cargo concreto que está por venir.
public struct UpcomingCharge: Hashable, Sendable, Identifiable {
    public var series: RecurringSeries
    public var due: CalendarDay

    public var id: String { "\(series.id.uuidString)-\(due.iso)" }
}

extension Array where Element == RecurringSeries {
    /// Cargos de las series activas entre hoy y dentro de `days` días, por fecha.
    public func upcoming(from today: CalendarDay, days: Int = 30) -> [UpcomingCharge] {
        let end = today.adding(days: days)
        var charges: [UpcomingCharge] = []
        for series in self where !series.isArchived {
            for due in series.occurrences(from: today, through: end) {
                charges.append(UpcomingCharge(series: series, due: due))
            }
        }
        return charges.sorted { (a: UpcomingCharge, b: UpcomingCharge) -> Bool in
            a.due != b.due ? a.due < b.due : a.series.name < b.series.name
        }
    }

    /// Lo que suman al mes las series activas de ese tipo.
    public func monthlyTotal(of kind: RecurringKind, on day: CalendarDay) -> Money {
        filter { !$0.isArchived && $0.kind == kind && ($0.endsOn.map { $0 >= day } ?? true) }
            .reduce(Money.zero) { $0 + $1.monthlyAmount }
    }
}

// MARK: Columnas de Supabase

extension RecurringSeries {
    enum CodingKeys: String, CodingKey {
        case id, name, kind, every, unit
        case householdId = "household_id"
        case amountMinor = "amount_minor"
        case accountId = "account_id"
        case categoryId = "category_id"
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case remindDaysBefore = "remind_days_before"
        case archivedAt = "archived_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(RecurringKind.self, forKey: .kind)
        amount = Money(minor: try c.decode(Int.self, forKey: .amountMinor))
        accountId = try c.decodeIfPresent(UUID.self, forKey: .accountId)
        categoryId = try c.decodeIfPresent(UUID.self, forKey: .categoryId)
        recurrence = Recurrence(every: try c.decode(Int.self, forKey: .every), unit: try c.decode(RecurrenceUnit.self, forKey: .unit))
        startsOn = try c.decode(CalendarDay.self, forKey: .startsOn)
        endsOn = try c.decodeIfPresent(CalendarDay.self, forKey: .endsOn)
        remindDaysBefore = try c.decodeIfPresent(Int.self, forKey: .remindDaysBefore)
        archivedAt = try c.decodeIfPresent(ServerDate.self, forKey: .archivedAt)?.date
    }

    /// Codifica las columnas editables (sin id ni hogar, que pone quien inserta).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(trimmedName, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(amount.minor, forKey: .amountMinor)
        try c.encode(accountId, forKey: .accountId)
        try c.encode(categoryId, forKey: .categoryId)
        try c.encode(recurrence.every, forKey: .every)
        try c.encode(recurrence.unit, forKey: .unit)
        try c.encode(startsOn, forKey: .startsOn)
        try c.encode(endsOn, forKey: .endsOn)
        try c.encode(remindDaysBefore, forKey: .remindDaysBefore)
        try c.encode(archivedAt.map(ServerDate.init), forKey: .archivedAt)
    }
}
