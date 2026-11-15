import Foundation

// Resumen semanal: la última semana completa (de lunes a domingo) frente a la anterior,
// los gastos más grandes, las categorías que más suman y un mapa de calor por día de las
// últimas semanas. Cuenta como los informes: sin traspasos ni movimientos excluidos.

extension CalendarDay {
    /// 0 = lunes … 6 = domingo.
    public var weekdayIndex: Int { ((ordinal % 7) + 7 + 3) % 7 }

    /// El lunes de la semana de ese día.
    public var startOfWeek: CalendarDay { adding(days: -weekdayIndex) }
}

public struct WeeklySummary: Hashable, Sendable {
    public struct Week: Hashable, Sendable {
        public var start: CalendarDay
        public var range: ClosedRange<CalendarDay> { start...start.adding(days: 6) }
        public var spent: Money
        public var income: Money
    }

    /// Un día del mapa de calor.
    public struct Day: Hashable, Sendable, Identifiable {
        public var day: CalendarDay
        public var spent: Money
        /// 0...1 frente al día que más se gastó del mapa.
        public var intensity: Double
        public var id: CalendarDay { day }
    }

    public var week: Week
    public var previous: Week
    /// Hasta 5, de mayor a menor.
    public var biggest: [Movement]
    /// Hasta 5 categorías de gasto de la semana.
    public var topCategories: [SpendingReport.Row]
    /// Semanas del mapa (de la más antigua a la más reciente), cada una de lunes a domingo.
    public var heatmap: [[Day]]

    /// Diferencia de gasto con la semana anterior y su porcentaje (nil si la anterior fue 0).
    public var change: (difference: Money, percent: Int?) {
        let difference = week.spent - previous.spent
        guard previous.spent.minor > 0 else { return (difference, nil) }
        return (difference, Int((Double(difference.minor) / Double(previous.spent.minor) * 100).rounded()))
    }

    /// - Parameter today: la semana del resumen es la última completa antes de hoy (la que acabó
    ///   el domingo pasado). Si `includeCurrent`, la que está en curso.
    public init(movements: [Movement], categories: [BudgetCategory], today: CalendarDay,
                includeCurrent: Bool = false, heatmapWeeks: Int = 6) {
        let thisMonday = today.startOfWeek
        let start = includeCurrent ? thisMonday : thisMonday.adding(days: -7)
        func makeWeek(_ monday: CalendarDay) -> Week {
            let range = monday...monday.adding(days: 6)
            return Week(start: monday,
                        spent: SpendingReport(movements: movements, categories: categories, range: range, kind: .expense).total,
                        income: SpendingReport(movements: movements, categories: categories, range: range, kind: .income).total)
        }
        let current = makeWeek(start)
        week = current
        previous = makeWeek(start.adding(days: -7))

        let expenses = Self.expenses(movements: movements, categories: categories)
        biggest = Array(expenses.filter { current.range.contains($0.bookedOn) }
            .sorted { $0.amount.minor != $1.amount.minor ? $0.amount.minor < $1.amount.minor : $0.bookedOn > $1.bookedOn }
            .prefix(5))
        topCategories = Array(SpendingReport(movements: movements, categories: categories, range: current.range, kind: .expense)
            .byCategory.filter { $0.amount.minor > 0 }.prefix(5))

        let weeks = max(1, heatmapWeeks)
        let firstMonday = start.adding(days: -7 * (weeks - 1))
        var perDay: [CalendarDay: Int] = [:]
        for movement in expenses where movement.bookedOn >= firstMonday && movement.bookedOn <= start.adding(days: 6) {
            perDay[movement.bookedOn, default: 0] += -movement.amount.minor
        }
        let peak = max(1, perDay.values.max() ?? 0)
        heatmap = (0..<weeks).map { w in
            (0..<7).map { d in
                let day = firstMonday.adding(days: 7 * w + d)
                let spent = max(0, perDay[day] ?? 0)
                return Day(day: day, spent: Money(minor: spent), intensity: Double(spent) / Double(peak))
            }
        }
    }

    /// Gastos de verdad: negativos, no excluidos, ni traspasos ni ingresos.
    static func expenses(movements: [Movement], categories: [BudgetCategory]) -> [Movement] {
        let byId = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return movements.filter { movement in
            guard !movement.excluded, movement.amount.isNegative else { return false }
            guard let category = movement.categoryId.flatMap({ byId[$0] }) else { return true }
            return category.kind == .expense
        }
    }

    /// "10 – 16 nov".
    public var title: String { "\(week.start.dayMonthText) – \(week.start.adding(days: 6).dayMonthText)" }

    /// Texto corto para el aviso del lunes.
    public var notificationBody: String {
        var text = "Gastaste \(week.spent.formatted())"
        if let percent = change.percent, percent != 0 {
            text += percent > 0 ? ", un \(percent) % más que la semana anterior" : ", un \(-percent) % menos que la semana anterior"
        }
        if let top = topCategories.first { text += ". Lo que más: \(top.title)" }
        return text + "."
    }
}

// MARK: - Avisos de hábito

public enum HabitReminderPlanner {
    /// Prefijo de los avisos de hábito (recordatorio para apuntar y resumen semanal).
    public static let prefix = "stm.habit."

    /// Recordatorio para apuntar gastos los próximos `days` días a esa hora (o sólo los domingos si `weekly`).
    public static func logReminders(today: CalendarDay, hour: Int, weekly: Bool, days: Int = 21) -> [PlannedReminder] {
        (0..<days).compactMap { offset in
            let day = today.adding(days: offset)
            if weekly && day.weekdayIndex != 6 { return nil }
            return PlannedReminder(id: "\(prefix)log.\(day.iso)", fireOn: day, hour: hour,
                                   title: "¿Has apuntado tus gastos?",
                                   body: weekly ? "Tómate un minuto para repasar los gastos de la semana."
                                                : "Apunta lo que has gastado hoy; es un momento.")
        }
    }

    /// Aviso del resumen semanal los próximos lunes.
    public static func weeklySummary(today: CalendarDay, hour: Int = 9, weeks: Int = 3) -> [PlannedReminder] {
        let nextMonday = today.weekdayIndex == 0 ? today : today.startOfWeek.adding(days: 7)
        return (0..<weeks).map { w in
            let day = nextMonday.adding(days: 7 * w)
            return PlannedReminder(id: "\(prefix)weekly.\(day.iso)", fireOn: day, hour: hour,
                                   title: "Tu resumen de la semana",
                                   body: "Mira en qué se fue el dinero la semana pasada.")
        }
    }
}
