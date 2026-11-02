import Foundation

/// Presupuesto de un hogar para un mes: ingresos previstos, reparto por grupos
/// (50/30/20 por defecto) y, si se quiere, un límite por categoría de gasto.
public struct Budget: Hashable, Sendable {
    public var householdId: UUID
    /// Mes del presupuesto (año y mes; el día se ignora).
    public var month: MonthKey
    public var expectedIncome: Money
    public var template: BudgetTemplate
    /// Límite por categoría de gasto, en positivo.
    public var limits: [UUID: Money]

    public init(householdId: UUID, month: MonthKey, expectedIncome: Money = .zero,
                template: BudgetTemplate = .fiftyThirtyTwenty, limits: [UUID: Money] = [:]) {
        self.householdId = householdId
        self.month = month
        self.expectedIncome = expectedIncome
        self.template = template
        self.limits = limits
    }

    /// El mismo presupuesto para otro mes, para proponer el del mes anterior.
    public func copied(to month: MonthKey) -> Budget {
        var copy = self
        copy.month = month
        return copy
    }

    public var issue: String? {
        if expectedIncome.isNegative { return "Los ingresos previstos no pueden ser negativos." }
        if limits.values.contains(where: \.isNegative) { return "Los límites no pueden ser negativos." }
        return nil
    }
}

/// Año y mes, sin día.
public struct MonthKey: Hashable, Comparable, Sendable, Codable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        precondition((1...12).contains(month), "Mes fuera de rango")
        self.year = year
        self.month = month
    }

    public init(_ day: CalendarDay) {
        self.init(year: day.year, month: day.month)
    }

    public var firstDay: CalendarDay { CalendarDay(year: year, month: month, day: 1)! }

    public func adding(months: Int) -> MonthKey {
        let index = year * 12 + (month - 1) + months
        return MonthKey(year: index / 12, month: index % 12 + 1)
    }

    /// "Noviembre de 2026".
    public var title: String {
        let names = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
                     "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
        return "\(names[month - 1].capitalized) de \(year)"
    }

    /// Días que cuenta como "este mes" un hogar cuyo mes empieza el día `startDay`
    /// (p. ej. el día de cobro). Con 25: del 25 del mes anterior al 24 de este.
    public func period(startDay: Int = 1) -> ClosedRange<CalendarDay> {
        let day = min(max(startDay, 1), 28)
        guard day > 1 else {
            let last = CalendarDay.daysIn(month: month, year: year)
            return firstDay...CalendarDay(year: year, month: month, day: last)!
        }
        let previous = adding(months: -1)
        let start = CalendarDay(year: previous.year, month: previous.month, day: day)!
        let end = CalendarDay(year: year, month: month, day: day - 1)!
        return start...end
    }

    /// Mes al que pertenece un día con ese día de inicio.
    public static func containing(_ day: CalendarDay, startDay: Int = 1) -> MonthKey {
        let start = min(max(startDay, 1), 28)
        let key = MonthKey(day)
        return start > 1 && day.day >= start ? key.adding(months: 1) : key
    }

    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool { (lhs.year, lhs.month) < (rhs.year, rhs.month) }
}

/// Lo que se ha gastado frente a lo previsto en un mes. Se calcula siempre a partir
/// de los movimientos; no se guarda en el servidor.
public struct BudgetReport: Hashable, Sendable {
    public struct CategoryLine: Hashable, Sendable, Identifiable {
        public var category: BudgetCategory
        public var limit: Money?
        public var spent: Money

        public var id: UUID { category.id }

        /// Fracción gastada del límite, entre 0 y 1; nil si no tiene límite.
        public var fraction: Double? {
            guard let limit, limit.minor > 0 else { return nil }
            return min(1, max(0, Double(spent.minor) / Double(limit.minor)))
        }

        public var isOver: Bool { limit.map { spent.minor > $0.minor } ?? false }
    }

