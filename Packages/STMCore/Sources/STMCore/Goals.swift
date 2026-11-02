import Foundation

public enum GoalKind: String, Codable, CaseIterable, Sendable {
    case savings, debt

    public var title: String {
        switch self {
        case .savings: "Ahorro"
        case .debt: "Pagar una deuda"
        }
    }

    public var systemImage: String {
        switch self {
        case .savings: "banknote"
        case .debt: "creditcard"
        }
    }
}

/// Una meta del hogar: juntar una cantidad o terminar de pagar una deuda.
/// Las dos se llevan igual: lo que había al empezar más las aportaciones, frente al objetivo.
public struct Goal: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var householdId: UUID
    public var name: String
    public var kind: GoalKind
    /// Ahorro: lo que se quiere juntar. Deuda: lo que se debía al empezar.
    public var target: Money
    /// Lo que ya estaba ahorrado o pagado antes de llevar la cuenta aquí.
    public var starting: Money
    /// Aportación mensual prevista.
    public var monthlyPlan: Money?
    public var targetOn: CalendarDay?
    public var accountId: UUID?
    public var icon: String?
    public var completedAt: Date?
    public var archivedAt: Date?

    public init(id: UUID = UUID(), householdId: UUID, name: String, kind: GoalKind = .savings,
                target: Money, starting: Money = .zero, monthlyPlan: Money? = nil, targetOn: CalendarDay? = nil,
                accountId: UUID? = nil, icon: String? = nil, completedAt: Date? = nil, archivedAt: Date? = nil) {
        self.id = id
        self.householdId = householdId
        self.name = name
        self.kind = kind
        self.target = target
        self.starting = starting
        self.monthlyPlan = monthlyPlan
        self.targetOn = targetOn
        self.accountId = accountId
        self.icon = icon
        self.completedAt = completedAt
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }
    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var issue: String? {
        if trimmedName.isEmpty { return "Ponle un nombre a la meta." }
        if trimmedName.count > 60 { return "El nombre es demasiado largo." }
        if target.minor <= 0 { return kind == .debt ? "Indica cuánto se debe." : "Indica cuánto quieres juntar." }
        if starting.isNegative { return "Lo que ya tienes no puede ser negativo." }
        if let monthlyPlan, monthlyPlan.isNegative { return "La aportación mensual no puede ser negativa." }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, icon
        case householdId = "household_id"
        case targetMinor = "target_minor"
        case startingMinor = "starting_minor"
        case monthlyPlanMinor = "monthly_plan_minor"
        case targetOn = "target_on"
        case accountId = "account_id"
        case completedAt = "completed_at"
        case archivedAt = "archived_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(GoalKind.self, forKey: .kind)
        target = Money(minor: try c.decode(Int.self, forKey: .targetMinor))
        starting = Money(minor: try c.decode(Int.self, forKey: .startingMinor))
        monthlyPlan = try c.decodeIfPresent(Int.self, forKey: .monthlyPlanMinor).map { Money(minor: $0) }
        targetOn = try c.decodeIfPresent(CalendarDay.self, forKey: .targetOn)
        accountId = try c.decodeIfPresent(UUID.self, forKey: .accountId)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        completedAt = try c.decodeIfPresent(ServerDate.self, forKey: .completedAt)?.date
        archivedAt = try c.decodeIfPresent(ServerDate.self, forKey: .archivedAt)?.date
    }

    /// Codifica las columnas editables (sin id ni hogar, que pone quien inserta).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(trimmedName, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(target.minor, forKey: .targetMinor)
        try c.encode(starting.minor, forKey: .startingMinor)
        try c.encode(monthlyPlan?.minor, forKey: .monthlyPlanMinor)
        try c.encode(targetOn, forKey: .targetOn)
        try c.encode(accountId, forKey: .accountId)
        try c.encode(icon, forKey: .icon)
        try c.encode(completedAt.map(ServerDate.init), forKey: .completedAt)
        try c.encode(archivedAt.map(ServerDate.init), forKey: .archivedAt)
    }
}

