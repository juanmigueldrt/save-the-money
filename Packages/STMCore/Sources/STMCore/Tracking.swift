import Foundation

// MARK: - Patrimonio neto

/// Lo que se tiene menos lo que se debe, con las cuentas no archivadas.
/// Una cuenta con saldo negativo (tarjeta, préstamo, descubierto) cuenta como deuda.
public struct NetWorthPoint: Hashable, Sendable, Identifiable {
    public var month: MonthKey
    /// Suma de los saldos positivos.
    public var assets: Money
    /// Suma de los saldos negativos, en positivo.
    public var liabilities: Money

    public var net: Money { assets - liabilities }
    public var id: MonthKey { month }

    public init(month: MonthKey, assets: Money, liabilities: Money) {
        self.month = month
        self.assets = assets
        self.liabilities = liabilities
    }

    public init(month: MonthKey, balances: [Money]) {
        self.init(month: month,
                  assets: Money(minor: balances.filter { $0.minor > 0 }.reduce(0) { $0 + $1.minor }),
                  liabilities: Money(minor: balances.filter { $0.minor < 0 }.reduce(0) { $0 - $1.minor }))
    }
}

public enum NetWorth {
    /// Patrimonio de hoy con los saldos actuales.
    public static func current(accounts: [Account], balances: [UUID: Money], today: CalendarDay = CalendarDay()) -> NetWorthPoint {
        let active = accounts.filter { !$0.isArchived }
        return NetWorthPoint(month: MonthKey(today), balances: active.map { balances[$0.id] ?? $0.openingBalance })
    }

    /// Patrimonio al final de cada uno de los últimos `months` meses (el último, el de `through`),
    /// rehecho a partir del saldo inicial de cada cuenta y sus movimientos.
    public static func history(accounts: [Account], movements: [Movement], months: Int = 12,
                               through: MonthKey) -> [NetWorthPoint] {
        let active = accounts.filter { !$0.isArchived }
        let ids = Set(active.map(\.id))
        let byAccount = Dictionary(grouping: movements.filter { ids.contains($0.accountId) }, by: \.accountId)
            .mapValues { $0.sorted { $0.bookedOn < $1.bookedOn } }
        var points: [NetWorthPoint] = []
        for offset in stride(from: months - 1, through: 0, by: -1) {
            let month = through.adding(months: -offset)
            let lastDay = month.adding(months: 1).firstDay.adding(days: -1)
            let balances = active.map { account -> Money in
                let moved = (byAccount[account.id] ?? []).prefix { $0.bookedOn <= lastDay }.reduce(0) { $0 + $1.amount.minor }
                return Money(minor: account.openingBalance.minor + moved, currency: account.currency)
            }
            points.append(NetWorthPoint(month: month, balances: balances))
        }
        return points
    }
}

// MARK: - Score crediticio

/// Score crediticio apuntado a mano. Es personal: sólo lo ve quien lo apunta.
public struct CreditScore: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var score: Int
    public var maxScore: Int
    public var provider: String?
    public var recordedOn: CalendarDay
    public var note: String?

    public init(id: UUID = UUID(), score: Int, maxScore: Int = 850, provider: String? = nil,
                recordedOn: CalendarDay = CalendarDay(), note: String? = nil) {
        self.id = id
        self.score = score
        self.maxScore = maxScore
        self.provider = provider
        self.recordedOn = recordedOn
        self.note = note
    }

    public enum Rating: String, Sendable, CaseIterable {
        case excellent, good, fair, poor

        public var title: String {
            switch self {
            case .excellent: "Excelente"
            case .good: "Bueno"
            case .fair: "Regular"
            case .poor: "Mejorable"
            }
        }
    }

    public var fraction: Double { maxScore > 0 ? min(1, max(0, Double(score) / Double(maxScore))) : 0 }

    /// Tramos orientativos sobre la escala del proveedor (en 850: 740, 670 y 580).
    public var rating: Rating {
        switch fraction {
        case 0.87...: .excellent
        case 0.79..<0.87: .good
        case 0.68..<0.79: .fair
        default: .poor
        }
    }

    public var trimmedProvider: String? {
        let text = provider?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    public var issue: String? {
        if !(100...1000).contains(maxScore) { return "La escala tiene que estar entre 100 y 1000." }
        if score < 0 || score > maxScore { return "El score tiene que estar entre 0 y \(maxScore)." }
        if let provider = trimmedProvider, provider.count > 60 { return "El nombre del proveedor es demasiado largo." }
        if let note, note.count > 200 { return "La nota es demasiado larga." }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, score, provider, note
        case maxScore = "max_score"
        case recordedOn = "recorded_on"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        score = try c.decode(Int.self, forKey: .score)
        maxScore = try c.decode(Int.self, forKey: .maxScore)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        recordedOn = try c.decode(CalendarDay.self, forKey: .recordedOn)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    /// Sólo las columnas que se escriben; el dueño lo pone el servidor.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(score, forKey: .score)
        try c.encode(maxScore, forKey: .maxScore)
        try c.encode(trimmedProvider, forKey: .provider)
        try c.encode(recordedOn, forKey: .recordedOn)
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try c.encode(cleanNote?.isEmpty == false ? cleanNote : nil, forKey: .note)
    }
}

