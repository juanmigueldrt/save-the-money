import Foundation
import Observation
import STMCore

/// Presupuesto y flujo de caja del mes elegido. Lo comparten la pantalla de
/// presupuesto y la de flujo, para que las dos miren el mismo mes.
@Observable
@MainActor
final class BudgetModel {
    let household: Household
    private let service: any BudgetService

    private(set) var month: MonthKey
    /// El presupuesto guardado de este mes.
    private(set) var budget: Budget?
    /// Si no hay presupuesto este mes, el del último mes que lo tenga, para proponerlo.
    private(set) var proposal: Budget?
    private(set) var movements: [Movement] = []
    private(set) var isLoading = false
    var error: String?

    init(household: Household, service: any BudgetService, today: CalendarDay = CalendarDay()) {
        self.household = household
        self.service = service
        month = MonthKey.containing(today, startDay: household.monthStartDay)
    }

    var period: ClosedRange<CalendarDay> { month.period(startDay: household.monthStartDay) }

    func report(categories: [BudgetCategory]) -> BudgetReport {
        BudgetReport(budget: budget, month: month, startDay: household.monthStartDay,
                     categories: categories, movements: movements)
    }

    /// Punto de partida del formulario: el de este mes, el anterior o uno vacío 50/30/20.
    var draft: Budget {
        budget ?? proposal?.copied(to: month) ?? Budget(householdId: household.id, month: month)
    }

    func show(_ month: MonthKey) async {
        self.month = month
        await load()
    }

    func load() async {
        let service = service, id = household.id, month = month, period = period
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            async let budget = service.budget(for: month, in: id)
            async let previous = service.latestBudget(before: month, in: id)
            async let movements = service.movements(in: id, from: period.lowerBound, through: period.upperBound)
            let (current, last, list) = try await (budget, previous, movements)
            // Si el usuario ya cambió de mes mientras cargaba, no se pisa.
            guard month == self.month else { return }
            self.budget = current
            proposal = current == nil ? last : nil
            self.movements = list
        } catch let appError as AppError {
            error = appError.errorDescription
        } catch {
            self.error = AppError.unknown("").errorDescription
        }
    }

    @discardableResult
    func save(_ budget: Budget) async -> Bool {
        error = nil
        do {
            self.budget = try await service.saveBudget(budget)
            proposal = nil
            return true
        } catch let appError as AppError {
            error = appError.errorDescription
        } catch {
            self.error = AppError.unknown("").errorDescription
        }
        return false
    }
}
