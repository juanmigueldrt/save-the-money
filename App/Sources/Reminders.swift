import Foundation
import STMCore
import UserNotifications

/// Programa los avisos de pagos en el dispositivo.
protocol ReminderScheduling: Sendable {
    func replace(with reminders: [PlannedReminder]) async
}

/// Para previews y pruebas: no avisa de nada.
struct NoReminders: ReminderScheduling {
    func replace(with reminders: [PlannedReminder]) async {}
}

/// Avisos locales con UserNotifications. No hace falta cuenta de pago de Apple ni
/// servidor: el propio iPhone o Mac los lanza. Si el usuario los apaga en
/// Más opciones, o no da permiso, sólo se borran los pendientes.
struct LocalReminders: ReminderScheduling {
    static let enabledKey = "remindersEnabled"

    func replace(with reminders: [PlannedReminder]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.prefix) }
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