// MARK: - Informes

/// Informe de gastos o ingresos de un periodo, por categoría y por mes.
public struct SpendingReport: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case expense, income

        public var title: String {
            switch self {
            case .expense: "Gastos"
            case .income: "Ingresos"
            }
        }
    }

    public struct Row: Hashable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var icon: String?
        public var amount: Money
        public var count: Int
        /// Parte del total, entre 0 y 1.
        public var share: Double
    }

    public struct MonthTotal: Hashable, Sendable, Identifiable {
        public var month: MonthKey
        public var amount: Money
        public var id: MonthKey { month }
    }

    public var kind: Kind
    public var range: ClosedRange<CalendarDay>
    public var total: Money
    public var byCategory: [Row]
    public var byMonth: [MonthTotal]

    public var averagePerMonth: Money {
        byMonth.isEmpty ? .zero : Money(minor: (total.minor + byMonth.count / 2) / byMonth.count)
    }

    /// - Parameter categoryIds: si no está vacío, sólo esas categorías.
    /// - Parameter accountIds: si no está vacío, sólo esas cuentas.
    public init(movements: [Movement], categories: [BudgetCategory], range: ClosedRange<CalendarDay>,
                kind: Kind = .expense, categoryIds: Set<UUID> = [], accountIds: Set<UUID> = []) {
        self.kind = kind
        self.range = range
        let byId = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var totals: [String: (title: String, icon: String?, minor: Int, count: Int)] = [:]
        var months: [MonthKey: Int] = [:]
        var total = 0
        for movement in movements where range.contains(movement.bookedOn) {
            if !accountIds.isEmpty && !accountIds.contains(movement.accountId) { continue }
            let category = movement.categoryId.flatMap { byId[$0] }
            if category?.kind == .transfer { continue }
            let matches: Bool
            switch kind {
            case .expense: matches = category.map { $0.kind == .expense } ?? movement.amount.isNegative
            case .income: matches = category.map { $0.kind == .income } ?? !movement.amount.isNegative
            }
            guard matches else { continue }
            if !categoryIds.isEmpty && !(category.map { categoryIds.contains($0.id) } ?? false) { continue }
            // Gastos en positivo; una devolución dentro de una categoría de gasto lo resta.
            let value = kind == .expense ? -movement.amount.minor : movement.amount.minor
            let key = category?.id.uuidString ?? "sin-categoria"
            var entry = totals[key] ?? (title: category?.name ?? "Sin categoría", icon: category?.icon, minor: 0, count: 0)
            entry.minor += value
            entry.count += 1
            totals[key] = entry
            months[MonthKey(movement.bookedOn), default: 0] += value
            total += value
        }
        self.total = Money(minor: total)
        byCategory = totals.map { key, entry in
            Row(id: key, title: entry.title, icon: entry.icon, amount: Money(minor: entry.minor), count: entry.count,
                share: total > 0 ? max(0, Double(entry.minor) / Double(total)) : 0)
        }
        .sorted { $0.amount.minor != $1.amount.minor ? $0.amount.minor > $1.amount.minor : $0.title < $1.title }

        var monthList: [MonthTotal] = []
        var month = MonthKey(range.lowerBound)
        let last = MonthKey(range.upperBound)
        while month <= last {
            monthList.append(MonthTotal(month: month, amount: Money(minor: months[month] ?? 0)))
            month = month.adding(months: 1)
        }
        byMonth = monthList
    }
}

/// Periodos rápidos para los informes.
public enum ReportPeriod: String, CaseIterable, Sendable, Identifiable {
    case thisMonth, lastMonth, last3Months, last6Months, thisYear, last12Months

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .thisMonth: "Este mes"
        case .lastMonth: "El mes pasado"
        case .last3Months: "Últimos 3 meses"
        case .last6Months: "Últimos 6 meses"
        case .thisYear: "Este año"
        case .last12Months: "Últimos 12 meses"
        }
    }

    public func range(today: CalendarDay = CalendarDay()) -> ClosedRange<CalendarDay> {
        let month = MonthKey(today)
        func lastDay(_ m: MonthKey) -> CalendarDay { m.adding(months: 1).firstDay.adding(days: -1) }
        switch self {
        case .thisMonth: return month.firstDay...today
        case .lastMonth: return month.adding(months: -1).firstDay...lastDay(month.adding(months: -1))
        case .last3Months: return month.adding(months: -2).firstDay...today
        case .last6Months: return month.adding(months: -5).firstDay...today
        case .thisYear: return MonthKey(year: today.year, month: 1).firstDay...today
        case .last12Months: return month.adding(months: -11).firstDay...today
        }
    }
}

