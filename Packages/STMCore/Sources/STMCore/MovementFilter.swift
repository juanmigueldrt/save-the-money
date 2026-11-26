import Foundation

/// Qué tipo de movimiento se quiere ver en la lista.
public enum MovementKindFilter: String, CaseIterable, Sendable, Identifiable {
    case all, expense, income, transfer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "Todos"
        case .expense: "Gastos"
        case .income: "Ingresos"
        case .transfer: "Transferencias"
        }
    }
}

/// Revisados, sin revisar o excluidos del presupuesto.
public enum MovementStatusFilter: String, CaseIterable, Sendable, Identifiable {
    case all, unreviewed, reviewed, excluded

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "Todos"
        case .unreviewed: "Sin revisar"
        case .reviewed: "Revisados"
        case .excluded: "Excluidos"
        }
    }
}

/// Fechas rápidas del filtro de movimientos.
public enum MovementDateFilter: String, CaseIterable, Sendable, Identifiable {
    case all, thisMonth, lastMonth, last30Days, last90Days, thisYear, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "Cualquier fecha"
        case .thisMonth: "Este mes"
        case .lastMonth: "El mes pasado"
        case .last30Days: "Últimos 30 días"
        case .last90Days: "Últimos 90 días"
        case .thisYear: "Este año"
        case .custom: "Fechas a medida"
        }
    }

    /// Días incluidos; nil = sin límite. `custom` usa las fechas dadas (en cualquier orden).
    /// Los meses y el año siguen el mes del hogar (`monthStartDay`), igual que los informes.
    public func range(today: CalendarDay, custom: ClosedRange<CalendarDay>? = nil,
                      monthStartDay: Int = 1) -> ClosedRange<CalendarDay>? {
        switch self {
        case .all: return nil
        case .thisMonth: return ReportPeriod.thisMonth.range(today: today, monthStartDay: monthStartDay)
        case .lastMonth: return ReportPeriod.lastMonth.range(today: today, monthStartDay: monthStartDay)
        case .last30Days: return today.adding(days: -29)...today
        case .last90Days: return today.adding(days: -89)...today
        case .thisYear: return ReportPeriod.thisYear.range(today: today, monthStartDay: monthStartDay)
        case .custom: return custom
        }
    }
}

/// Filtros de la lista de movimientos: cuenta, tipo, categoría, fechas y texto o importe.
public struct MovementFilter: Hashable, Sendable {
    public var accountId: UUID?
    public var kind: MovementKindFilter = .all
    public var categoryId: UUID?
    public var dates: MovementDateFilter = .all
    public var customFrom: CalendarDay?
    public var customThrough: CalendarDay?
    public var status: MovementStatusFilter = .all
    /// Sólo los que llevan esta etiqueta.
    public var tag: String?
    /// Busca en el concepto, las notas, el beneficiario, las etiquetas, el nombre de la categoría o el importe ("12,50", "12.5", "-12,50").
    public var search: String = ""

    public init(accountId: UUID? = nil, kind: MovementKindFilter = .all, categoryId: UUID? = nil,
                dates: MovementDateFilter = .all, customFrom: CalendarDay? = nil, customThrough: CalendarDay? = nil,
                search: String = "", status: MovementStatusFilter = .all, tag: String? = nil) {
        self.status = status
        self.tag = tag
        self.accountId = accountId
        self.kind = kind
        self.categoryId = categoryId
        self.dates = dates
        self.customFrom = customFrom
        self.customThrough = customThrough
        self.search = search
    }

    /// Cuántos filtros (sin contar la búsqueda) hay puestos, para el icono del menú.
    public var activeCount: Int {
        [accountId != nil, kind != .all, categoryId != nil, dates != .all, status != .all, tag != nil].filter { $0 }.count
    }

    public func dateRange(today: CalendarDay, monthStartDay: Int = 1) -> ClosedRange<CalendarDay>? {
        var custom: ClosedRange<CalendarDay>?
        if let from = customFrom, let through = customThrough {
            custom = min(from, through)...max(from, through)
        }
        return dates.range(today: today, custom: custom, monthStartDay: monthStartDay)
    }

    public func apply(to movements: [Movement], categories: [BudgetCategory],
                      today: CalendarDay = CalendarDay(), monthStartDay: Int = 1) -> [Movement] {
        let byId = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let range = dateRange(today: today, monthStartDay: monthStartDay)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let amountQuery = query.isEmpty ? nil : Money(parsing: query)
        return movements.filter { movement in
            if let accountId, movement.accountId != accountId { return false }
            if let categoryId, movement.categoryId != categoryId { return false }
            if let range, !range.contains(movement.bookedOn) { return false }
            if let tag, !movement.tags.contains(tag) { return false }
            switch status {
            case .all: break
            case .unreviewed: if movement.isReviewed { return false }
            case .reviewed: if !movement.isReviewed { return false }
            case .excluded: if !movement.excluded { return false }
            }
            let category = movement.categoryId.flatMap { byId[$0] }
            let isTransfer = category?.kind == .transfer
            switch kind {
            case .all: break
            case .transfer: if !isTransfer { return false }
            case .expense: if isTransfer || !movement.amount.isNegative { return false }
            case .income: if isTransfer || movement.amount.isNegative { return false }
            }
            guard !query.isEmpty else { return true }
            if movement.description.localizedCaseInsensitiveContains(query) { return true }
            if movement.notes?.localizedCaseInsensitiveContains(query) ?? false { return true }
            if movement.payee?.localizedCaseInsensitiveContains(query) ?? false { return true }
            let bareQuery = query.hasPrefix("#") ? String(query.dropFirst()) : query
            if movement.tags.contains(where: { $0.localizedCaseInsensitiveContains(bareQuery) }) { return true }
            if category?.name.localizedCaseInsensitiveContains(query) ?? false { return true }
            if let amountQuery {
                // Sin signo busca el importe en los dos sentidos; con "-" sólo gastos.
                let signed = query.hasPrefix("-") || query.hasPrefix("\u{2212}")
                return signed ? movement.amount.minor == amountQuery.minor
                              : abs(movement.amount.minor) == abs(amountQuery.minor)
            }
            return false
        }
    }
}

/// Movimientos de un mismo día con lo que suman (sin contar transferencias).
public struct MovementDay: Hashable, Sendable, Identifiable {
    public var day: CalendarDay
    public var movements: [Movement]
    public var total: Money

    public var id: CalendarDay { day }

    /// Agrupa por día, del más reciente al más antiguo; dentro de cada día se respeta el orden recibido.
    public static func group(_ movements: [Movement], categories: [BudgetCategory]) -> [MovementDay] {
        let transfers = Set(categories.filter { $0.kind == .transfer }.map(\.id))
        var order: [CalendarDay] = []
        var byDay: [CalendarDay: [Movement]] = [:]
        for movement in movements {
            if byDay[movement.bookedOn] == nil { order.append(movement.bookedOn) }
            byDay[movement.bookedOn, default: []].append(movement)
        }
        return order.sorted(by: >).map { day in
            let items = byDay[day] ?? []
            let total = items.filter { !$0.excluded && !($0.categoryId.map(transfers.contains) ?? false) }
                .reduce(0) { $0 + $1.amount.minor }
            return MovementDay(day: day, movements: items, total: Money(minor: total))
        }
    }
}
