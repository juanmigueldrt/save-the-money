import Foundation

/// Los tres grupos de la plantilla 50/30/20.
public enum BudgetGroup: String, Codable, CaseIterable, Sendable {
    case needs     // Necesidades
    case wants     // Deseos
    case savings   // Ahorro

    public var title: String {
        switch self {
        case .needs: "Necesidades"
        case .wants: "Deseos"
        case .savings: "Ahorro"
        }
    }
}

/// Plantilla de reparto de ingresos, por defecto 50/30/20.
public struct BudgetTemplate: Hashable, Codable, Sendable {
    public var needs: Int
    public var wants: Int
    public var savings: Int

    public static let fiftyThirtyTwenty = BudgetTemplate(needs: 50, wants: 30, savings: 20)

    public init(needs: Int, wants: Int, savings: Int) {
        precondition(needs + wants + savings == 100, "La plantilla debe sumar 100")
        self.needs = needs
        self.wants = wants
        self.savings = savings
    }

    public func percentage(for group: BudgetGroup) -> Int {
        switch group {
        case .needs: needs
        case .wants: wants
        case .savings: savings
        }
    }

    /// Cuánto toca a cada grupo de unos ingresos dados.
    public func allocate(_ income: Money) -> [BudgetGroup: Money] {
        let parts = income.split(percentages: [needs, wants, savings])
        return [.needs: parts[0], .wants: parts[1], .savings: parts[2]]
    }
}

/// Estado de un grupo para pintar el gauge semicircular: lo asignado frente a lo gastado.
public struct GroupProgress: Hashable, Sendable {
    public var group: BudgetGroup
    public var allocated: Money
    public var spent: Money

    public init(group: BudgetGroup, allocated: Money, spent: Money) {
        self.group = group
        self.allocated = allocated
        self.spent = spent
    }

    /// Fracción gastada entre 0 y 1 para el arco del semicírculo.
    public var fraction: Double {
        guard allocated.minor > 0 else { return spent.minor > 0 ? 1 : 0 }
        return min(1, max(0, Double(spent.minor) / Double(allocated.minor)))
    }

    public var remaining: Money { allocated - spent }
    public var isOver: Bool { spent.minor > allocated.minor }
}