// MARK: - Presupuesto flexible

/// Presupuesto flexible: de lo que entra se apartan los pagos fijos y el ahorro,
/// y lo que queda es un solo número para todo lo demás.
public struct FlexBudget: Hashable, Sendable {
    public var income: Money
    /// Pagos fijos previstos del mes (suscripciones y gastos esenciales).
    public var fixed: Money
    /// Ahorro previsto según el reparto del presupuesto.
    public var savings: Money
    /// Lo gastado en categorías de pagos fijos.
    public var fixedSpent: Money
    /// Lo gastado en todo lo demás (incluido lo que no tiene categoría).
    public var flexibleSpent: Money
    public var daysLeft: Int

    /// Lo que se puede gastar en lo flexible este mes.
    public var flexible: Money { income - fixed - savings }
    public var remaining: Money { flexible - flexibleSpent }
    public var fraction: Double {
        guard flexible.minor > 0 else { return flexibleSpent.minor > 0 ? 1 : 0 }
        return min(1, max(0, Double(flexibleSpent.minor) / Double(flexible.minor)))
    }
    public var isOver: Bool { remaining.isNegative }
    /// Lo que se puede gastar al día hasta final de mes.
    public var perDay: Money? {
        guard daysLeft > 0, remaining.minor > 0 else { return nil }
        return Money(minor: remaining.minor / daysLeft)
    }

    public init(report: BudgetReport, series: [RecurringSeries], today: CalendarDay) {
        income = report.base
        savings = report.groups.first { $0.group == .savings }?.allocated ?? .zero
        let start = report.period.lowerBound
        let active = series.filter { !$0.isArchived && $0.kind != .income }
        fixed = active.monthlyTotal(of: .subscription, on: start) + active.monthlyTotal(of: .essential, on: start)
        let fixedCategories = Set(active.compactMap(\.categoryId))
        var fixedSpent = 0, flexibleSpent = report.uncategorized.minor
        for line in report.lines {
            if fixedCategories.contains(line.category.id) {
                fixedSpent += line.spent.minor
            } else if line.category.budgetGroup == .savings || line.category.budgetGroup == nil {
                // El ahorro va aparte; las categorías sin grupo ya están en uncategorized.
                continue
            } else {
                flexibleSpent += line.spent.minor
            }
        }
        self.fixedSpent = Money(minor: fixedSpent)
        self.flexibleSpent = Money(minor: flexibleSpent)
        daysLeft = report.period.contains(today) ? today.days(until: report.period.upperBound) + 1 : 0
    }
}

// MARK: - Avisos de límites

/// Avisos de que una categoría o un grupo del presupuesto llega al 80 % o se pasa.
public struct BudgetAlert: Hashable, Sendable, Identifiable {
    /// Estable por mes, categoría y umbral: así cada aviso sale una sola vez.
    public var id: String
    public var title: String
    public var body: String
}

public enum BudgetAlertPlanner {
    public static let prefix = "stm.budget."
    public static let thresholds = [80, 100]

    public static func alerts(for report: BudgetReport) -> [BudgetAlert] {
        let month = String(format: "%04d-%02d", report.month.year, report.month.month)
        var alerts: [BudgetAlert] = []
        for line in report.lines {
            guard let limit = line.limit, limit.minor > 0 else { continue }
            if let alert = alert(id: "\(prefix)\(month).\(line.category.id.uuidString)", name: line.category.name,
                                 spent: line.spent, limit: limit) {
                alerts.append(alert)
            }
        }
        for group in report.groups where group.allocated.minor > 0 && group.group != .savings {
            if let alert = alert(id: "\(prefix)\(month).\(group.group.rawValue)", name: group.group.title,
                                 spent: group.spent, limit: group.allocated) {
                alerts.append(alert)
            }
        }
        return alerts
    }

    private static func alert(id: String, name: String, spent: Money, limit: Money) -> BudgetAlert? {
        let percent = spent.minor * 100 / limit.minor
        guard let reached = thresholds.last(where: { percent >= $0 }) else { return nil }
        if reached >= 100 {
            return BudgetAlert(id: "\(id).\(reached)", title: "Te has pasado en \(name)",
                               body: "Llevas \(spent.formatted()) de \(limit.formatted()) este mes.")
        }
        return BudgetAlert(id: "\(id).\(reached)", title: "\(name): ya llevas el \(percent) %",
                           body: "Has gastado \(spent.formatted()) de \(limit.formatted()). Quedan \((limit - spent).formatted()).")
    }
}
