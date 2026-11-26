import Foundation

// MARK: - Día de cobro

/// Cada cuánto cobra una persona.
public enum PayFrequency: String, CaseIterable, Codable, Sendable, Identifiable {
    case weekly, biweekly
    case twiceMonthly = "twice_monthly"
    case monthly, yearly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .weekly: "Cada semana"
        case .biweekly: "Cada dos semanas"
        case .twiceMonthly: "Dos días al mes"
        case .monthly: "Cada mes"
        case .yearly: "Cada año"
        }
    }

    /// Si usa una fecha de cobro de referencia en vez de días del mes.
    public var usesAnchor: Bool { self == .weekly || self == .biweekly || self == .yearly }
}

/// Cuándo cobra una persona; de ahí salen sus periodos de presupuesto. Es privado de cada uno.
public struct PaySchedule: Hashable, Sendable, Codable {
    public var frequency: PayFrequency
    /// Día del mes (1–31; en meses más cortos, el último día).
    public var day1: Int
    /// Segundo día del mes, sólo con `twiceMonthly`.
    public var day2: Int?
    /// Un día en que se cobró, para semanal, quincenal y anual.
    public var anchor: CalendarDay?

    public init(frequency: PayFrequency = .monthly, day1: Int = 1, day2: Int? = nil, anchor: CalendarDay? = nil) {
        self.frequency = frequency
        self.day1 = day1
        self.day2 = day2
        self.anchor = anchor
    }

    /// Mensual desde el día de inicio de mes del hogar (lo de antes de la fase C).
    public static func monthly(startDay: Int) -> PaySchedule { PaySchedule(frequency: .monthly, day1: startDay) }

    public var issue: String? {
        guard (1...31).contains(day1) else { return "El día de cobro tiene que estar entre 1 y 31." }
        switch frequency {
        case .twiceMonthly:
            guard let day2, (1...31).contains(day2), day2 > day1 else {
                return "El segundo día de cobro tiene que ir después del primero."
            }
        case .weekly, .biweekly, .yearly:
            if anchor == nil { return "Elige un día en que hayas cobrado." }
        case .monthly:
            break
        }
        return nil
    }

    /// Texto corto: "Cada mes, el día 25", "Días 1 y 15", "Cada semana (lunes)".
    public var summary: String {
        switch frequency {
        case .monthly: return day1 == 1 ? "Cada mes, desde el día 1" : "Cada mes, el día \(day1)"
        case .twiceMonthly: return "Los días \(day1) y \(day2 ?? 15)"
        case .weekly: return "Cada semana" + (anchor.map { " (\($0.weekdayName))" } ?? "")
        case .biweekly: return "Cada dos semanas" + (anchor.map { " (\($0.weekdayName))" } ?? "")
        case .yearly: return "Cada año" + (anchor.map { ", el \($0.day)/\($0.month)" } ?? "")
        }
    }

    /// El periodo (de un cobro al día antes del siguiente) que contiene ese día.
    public func period(containing day: CalendarDay) -> BudgetPeriod {
        let start = lastPayday(onOrBefore: day)
        let next = nextPayday(after: start)
        return BudgetPeriod(start: start, end: next.adding(days: -1))
    }

    public func period(after period: BudgetPeriod) -> BudgetPeriod { self.period(containing: period.end.adding(days: 1)) }

    public func period(before period: BudgetPeriod) -> BudgetPeriod { self.period(containing: period.start.adding(days: -1)) }

    /// El próximo cobro estrictamente después de ese día.
    public func nextPayday(after day: CalendarDay) -> CalendarDay {
        switch frequency {
        case .weekly, .biweekly:
            let step = frequency == .weekly ? 7 : 14
            let base = anchor ?? day
            let offset = base.days(until: day)
            let steps = Int((Double(offset) / Double(step)).rounded(.down)) + 1
            return base.adding(days: steps * step)
        case .yearly:
            let base = anchor ?? day
            var candidate = Self.clamped(year: day.year, month: base.month, day: base.day)
            if candidate <= day { candidate = Self.clamped(year: day.year + 1, month: base.month, day: base.day) }
            return candidate
        case .monthly, .twiceMonthly:
            for monthOffset in 0...2 {
                let key = MonthKey(day).adding(months: monthOffset)
                for d in days {
                    let candidate = Self.clamped(year: key.year, month: key.month, day: d)
                    if candidate > day { return candidate }
                }
            }
            return day.adding(days: 1)
        }
    }