/// Dinero que se mete en una meta (o se saca, si es negativo).
public struct GoalContribution: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var householdId: UUID
    public var goalId: UUID
    public var amount: Money
    public var madeOn: CalendarDay
    public var note: String?

    public init(id: UUID = UUID(), householdId: UUID, goalId: UUID, amount: Money, madeOn: CalendarDay, note: String? = nil) {
        self.id = id
        self.householdId = householdId
        self.goalId = goalId
        self.amount = amount
        self.madeOn = madeOn
        self.note = note
    }

    public var issue: String? {
        if amount.minor == 0 { return "El importe no puede ser cero." }
        if let note, note.count > 200 { return "La nota es demasiado larga." }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, note
        case householdId = "household_id"
        case goalId = "goal_id"
        case amountMinor = "amount_minor"
        case madeOn = "made_on"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        goalId = try c.decode(UUID.self, forKey: .goalId)
        amount = Money(minor: try c.decode(Int.self, forKey: .amountMinor))
        madeOn = try c.decode(CalendarDay.self, forKey: .madeOn)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(householdId, forKey: .householdId)
        try c.encode(goalId, forKey: .goalId)
        try c.encode(amount.minor, forKey: .amountMinor)
        try c.encode(madeOn, forKey: .madeOn)
        try c.encode(note, forKey: .note)
    }
}

/// Cómo va una meta hoy y cuándo se alcanzará a este ritmo.
public struct GoalProgress: Hashable, Sendable, Identifiable {
    public var goal: Goal
    /// Suma de las aportaciones.
    public var contributed: Money
    /// Lo que ya hay: lo inicial más las aportaciones.
    public var saved: Money
    /// Lo que falta, nunca negativo.
    public var remaining: Money
    /// Lo que se aporta al mes: lo previsto o, si no hay, la media de los últimos 3 meses.
    public var monthlyPace: Money?
    /// Meses que faltan a ese ritmo; nil si no hay ritmo.
    public var monthsLeft: Int?
    /// Mes en el que se alcanzará a ese ritmo.
    public var projectedMonth: MonthKey?
    /// Lo que habría que aportar al mes para llegar a la fecha objetivo.
    public var neededMonthly: Money?

    public var id: UUID { goal.id }

    public var fraction: Double {
        guard goal.target.minor > 0 else { return 0 }
        return min(1, max(0, Double(saved.minor) / Double(goal.target.minor)))
    }

    public var isReached: Bool { remaining.minor == 0 }

    /// Si hay fecha objetivo y ritmo: si se llega a tiempo.
    public var isOnTrack: Bool? {
        guard let neededMonthly, let monthlyPace else { return nil }
        return monthlyPace.minor >= neededMonthly.minor
    }

    public init(goal: Goal, contributions: [GoalContribution], today: CalendarDay) {
        self.goal = goal
        let own = contributions.filter { $0.goalId == goal.id }
        contributed = own.reduce(Money.zero) { $0 + $1.amount }
        saved = goal.starting + contributed
        remaining = Money(minor: max(0, goal.target.minor - saved.minor))

        if let plan = goal.monthlyPlan, plan.minor > 0 {
            monthlyPace = plan
        } else {
            // Media de los tres meses anteriores al actual.
            let thisMonth = MonthKey(today)
            let from = thisMonth.adding(months: -3).firstDay
            let recent = own.filter { $0.madeOn >= from && $0.madeOn < thisMonth.firstDay }
            let total = recent.reduce(0) { $0 + $1.amount.minor }
            monthlyPace = total > 0 ? Money(minor: (total + 2) / 3) : nil
        }

        if remaining.minor == 0 {
            monthsLeft = 0
            projectedMonth = MonthKey(today)
        } else if let pace = monthlyPace, pace.minor > 0 {
            let months = (remaining.minor + pace.minor - 1) / pace.minor
            monthsLeft = months
            projectedMonth = MonthKey(today).adding(months: months)
        } else {
            monthsLeft = nil
            projectedMonth = nil
        }

        if let targetOn = goal.targetOn, remaining.minor > 0 {
            let start = MonthKey(today), end = MonthKey(targetOn)
            let months = max(1, (end.year - start.year) * 12 + (end.month - start.month))
            neededMonthly = Money(minor: (remaining.minor + months - 1) / months)
        } else {
            neededMonthly = nil
        }
    }
}
