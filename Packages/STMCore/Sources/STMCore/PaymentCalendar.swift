import Foundation

// MARK: Calendario de pagos

/// De dónde sale un pago del calendario.
public enum PaymentSource: String, Hashable, Sendable, CaseIterable {
    case subscription, essential, income, creditCard, investment

    public init(_ kind: RecurringKind) {
        switch kind {
        case .subscription: self = .subscription
        case .essential: self = .essential
        case .income: self = .income
        }
    }

    public var title: String {
        switch self {
        case .subscription: "Suscripción"
        case .essential: "Pago fijo"
        case .income: "Ingreso fijo"
        case .creditCard: "Tarjeta de crédito"
        case .investment: "Inversión"
        }
    }

    public var systemImage: String {
        switch self {
        case .subscription: "play.rectangle"
        case .essential: "bolt.house"
        case .income: "banknote"
        case .creditCard: "creditcard"
        case .investment: "chart.line.uptrend.xyaxis"
        }
    }
}

/// Un pago (o ingreso) previsto para un día concreto.
public struct CalendarPayment: Hashable, Sendable, Identifiable {
    public var day: CalendarDay
    public var title: String
    public var source: PaymentSource
    /// Negativo para gastos, positivo para ingresos.
    public var amount: Money
    /// Es una estimación (p. ej. el cargo de la tarjeta antes de cerrar el extracto).
    public var isEstimate: Bool
    /// Serie, tarjeta o plan del que sale, para abrirlo.
    public var originId: UUID

    public init(day: CalendarDay, title: String, source: PaymentSource, amount: Money,
                isEstimate: Bool = false, originId: UUID) {
        self.day = day
        self.title = title
        self.source = source
        self.amount = amount
        self.isEstimate = isEstimate
        self.originId = originId
    }

    public var id: String { "\(source.rawValue)-\(originId.uuidString)-\(day.iso)" }
}

/// Junta pagos fijos, suscripciones, cargos de tarjeta y aportaciones a inversiones
/// en un solo calendario. No guarda nada: se calcula con lo que ya hay.
public struct PaymentCalendar: Hashable, Sendable {
    public var series: [RecurringSeries]
    /// Próximos cargos de cada tarjeta, con el nombre de la tarjeta.
    public var cardPayments: [(name: String, accountId: UUID, payment: CardPayment)]
    /// Planes de inversión, con el nombre del activo.
    public var plans: [(name: String, plan: InvestmentPlan)]

    public init(series: [RecurringSeries] = [],
                cardPayments: [(name: String, accountId: UUID, payment: CardPayment)] = [],
                plans: [(name: String, plan: InvestmentPlan)] = []) {
        self.series = series
        self.cardPayments = cardPayments
        self.plans = plans
    }

    /// Pagos entre dos días, ambos incluidos, ordenados por día y por nombre.
    public func payments(from start: CalendarDay, through end: CalendarDay) -> [CalendarPayment] {
        guard start <= end else { return [] }
        var result: [CalendarPayment] = []
        for item in series where !item.isArchived {
            for due in item.occurrences(from: start, through: end) {
                let charge = UpcomingCharge(series: item, due: due)
                result.append(CalendarPayment(day: due, title: item.trimmedName, source: PaymentSource(item.kind),
                                              amount: charge.signedAmount, originId: item.id))
            }
        }
        for card in cardPayments where card.payment.due >= start && card.payment.due <= end && card.payment.amount.minor > 0 {
            result.append(CalendarPayment(day: card.payment.due, title: card.name, source: .creditCard,
                                          amount: -card.payment.amount, isEstimate: card.payment.isEstimate,
                                          originId: card.accountId))
        }
        for entry in plans where !entry.plan.isPaused && !entry.plan.isArchived {
            for due in entry.plan.occurrences(from: start, through: end) {
                result.append(CalendarPayment(day: due, title: entry.name, source: .investment,
                                              amount: -entry.plan.amount, originId: entry.plan.id))
            }
        }
        return result.sorted { a, b in
            if a.day != b.day { return a.day < b.day }
            if a.title != b.title { return a.title.localizedCompare(b.title) == .orderedAscending }
            return a.source.rawValue < b.source.rawValue
        }
    }

    /// Los pagos de un mes de calendario (del 1 al último día), agrupados por día.
    public func month(_ key: MonthKey) -> PaymentMonth {
        let first = key.firstDay
        let last = CalendarDay(year: key.year, month: key.month, day: CalendarDay.daysIn(month: key.month, year: key.year))!
        return PaymentMonth(key: key, payments: payments(from: first, through: last))
    }

    /// Los `limit` pagos siguientes a un día (sin contarlo), mirando hasta un año adelante.
    public func next(after day: CalendarDay, limit: Int = 10) -> [CalendarPayment] {
        Array(payments(from: day.adding(days: 1), through: day.adding(days: 366)).prefix(limit))
    }