    /// El último cobro ese día o antes.
    public func lastPayday(onOrBefore day: CalendarDay) -> CalendarDay {
        switch frequency {
        case .weekly, .biweekly:
            let step = frequency == .weekly ? 7 : 14
            let base = anchor ?? day
            let offset = base.days(until: day)
            let steps = Int((Double(offset) / Double(step)).rounded(.down))
            return base.adding(days: steps * step)
        case .yearly:
            let base = anchor ?? day
            let candidate = Self.clamped(year: day.year, month: base.month, day: base.day)
            return candidate <= day ? candidate : Self.clamped(year: day.year - 1, month: base.month, day: base.day)
        case .monthly, .twiceMonthly:
            for monthOffset in 0...2 {
                let key = MonthKey(day).adding(months: -monthOffset)
                for d in days.reversed() {
                    let candidate = Self.clamped(year: key.year, month: key.month, day: d)
                    if candidate <= day { return candidate }
                }
            }
            return day
        }
    }

    private var days: [Int] {
        frequency == .twiceMonthly ? [day1, day2 ?? 15].sorted() : [day1]
    }

    /// Ese día del mes, o el último si el mes es más corto (31 de febrero → 28 o 29).
    static func clamped(year: Int, month: Int, day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: min(day, CalendarDay.daysIn(month: month, year: year)))!
    }
}

extension CalendarDay {
    /// "25 oct", sin depender del idioma del sistema.
    public var dayMonthText: String {
        let names = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"]
        return "\(day) \(names[month - 1])"
    }

    /// "lunes", "martes"…
    public var weekdayName: String {
        let names = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]
        // El ordinal 0 (1970-01-01) fue jueves.
        let index = ((ordinal % 7) + 7 + 3) % 7
        return names[index]
    }
}

// MARK: - Periodo

/// Del día de cobro al día antes del siguiente (o unas fechas propias).
public struct BudgetPeriod: Hashable, Sendable, Comparable, Identifiable {
    public var start: CalendarDay
    public var end: CalendarDay

    public init(start: CalendarDay, end: CalendarDay) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    /// El mes natural.
    public init(month: MonthKey) {
        self.init(start: month.firstDay,
                  end: CalendarDay(year: month.year, month: month.month,
                                   day: CalendarDay.daysIn(month: month.month, year: month.year))!)
    }

    public var id: CalendarDay { start }
    public var range: ClosedRange<CalendarDay> { start...end }
    public var dayCount: Int { start.days(until: end) + 1 }

    public func contains(_ day: CalendarDay) -> Bool { range.contains(day) }

    /// El mes al que se asocia: el del último día (del 25-oct al 24-nov es «noviembre»).
    public var month: MonthKey { MonthKey(end) }

    /// "Noviembre de 2026" si es un mes natural; si no, "25 oct – 24 nov".
    public var title: String {
        if start.day == 1 && end == BudgetPeriod(month: MonthKey(start)).end { return MonthKey(start).title }
        return "\(start.dayMonthText) – \(end.dayMonthText)"
    }

    /// Días que quedan contando hoy (0 si ya pasó; todos si aún no empezó).
    public func daysLeft(from today: CalendarDay) -> Int {
        if today > end { return 0 }
        if today < start { return dayCount }
        return today.days(until: end) + 1
    }

    /// Días que ya han pasado contando hoy (0 si aún no empezó; todos si ya acabó).
    public func daysElapsed(at today: CalendarDay) -> Int {
        if today < start { return 0 }
        if today > end { return dayCount }
        return start.days(until: today) + 1
    }

    public static func < (lhs: BudgetPeriod, rhs: BudgetPeriod) -> Bool { lhs.start < rhs.start }
}

// MARK: - Lo que dice el presupuesto del periodo

