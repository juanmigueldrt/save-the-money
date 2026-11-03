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
            try await prepareInvestments(services.investments, household: household.id, account: account.id, today: today)
        } catch {
            // Si algo falla, la app queda en la pantalla de entrar, como sin este modo.
        }
        await session.refresh()
    }

    /// Dos fondos inventados con unos meses de compras y precios, y dos planes (uno en pausa).
    private static func prepareInvestments(_ service: any InvestmentService, household: UUID, account: UUID,
                                           today: CalendarDay) async throws {
        let world = try await service.createHolding(Holding(householdId: household, name: "Fondo indexado mundial",
                                                            kind: .fund, feeRate: Decimal(string: "0.1")!))
        let bonds = try await service.createHolding(Holding(householdId: household, name: "Fondo de renta fija",
                                                            kind: .bond))
        let coin = try await service.createHolding(Holding(householdId: household, name: "Moneda digital", symbol: "MD",
                                                           kind: .crypto, feeRate: 1))
        let buys: [(Holding, Int, String, String)] = [
            (world, -6, "20", "10.00"), (world, -4, "15", "10.80"), (world, -2, "15", "11.40"),
            (bonds, -5, "100", "5.00"), (coin, -3, "0.5", "180.00"),
            // Compras de los planes, después de que empezaran.
            (world, -1, "13", "11.90"), (bonds, 0, "12", "5.06"),
        ]
        for (holding, months, quantity, price) in buys {
            _ = try await service.addTrade(InvestmentTrade(householdId: household, holdingId: holding.id,
                                                           tradedOn: today.adding(months: months),
                                                           quantity: Decimal(string: quantity)!, price: Decimal(string: price)!))
        }
        let prices: [(Holding, Int, String)] = [
            (world, -75, "11.20"), (world, -40, "11.60"), (world, -15, "12.05"), (world, 0, "12.35"),
            (bonds, -60, "5.02"), (bonds, 0, "5.06"),
            (coin, -45, "205.00"), (coin, -15, "170.00"), (coin, 0, "196.00"),
        ]
        for (holding, days, price) in prices {
            _ = try await service.recordPrice(Decimal(string: price)!, on: today.adding(days: days), for: holding.id)
        }
        _ = try await service.createPlan(InvestmentPlan(householdId: household, holdingId: world.id, accountId: account,
                                                        amount: Money(minor: 15_000), startsOn: today.adding(months: -5)))
        _ = try await service.createPlan(InvestmentPlan(householdId: household, holdingId: bonds.id, accountId: account,
                                                        amount: Money(minor: 6_000), recurrence: Recurrence(every: 2, unit: .week),
                                                        startsOn: today.adding(days: -9)))
        _ = try await service.createPlan(InvestmentPlan(householdId: household, holdingId: coin.id, amount: Money(minor: 2_500),
                                                        startsOn: today.adding(months: -2), pausedAt: Date()))
    }
}
#endif
