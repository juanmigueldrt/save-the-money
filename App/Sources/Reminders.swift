import Foundation
import STMCore
import UserNotifications

/// Programa los avisos de pagos en el dispositivo.
protocol ReminderScheduling: Sendable {
    /// Sustituye los avisos pendientes que empiezan por `prefix` (pagos fijos o aportaciones).
    func replace(with reminders: [PlannedReminder], prefix: String) async
}

/// Para previews y pruebas: no avisa de nada.
struct NoReminders: ReminderScheduling {
    func replace(with reminders: [PlannedReminder], prefix: String) async {}
}

/// Avisos locales con UserNotifications. No hace falta cuenta de pago de Apple ni
/// servidor: el propio iPhone o Mac los lanza. Si el usuario los apaga en
/// Más opciones, o no da permiso, sólo se borran los pendientes.
struct LocalReminders: ReminderScheduling {
    static let enabledKey = "remindersEnabled"

    func replace(with reminders: [PlannedReminder], prefix: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true, !reminders.isEmpty else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            var when = DateComponents()
            when.year = reminder.fireOn.year
            when.month = reminder.fireOn.month
            when.day = reminder.fireOn.day
            when.hour = reminder.hour
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }
}

/// Avisa de que una categoría o grupo del presupuesto llega al 80 % o se pasa.
protocol BudgetAlerting: Sendable {
    func notify(_ alerts: [BudgetAlert]) async
}

struct NoBudgetAlerts: BudgetAlerting {
    func notify(_ alerts: [BudgetAlert]) async {}
}

/// Avisos inmediatos en el dispositivo. Cada aviso (mes, categoría y umbral) sale una sola vez.
struct LocalBudgetAlerts: BudgetAlerting {
    static let enabledKey = "budgetAlertsEnabled"
    static let sentKey = "budgetAlertsSent"

    func notify(_ alerts: [BudgetAlert]) async {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.enabledKey) as? Bool ?? true else { return }
        var sent = Set(defaults.stringArray(forKey: Self.sentKey) ?? [])
        let fresh = alerts.filter { !sent.contains($0.id) }
        guard !fresh.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        for alert in fresh {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: nil))
            sent.insert(alert.id)
        }
        // Sólo se guardan los de los últimos meses para que la lista no crezca sin fin.
        let recent = sent.sorted().suffix(300)
        defaults.set(Array(recent), forKey: Self.sentKey)
    }
}
