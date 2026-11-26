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
        let active = accounts.filter { !$0.isArchived && $0.includeInNetWorth }
        return NetWorthPoint(month: MonthKey(today), balances: active.map { balances[$0.id] ?? $0.openingBalance })
    }

    /// Patrimonio al final de cada uno de los últimos `months` meses (el último, el de `through`),
    /// rehecho a partir del saldo inicial de cada cuenta y sus movimientos.
    ///
    /// Reglas (las mismas en Android, con vectores en `testdata/vectors/net_worth.json`):
    /// - El saldo inicial cuenta desde el día de alta de la cuenta (`createdAt`), o desde su primer
    ///   movimiento si es anterior (movimientos importados): es el saldo de antes de todos sus movimientos.
    ///   Antes de eso la cuenta no existía y suma 0. Sin `createdAt` cuenta desde siempre.
    /// - Una cuenta archivada sigue en los meses que terminan antes del día en que se archivó.
    /// - Las inversiones no suman: su valor no es el saldo de ninguna cuenta, no hay precio de cada fin
    ///   de mes y el dinero de una cartera puede estar ya en una cuenta de inversión (se contaría dos veces).
    public static func history(accounts: [Account], movements: [Movement], months: Int = 12,
                               through: MonthKey) -> [NetWorthPoint] {
        let counted = accounts.filter(\.includeInNetWorth)
        let ids = Set(counted.map(\.id))
        let byAccount = Dictionary(grouping: movements.filter { ids.contains($0.accountId) }, by: \.accountId)
            .mapValues { $0.sorted { $0.bookedOn < $1.bookedOn } }
        var points: [NetWorthPoint] = []
        for offset in stride(from: months - 1, through: 0, by: -1) {
            let month = through.adding(months: -offset)
            let lastDay = month.adding(months: 1).firstDay.adding(days: -1)
            let balances = counted.compactMap { account -> Money? in
                if let archived = account.archivedAt, CalendarDay(archived) <= lastDay { return nil }
                let done = (byAccount[account.id] ?? []).prefix { $0.bookedOn <= lastDay }
                let opened = account.createdAt.map { CalendarDay($0) <= lastDay } ?? true
                guard opened || !done.isEmpty else { return nil }
                let moved = done.reduce(0) { $0 + $1.amount.minor }
                return Money(minor: account.openingBalance.minor + moved, currency: account.currency)
            }
            points.append(NetWorthPoint(month: month, balances: balances))
        }
        return points
    }
}

/// Predicción del patrimonio hasta final de año: sigue el cambio medio mensual de los últimos meses.
public struct NetWorthProjection: Hashable, Sendable {
    public struct Point: Hashable, Sendable, Identifiable {
        public var month: MonthKey
        public var net: Money
        public var id: MonthKey { month }
    }

    /// Cambio medio al mes que se ha usado.
    public var monthlyChange: Money
    /// Un punto por mes, desde el último real (incluido) hasta diciembre.
    public var points: [Point]

    public var endOfYear: Money { points.last?.net ?? .zero }