/// Cuánto puedes gastar hoy, cuánto falta para cobrar, la proyección del periodo y lo que queda por presupuestar.
public struct PeriodInsights: Hashable, Sendable {
    /// Lo que se puede gastar en el periodo: necesidades + caprichos del reparto, más el arrastre.
    public var spendable: Money
    public var spent: Money
    /// Lo que queda de lo gastable (negativo = te has pasado).
    public var left: Money
    /// Lo que queda dividido entre los días que faltan (0 si no queda nada).
    public var perDay: Money
    /// Días hasta el próximo cobro (el día siguiente al final del periodo).
    public var daysToPayday: Int
    /// Gasto previsto al final del periodo, al ritmo de hoy.
    public var projectedSpent: Money
    /// Ingresos previstos menos la suma de los límites (lo que aún no tiene destino).
    public var unbudgeted: Money

    public init(report: BudgetReport, budget: Budget?, today: CalendarDay) {
        let period = BudgetPeriod(start: report.period.lowerBound, end: report.period.upperBound)
        let spendingGroups = report.groups.filter { $0.group != .savings }
        let allocated = spendingGroups.reduce(0) { $0 + $1.allocated.minor }
        let carried = report.carried.values.reduce(0) { $0 + $1.minor }
        let spentMinor = spendingGroups.reduce(0) { $0 + $1.spent.minor } + report.uncategorized.minor
        spendable = Money(minor: allocated + carried)
        spent = Money(minor: spentMinor)
        left = Money(minor: allocated + carried - spentMinor)
        let remainingDays = period.daysLeft(from: today)
        perDay = remainingDays > 0 && left.minor > 0 ? Money(minor: left.minor / remainingDays) : .zero
        daysToPayday = max(0, today.days(until: period.end.adding(days: 1)))
        let elapsed = max(1, period.daysElapsed(at: today))
        projectedSpent = today > period.end
            ? spent
            : Money(minor: Int((Double(spentMinor) / Double(elapsed) * Double(period.dayCount)).rounded()))
        let limits = budget?.limits.values.reduce(0) { $0 + $1.minor } ?? 0
        unbudgeted = Money(minor: report.base.minor - limits)
    }
}

// MARK: - Arrastre

public enum BudgetCarryOver {
    /// Lo que pasa de un periodo al siguiente en cada categoría con límite: lo que sobró (positivo)
    /// o lo que te pasaste (negativo), sumado a lo que ya venía arrastrado.
    public static func amounts(previous: BudgetReport) -> [UUID: Money] {
        var result: [UUID: Money] = [:]
        for line in previous.lines {
            guard let limit = line.limit else { continue }
            let available = limit.minor + (previous.carried[line.category.id]?.minor ?? 0)
            let left = available - line.spent.minor
            if left != 0 { result[line.category.id] = Money(minor: left) }
        }
        return result
    }
}

// MARK: - Presupuesto inteligente

public enum SmartBudget {
    /// Límites propuestos: la media de lo gastado en cada categoría de gasto en los periodos dados
    /// (normalmente los 3 anteriores), redondeada a euros. Las que no tuvieron gasto no salen.
    public static func suggestedLimits(movements: [Movement], categories: [BudgetCategory],
                                       periods: [BudgetPeriod]) -> [UUID: Money] {
        guard !periods.isEmpty else { return [:] }
        let expense = Dictionary(categories.filter { $0.kind == .expense }.map { ($0.id, $0) },
                                 uniquingKeysWith: { a, _ in a })
        var totals: [UUID: Int] = [:]
        for movement in movements where !movement.excluded {
            guard let id = movement.categoryId, expense[id] != nil,
                  periods.contains(where: { $0.contains(movement.bookedOn) }) else { continue }
            totals[id, default: 0] -= movement.amount.minor
        }
        var result: [UUID: Money] = [:]
        for (id, total) in totals where total > 0 {
            let average = Double(total) / Double(periods.count)
            let euros = (average / 100).rounded(.up)
            result[id] = Money(minor: Int(euros) * 100)
        }
        return result
    }
}