    public var month: MonthKey
    public var period: ClosedRange<CalendarDay>
    /// Ingresos reales del periodo (sin transferencias entre cuentas).
    public var income: Money
    /// Lo que se reparte: los ingresos previstos si los hay; si no, los reales.
    public var base: Money
    public var groups: [GroupProgress]
    /// Categorías de gasto con límite o con gasto este mes, por grupo y nombre.
    public var lines: [CategoryLine]
    /// Gastos sin categoría.
    public var uncategorized: Money
    /// De dónde vienen los ingresos: nombre de la categoría (o "Sin categoría") e importe.
    public var incomeSources: [(title: String, amount: Money)]

    public static func == (lhs: BudgetReport, rhs: BudgetReport) -> Bool {
        lhs.month == rhs.month && lhs.income == rhs.income && lhs.base == rhs.base && lhs.groups == rhs.groups
            && lhs.lines == rhs.lines && lhs.uncategorized == rhs.uncategorized
            && lhs.incomeSources.map(\.title) == rhs.incomeSources.map(\.title)
            && lhs.incomeSources.map(\.amount) == rhs.incomeSources.map(\.amount)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(month)
        hasher.combine(income)
        hasher.combine(lines)
    }

    public var totalSpent: Money { groups.reduce(Money.zero) { $0 + $1.spent } + uncategorized }
    /// Ingresos menos gastos: positivo es lo que queda, negativo es que se ha gastado más.
    public var remaining: Money { income - totalSpent }

    public func lines(in group: BudgetGroup) -> [CategoryLine] {
        lines.filter { $0.category.budgetGroup == group }
    }

    public init(budget: Budget?, month: MonthKey, startDay: Int = 1,
                categories: [BudgetCategory], movements: [Movement]) {
        self.month = month
        period = month.period(startDay: startDay)
        let range = period
        let inPeriod = movements.filter { range.contains($0.bookedOn) }
        let byId = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        var income = 0
        var incomeByTitle: [String: Int] = [:]
        var spentByCategory: [UUID: Int] = [:]
        var uncategorized = 0
        for movement in inPeriod {
            let category = movement.categoryId.flatMap { byId[$0] }
            switch category?.kind {
            case .transfer:
                continue
            case .income:
                income += movement.amount.minor
                incomeByTitle[category!.name, default: 0] += movement.amount.minor
            case .expense:
                spentByCategory[category!.id, default: 0] -= movement.amount.minor
            case nil:
                if movement.amount.minor > 0 {
                    income += movement.amount.minor
                    incomeByTitle["Sin categoría", default: 0] += movement.amount.minor
                } else {
                    uncategorized -= movement.amount.minor
                }
            }
        }

        // Las categorías de gasto sin grupo cuentan como gasto sin clasificar.
        for category in categories where category.kind == .expense && category.budgetGroup == nil {
            uncategorized += spentByCategory[category.id] ?? 0
        }
        self.income = Money(minor: income)
        incomeSources = incomeByTitle.filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (title: $0.key, amount: Money(minor: $0.value)) }
        self.uncategorized = Money(minor: uncategorized)
        let template = budget?.template ?? .fiftyThirtyTwenty
        let expected = budget?.expectedIncome ?? .zero
        base = expected.minor > 0 ? expected : Money(minor: max(income, 0))
        let allocation = template.allocate(base)

        groups = BudgetGroup.allCases.map { group in
            let spent = categories.filter { $0.budgetGroup == group }.reduce(0) { $0 + (spentByCategory[$1.id] ?? 0) }
            return GroupProgress(group: group, allocated: allocation[group] ?? .zero, spent: Money(minor: spent))
        }

        let order = Dictionary(uniqueKeysWithValues: BudgetGroup.allCases.enumerated().map { ($1, $0) })
        lines = categories
            .filter { $0.kind == .expense }
            .compactMap { category -> CategoryLine? in
                let limit = budget?.limits[category.id]
                let spent = spentByCategory[category.id] ?? 0
                guard limit != nil || spent != 0 else { return nil }
                return CategoryLine(category: category, limit: limit, spent: Money(minor: spent))
            }
            .sorted {
                let a = order[$0.category.budgetGroup ?? .wants] ?? 3, b = order[$1.category.budgetGroup ?? .wants] ?? 3
                return a != b ? a < b : $0.category.name.localizedStandardCompare($1.category.name) == .orderedAscending
            }
    }
}
