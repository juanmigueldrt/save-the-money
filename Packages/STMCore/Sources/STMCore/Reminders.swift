import Foundation

/// Un aviso local que la app programa en el dispositivo. No pasa por ningún servidor.
public struct PlannedReminder: Hashable, Sendable, Identifiable {
    /// Identificador estable: el mismo cargo da siempre el mismo id, así que reprogramar no duplica.
    public var id: String
    public var fireOn: CalendarDay
    /// Hora local del aviso.
    public var hour: Int
    public var title: String
    public var body: String
}

public enum ReminderPlanner {
    /// Prefijo de los avisos de pagos, para poder quitarlos todos sin tocar otros.
    public static let prefix = "stm.recurring."

    /// Avisos de los próximos cargos de las series activas que tienen aviso.
    /// iOS guarda como mucho 64 avisos pendientes por app, así que se limita a `limit`
    /// y la app los vuelve a calcular cada vez que se abre.
    public static func plan(_ series: [RecurringSeries], today: CalendarDay, horizonDays: Int = 45,
                            limit: Int = 50, hour: Int = 9) -> [PlannedReminder] {
        let end = today.adding(days: horizonDays)
        var result: [PlannedReminder] = []
        for item in series where !item.isArchived {
            guard let before = item.remindDaysBefore else { continue }
            for due in item.occurrences(from: today, through: end.adding(days: before)) {
                let fire = due.adding(days: -before)
                guard fire >= today, fire <= end else { continue }
                result.append(PlannedReminder(id: "\(prefix)\(item.id.uuidString).\(due.iso)", fireOn: fire, hour: hour,
                                              title: title(for: item, daysBefore: before),
                                              body: body(for: item, due: due)))
            }
        }
        return Array(result.sorted { $0.fireOn != $1.fireOn ? $0.fireOn < $1.fireOn : $0.id < $1.id }.prefix(limit))
    }

    static func title(for series: RecurringSeries, daysBefore: Int) -> String {
        let when = switch daysBefore {
        case 0: "Hoy"
        case 1: "Mañana"
        default: "En \(daysBefore) días"
        }
        return "\(when): \(series.trimmedName)"
    }

    static func body(for series: RecurringSeries, due: CalendarDay) -> String {
        let verb = series.kind == .income ? "Se ingresan" : "Se cobran"
        return "\(verb) \(series.amount.formatted()) el \(due.longTitle)."
    }
}