    public static func == (lhs: PaymentCalendar, rhs: PaymentCalendar) -> Bool {
        lhs.series == rhs.series && lhs.plans.map(\.plan) == rhs.plans.map(\.plan)
            && lhs.cardPayments.map(\.payment) == rhs.cardPayments.map(\.payment)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(series)
        hasher.combine(plans.map(\.plan))
        hasher.combine(cardPayments.map(\.payment))
    }
}

/// Un mes del calendario de pagos.
public struct PaymentMonth: Hashable, Sendable {
    public var key: MonthKey
    public var payments: [CalendarPayment]

    public func payments(on day: CalendarDay) -> [CalendarPayment] { payments.filter { $0.day == day } }

    /// Días con algún pago, para marcarlos en la cuadrícula.
    public var daysWithPayments: Set<CalendarDay> { Set(payments.map(\.day)) }

    /// Lo que sale en el mes (en positivo) y lo que entra.
    public var totalOut: Money { payments.filter { $0.amount.isNegative }.reduce(Money.zero) { $0 - $1.amount } }
    public var totalIn: Money { payments.filter { !$0.amount.isNegative }.reduce(Money.zero) { $0 + $1.amount } }

    /// Semanas del mes para la cuadrícula, empezando en lunes; nil en los huecos.
    public var weeks: [[CalendarDay?]] {
        let first = key.firstDay
        let count = CalendarDay.daysIn(month: key.month, year: key.year)
        let lead = first.weekdayFromMonday
        var cells: [CalendarDay?] = Array(repeating: nil, count: lead)
        cells += (0..<count).map { first.adding(days: $0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
    }
}

extension CalendarDay {
    /// 0 lunes … 6 domingo (el 1 de enero de 1970 fue jueves).
    public var weekdayFromMonday: Int {
        let value = (ordinal + 3) % 7
        return value < 0 ? value + 7 : value
    }

    /// "Sábado, 14 de noviembre".
    public var weekdayTitle: String {
        let names = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]
        return "\(names[weekdayFromMonday].capitalized), \(longTitle)"
    }
}

// MARK: Marcas al importar un CSV

/// Cómo se marca una fila del CSV antes de importarla.
public enum CSVRowMark: Hashable, Sendable {
    case none
    /// Crea un pago fijo (gasto esencial) mensual desde ese día.
    case essential
    /// Crea una suscripción mensual desde ese día.
    case subscription
    /// Guarda el movimiento en esa tarjeta de crédito en vez de en la cuenta del CSV.
    case creditCard(accountId: UUID)

    public var title: String {
        switch self {
        case .none: "Sin marcar"
        case .essential: "Pago fijo"
        case .subscription: "Suscripción"
        case .creditCard: "Compra con tarjeta"
        }
    }

    public var recurringKind: RecurringKind? {
        switch self {
        case .essential: .essential
        case .subscription: .subscription
        case .none, .creditCard: nil
        }
    }
}

/// Lo que hay que guardar al importar con marcas.
public struct CSVImportPlan: Hashable, Sendable {
    public var drafts: [MovementDraft]
    public var newSeries: [RecurringSeries]

    /// Aplica las marcas a las filas válidas: cambia la cuenta de las compras con tarjeta
    /// y prepara un pago fijo por cada fila marcada como recurrente o suscripción.
    /// Sólo se marcan gastos; no se repite una serie activa con el mismo nombre
    /// (ni dos filas marcadas con el mismo concepto: se queda la primera).
    public static func make(rows: [CSVImportRow], marks: [Int: CSVRowMark], householdId: UUID,
                            existing: [RecurringSeries]) -> CSVImportPlan {
        var known = Set(existing.filter { !$0.isArchived }.map { normalizedName($0.name) })
        var drafts: [MovementDraft] = []
        var series: [RecurringSeries] = []
        for row in rows {
            guard var draft = row.draft else { continue }
            let mark = draft.amount.isNegative ? (marks[row.line] ?? .none) : .none
            if case .creditCard(let card) = mark { draft.accountId = card }
            drafts.append(draft)
            if let kind = mark.recurringKind {
                let key = normalizedName(draft.description)
                guard !key.isEmpty, !known.contains(key) else { continue }
                known.insert(key)
                let name = draft.description.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                series.append(RecurringSeries(householdId: householdId, name: String(name.prefix(60)),
                                              kind: kind, amount: Money(minor: abs(draft.amount.minor), currency: draft.amount.currency),
                                              accountId: draft.accountId, categoryId: draft.categoryId,
                                              recurrence: .monthly, startsOn: draft.bookedOn, remindDaysBefore: 1))
            }
        }
        return CSVImportPlan(drafts: drafts, newSeries: series)
    }

    static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