    /// - Parameter history: patrimonio a final de cada mes, del más antiguo al actual (el último es el mes en curso).
    ///   Se usan como mucho los últimos 6 cambios. Hacen falta al menos 2 puntos, y no se predice en diciembre.
    public init?(history: [NetWorthPoint], maxChanges: Int = 6) {
        guard history.count >= 2, let last = history.last, last.month.month < 12 else { return nil }
        let recent = Array(history.suffix(maxChanges + 1))
        let changes = recent.count - 1
        let total = recent.last!.net.minor - recent.first!.net.minor
        let average = Int((Double(total) / Double(changes)).rounded())
        monthlyChange = Money(minor: average)
        var points = [Point(month: last.month, net: last.net)]
        var month = last.month
        var net = last.net.minor
        while month.month < 12 {
            month = month.adding(months: 1)
            net += average
            points.append(Point(month: month, net: Money(minor: net)))
        }
        self.points = points
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

    /// Días que abarca el informe (los dos extremos incluidos).
    public var dayCount: Int { range.lowerBound.days(until: range.upperBound) + 1 }

    /// Media por día del periodo, redondeada al céntimo.
    public var averagePerDay: Money {
        let days = max(1, dayCount)
        return Money(minor: Int((Double(total.minor) / Double(days)).rounded()))
    }

    /// Cambio frente a otro informe (normalmente el del periodo anterior): diferencia y porcentaje.
    /// El porcentaje es nil si antes no había nada con qué comparar.
    public func change(from previous: SpendingReport) -> (difference: Money, percent: Int?) {
        let difference = total - previous.total
        guard previous.total.minor > 0 else { return (difference, nil) }
        let percent = (Double(difference.minor) / Double(previous.total.minor) * 100).rounded()
        return (difference, Int(percent))
    }

    public var averagePerMonth: Money {
        byMonth.isEmpty ? .zero : Money(minor: (total.minor + byMonth.count / 2) / byMonth.count)
    }

    /// - Parameter categoryIds: si no está vacío, sólo esas categorías.
    /// - Parameter accountIds: si no está vacío, sólo esas cuentas.
    /// - Parameter monthStartDay: día en que empieza el mes del hogar; los meses de `byMonth` son esos periodos.
    public init(movements: [Movement], categories: [BudgetCategory], range: ClosedRange<CalendarDay>,
                kind: Kind = .expense, categoryIds: Set<UUID> = [], accountIds: Set<UUID> = [], monthStartDay: Int = 1) {
        self.kind = kind
        self.range = range
        let byId = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var totals: [String: (title: String, icon: String?, minor: Int, count: Int)] = [:]
        var months: [MonthKey: Int] = [:]
        var total = 0
        for movement in movements where !movement.excluded && range.contains(movement.bookedOn) {
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
            months[MonthKey.containing(movement.bookedOn, startDay: monthStartDay), default: 0] += value
            total += value
        }
        self.total = Money(minor: total)
        byCategory = totals.map { key, entry in
            Row(id: key, title: entry.title, icon: entry.icon, amount: Money(minor: entry.minor), count: entry.count,
                share: total > 0 ? max(0, Double(entry.minor) / Double(total)) : 0)
        }
        .sorted { $0.amount.minor != $1.amount.minor ? $0.amount.minor > $1.amount.minor : $0.title < $1.title }

        var monthList: [MonthTotal] = []
        var month = MonthKey.containing(range.lowerBound, startDay: monthStartDay)
        let last = MonthKey.containing(range.upperBound, startDay: monthStartDay)
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

    /// El mismo tramo justo antes, para comparar: este mes hasta hoy frente al mes pasado hasta el mismo día,
    /// los últimos 3 meses frente a los 3 anteriores, este año hasta hoy frente al año pasado hasta el mismo día.
    public func previousRange(today: CalendarDay = CalendarDay(), monthStartDay: Int = 1) -> ClosedRange<CalendarDay> {
        let current = range(today: today, monthStartDay: monthStartDay)
        let shift: Int
        switch self {
        case .thisMonth, .lastMonth: shift = 1
        case .last3Months: shift = 3
        case .last6Months: shift = 6
        case .thisYear, .last12Months: shift = 12
        }
        let start = Self.shifted(current.lowerBound, months: -shift, startDay: monthStartDay)
        // Un mes completo se compara con el periodo anterior completo (31 de marzo → 28 de febrero, no 3 de marzo).
        let end = self == .lastMonth
            ? MonthKey.containing(start, startDay: monthStartDay).period(startDay: monthStartDay).upperBound
            : Self.shifted(current.upperBound, months: -shift, startDay: monthStartDay)
        return start...max(start, end)
    }

    /// Mismo día dentro de su periodo del hogar, [months] meses antes; sin pasarse del final de ese periodo.
    private static func shifted(_ day: CalendarDay, months: Int, startDay: Int) -> CalendarDay {
        let key = MonthKey.containing(day, startDay: startDay)
        let offset = key.period(startDay: startDay).lowerBound.days(until: day)
        let target = key.adding(months: months).period(startDay: startDay)
        return min(target.upperBound, target.lowerBound.adding(days: offset))
    }

    /// "el mes pasado", "los 3 meses anteriores"… para la frase de la comparación.
    public var previousTitle: String {
        switch self {
        case .thisMonth: "el mes pasado a estas alturas"
        case .lastMonth: "el mes anterior"
        case .last3Months: "los 3 meses anteriores"
        case .last6Months: "los 6 meses anteriores"
        case .thisYear: "el año pasado a estas alturas"
        case .last12Months: "los 12 meses anteriores"
        }
    }

    /// Periodos del hogar: empiezan el día `monthStartDay`, como el presupuesto. "Este año" son los periodos
    /// del año del mes en curso (con inicio 25, el primero es del 25 de diciembre anterior).
    public func range(today: CalendarDay = CalendarDay(), monthStartDay: Int = 1) -> ClosedRange<CalendarDay> {
        let month = MonthKey.containing(today, startDay: monthStartDay)
        switch self {
        case .thisMonth: return month.period(startDay: monthStartDay).lowerBound...today
        case .lastMonth: return month.adding(months: -1).period(startDay: monthStartDay)
        case .last3Months: return month.adding(months: -2).period(startDay: monthStartDay).lowerBound...today
        case .last6Months: return month.adding(months: -5).period(startDay: monthStartDay).lowerBound...today
        case .thisYear: return MonthKey(year: month.year, month: 1).period(startDay: monthStartDay).lowerBound...today
        case .last12Months: return month.adding(months: -11).period(startDay: monthStartDay).lowerBound...today
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
        // Por periodo: el id lleva el primer día, para que cada periodo avise una vez.
        let month = report.period.lowerBound.day == 1
            ? String(format: "%04d-%02d", report.month.year, report.month.month)
            : report.period.lowerBound.iso
        let thresholds = [min(max(report.warnPercent, 50), 100), 100]
        var alerts: [BudgetAlert] = []
        for line in report.lines {
            guard let limit = line.limit, limit.minor > 0 else { continue }
            if let alert = alert(id: "\(prefix)\(month).\(line.category.id.uuidString)", name: line.category.name,
                                 spent: line.spent, limit: line.available ?? limit, thresholds: thresholds) {
                alerts.append(alert)
            }
        }
        for group in report.groups where group.allocated.minor > 0 && group.group != .savings {
            if let alert = alert(id: "\(prefix)\(month).\(group.group.rawValue)", name: group.group.title,
                                 spent: group.spent, limit: group.allocated, thresholds: thresholds) {
                alerts.append(alert)
            }
        }
        return alerts
    }

    private static func alert(id: String, name: String, spent: Money, limit: Money,
                              thresholds: [Int] = BudgetAlertPlanner.thresholds) -> BudgetAlert? {
        guard limit.minor > 0 else { return nil }
        let percent = spent.minor * 100 / limit.minor
        guard let reached = thresholds.last(where: { percent >= $0 }) else { return nil }
        if reached >= 100 {
            return BudgetAlert(id: "\(id).\(reached)", title: "Te has pasado en \(name)",
                               body: "Llevas \(spent.formatted()) de \(limit.formatted()) en este periodo.")
        }
        return BudgetAlert(id: "\(id).\(reached)", title: "\(name): ya llevas el \(percent) %",
                           body: "Has gastado \(spent.formatted()) de \(limit.formatted()). Quedan \((limit - spent).formatted()).")
    }
}

// MARK: - Tramos del patrimonio (igual que en Android)

/// Tramo del gráfico de patrimonio: 1M, 6M, 1A o Todo.
public enum NetWorthRange: String, CaseIterable, Sendable, Identifiable {
    case oneMonth, sixMonths, oneYear, all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oneMonth: "1M"
        case .sixMonths: "6M"
        case .oneYear: "1A"
        case .all: "Todo"
        }
    }

    /// Para la frase del cambio: "+120 € en 6 meses".
    public var caption: String {
        switch self {
        case .oneMonth: "en 1 mes"
        case .sixMonths: "en 6 meses"
        case .oneYear: "en 1 año"
        case .all: "desde el principio"
        }
    }

    /// Puntos del gráfico (final de cada mes); el primero es el punto de partida.
    /// "Todo" va desde el mes del primer movimiento, y siempre hay al menos 2.
    public func months(firstMovement: CalendarDay?, through: MonthKey) -> Int {
        switch self {
        case .oneMonth: return 2
        case .sixMonths: return 7
        case .oneYear: return 13
        case .all:
            guard let first = firstMovement.map(MonthKey.init) else { return 2 }
            let span = (through.year - first.year) * 12 + (through.month - first.month) + 1
            return max(2, span)
        }
    }

    /// Cuánto ha cambiado el patrimonio entre el primer y el último punto.
    public static func change(_ history: [NetWorthPoint]) -> Money {
        guard let first = history.first, let last = history.last else { return .zero }
        return last.net - first.net
    }
}

// MARK: - Resumen del mes (igual que en Android)

public enum MonthSummary {
    /// Lo gastado en el mes del hogar de `today` hasta hoy. Los traspasos no cuentan; una devolución resta.
    public static func spent(movements: [Movement], categories: [BudgetCategory],
                             today: CalendarDay = CalendarDay(), monthStartDay: Int = 1) -> Money {
        SpendingReport(movements: movements, categories: categories,
                       range: ReportPeriod.thisMonth.range(today: today, monthStartDay: monthStartDay),
                       kind: .expense, monthStartDay: monthStartDay).total
    }

