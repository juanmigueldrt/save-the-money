#if DEBUG
import Foundation
import STMCore

/// Solo en compilaciones de depuración: arranca en modo demo, ya dentro de un
/// hogar con datos inventados y en la pantalla pedida, para hacer capturas sin
/// pulsar nada en el simulador. Nunca usa el servidor ni datos reales.
///
///     xcrun simctl launch booted <bundle id> -STMScreenshotSection budget
enum ScreenshotMode {
    /// La sección pedida con `-STMScreenshotSection <rawValue>`, o nil si no se pidió.
    static var section: AppSection? {
        UserDefaults.standard.string(forKey: "STMScreenshotSection").flatMap(AppSection.init(rawValue:))
    }

    static var isActive: Bool { section != nil }

    /// Crea una persona y un hogar de prueba con un mes de movimientos inventados.
    @MainActor
    static func prepare(_ session: SessionModel) async {
        let services = session.services
        do {
            _ = try await services.auth.signUp(username: try Username("demo"), password: "demo-capturas", displayName: "Demo")
            let household = try await services.households.createHousehold(name: "Hogar de prueba")
            let account = try await services.finance.createAccount(
                AccountDraft(name: "Cuenta corriente", openingBalance: Money(minor: 250_000)), in: household.id)
            let categories = try await services.finance.categories(in: household.id)
            func first(_ kind: CategoryKind, _ group: BudgetGroup? = nil) -> UUID? {
                categories.first { $0.kind == kind && (group == nil || $0.budgetGroup == group) }?.id
            }
            let today = CalendarDay()
            func day(_ d: Int) -> CalendarDay {
                CalendarDay(year: today.year, month: today.month, day: min(d, today.day)) ?? today
            }
            let movements: [(Int, Int, UUID?, String)] = [
                (1, 210_000, first(.income), "Nómina"),
                (2, -75_000, first(.expense, .needs), "Alquiler"),
                (3, -8_450, first(.expense, .needs), "Supermercado"),
                (5, -3_990, first(.expense, .wants), "Cena fuera"),
                (8, -1_299, first(.expense, .wants), "Suscripción de música"),
                (10, -20_000, first(.expense, .savings), "Ahorro mensual"),
            ]
            for (d, amount, category, text) in movements {
                _ = try await services.finance.addMovement(
                    MovementDraft(accountId: account.id, categoryId: category, bookedOn: day(d),
                                  amount: Money(minor: amount), description: text),
                    in: household.id)
            }
            _ = try await services.budgets.saveBudget(
                Budget(householdId: household.id, month: MonthKey(today), expectedIncome: Money(minor: 210_000)))
        } catch {
            // Si algo falla, la app queda en la pantalla de entrar, como sin este modo.
        }
        await session.refresh()
    }
}
#endif