// MARK: - Presupuestos extra

/// Un presupuesto aparte del del periodo, con nombre, límite y fechas propias (p. ej. «Vacaciones»).
public struct ExtraBudget: Identifiable, Hashable, Sendable, Codable, Named {
    public let id: UUID
    public var householdId: UUID
    public var name: String
    public var limit: Money
    public var startsOn: CalendarDay
    /// nil = sin final.
    public var endsOn: CalendarDay?
    /// Vacías = todas las categorías de gasto / todas las cuentas.
    public var categoryIds: [UUID]
    public var accountIds: [UUID]
    public var isFavorite: Bool
    /// Versión de la fila: el `updated_at` del servidor tal cual llegó (como `Movement.updatedAt`). Nil en uno que
    /// aún no se ha guardado: guardarlo es un alta.
    public var updatedAt: String?

    public init(id: UUID = UUID(), householdId: UUID, name: String = "", limit: Money = .zero,
                startsOn: CalendarDay = CalendarDay(), endsOn: CalendarDay? = nil,
                categoryIds: [UUID] = [], accountIds: [UUID] = [], isFavorite: Bool = false, updatedAt: String? = nil) {
        self.updatedAt = updatedAt
        self.id = id
        self.householdId = householdId
        self.name = name
        self.limit = limit
        self.startsOn = startsOn
        self.endsOn = endsOn
        self.categoryIds = categoryIds
        self.accountIds = accountIds
        self.isFavorite = isFavorite
    }

    public var issue: String? {
        if trimmedName.isEmpty { return "Ponle un nombre." }
        if trimmedName.count > 60 { return "El nombre es demasiado largo (máximo 60 caracteres)." }
        if limit.minor <= 0 { return "El límite tiene que ser mayor que cero." }
        if let endsOn, endsOn < startsOn { return "La fecha de fin no puede ser anterior a la de inicio." }
        if categoryIds.count > 50 || accountIds.count > 50 { return "Demasiadas categorías o cuentas." }
        return nil
    }

    /// Gasto que cuenta: dentro de las fechas, en sus categorías de gasto y cuentas, sin excluidos ni transferencias.
    public func spent(movements: [Movement], categories: [BudgetCategory]) -> Money {
        let kinds = Dictionary(categories.map { ($0.id, $0.kind) }, uniquingKeysWith: { a, _ in a })
        let categorySet = Set(categoryIds), accountSet = Set(accountIds)
        var total = 0
        for movement in movements where !movement.excluded && movement.bookedOn >= startsOn {
            if let endsOn, movement.bookedOn > endsOn { continue }
            if !accountSet.isEmpty && !accountSet.contains(movement.accountId) { continue }
            let kind = movement.categoryId.flatMap { kinds[$0] }
            if kind == .transfer || kind == .income { continue }
            if !categorySet.isEmpty && !(movement.categoryId.map(categorySet.contains) ?? false) { continue }
            if kind == nil && !movement.amount.isNegative { continue }
            total -= movement.amount.minor
        }
        return Money(minor: total)
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case householdId = "household_id"
        case limitMinor = "limit_minor"
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case categoryIds = "category_ids"
        case accountIds = "account_ids"
        case isFavorite = "is_favorite"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        name = try c.decode(String.self, forKey: .name)
        limit = Money(minor: try c.decode(Int.self, forKey: .limitMinor))
        startsOn = try c.decode(CalendarDay.self, forKey: .startsOn)
        endsOn = try c.decodeIfPresent(CalendarDay.self, forKey: .endsOn)
        categoryIds = try c.decodeIfPresent([UUID].self, forKey: .categoryIds) ?? []
        accountIds = try c.decodeIfPresent([UUID].self, forKey: .accountIds) ?? []
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(householdId, forKey: .householdId)
        try c.encode(name, forKey: .name)
        try c.encode(limit.minor, forKey: .limitMinor)
        try c.encode(startsOn, forKey: .startsOn)
        try c.encode(endsOn, forKey: .endsOn)
        try c.encode(categoryIds, forKey: .categoryIds)
        try c.encode(accountIds, forKey: .accountIds)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}