    /// Cuánto ha cambiado el patrimonio este mes: la suma de los movimientos del mes en cuentas no archivadas.
    /// Los traspasos entre cuentas propias se anulan solos.
    public static func netWorthChange(accounts: [Account], movements: [Movement],
                                      today: CalendarDay = CalendarDay()) -> Money {
        let ids = Set(accounts.filter { !$0.isArchived && $0.includeInNetWorth }.map(\.id))
        let start = MonthKey(today).firstDay
        return Money(minor: movements
            .filter { ids.contains($0.accountId) && $0.bookedOn >= start && $0.bookedOn <= today }
            .reduce(0) { $0 + $1.amount.minor })
    }
}

// MARK: - Categoría que más sube (igual que en Android)

/// La categoría de gasto que más sube de un mes al anterior.
public struct BiggestRise: Hashable, Sendable {
    public var title: String
    public var icon: String?
    /// Subida en %, o nil si el mes anterior no se gastó nada en ella.
    public var percent: Int?
    public var previous: MonthKey

    /// - Parameter month: mes del hogar (con `MonthKey.containing`); cada mes abarca su `MonthKey.period`.
    public static func find(movements: [Movement], categories: [BudgetCategory], month: MonthKey,
                            monthStartDay: Int = 1) -> BiggestRise? {
        func rows(_ m: MonthKey) -> [String: SpendingReport.Row] {
            let report = SpendingReport(movements: movements, categories: categories, range: m.period(startDay: monthStartDay),
                                        kind: .expense)
            return Dictionary(report.byCategory.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        let previous = month.adding(months: -1)
        let before = rows(previous)
        let rises = rows(month).values
            .map { ($0, $0.amount.minor - (before[$0.id]?.amount.minor ?? 0)) }
            .filter { $0.1 > 0 }
        guard let best = rises.max(by: { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.title > $1.0.title }) else { return nil }
        let old = before[best.0.id]?.amount.minor ?? 0
        return BiggestRise(title: best.0.title, icon: best.0.icon,
                           percent: old > 0 ? best.1 * 100 / old : nil, previous: previous)
    }
}
