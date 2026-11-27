import STMCore

// ORC-103: títulos e iconos de los tipos del dominio que pinta la app. Estaban en STMCore.

extension AccountKind {
    var title: String {
        switch self {
        case .checking: String(localized: "Cuenta corriente")
        case .savings: String(localized: "Ahorro")
        case .creditCard: String(localized: "Tarjeta de crédito")
        case .cash: String(localized: "Efectivo")
        case .investment: String(localized: "Inversión")
        case .loan: String(localized: "Préstamo")
        case .other: String(localized: "Otra")
        }
    }

    var systemImage: String {
        switch self {
        case .checking: "building.columns"
        case .savings: "banknote"
        case .creditCard: "creditcard"
        case .cash: "eurosign"
        case .investment: "chart.line.uptrend.xyaxis"
        case .loan: "doc.text"
        case .other: "wallet.pass"
        }
    }
}

extension CategoryKind {
    var title: String {
        switch self {
        case .income: String(localized: "Ingreso")
        case .expense: String(localized: "Gasto")
        case .transfer: String(localized: "Transferencia")
        }
    }
}

extension GoalKind {
    var title: String {
        switch self {
        case .savings: String(localized: "Ahorro")
        case .debt: String(localized: "Pagar una deuda")
        }
    }

    var systemImage: String {
        switch self {
        case .savings: "banknote"
        case .debt: "creditcard"
        }
    }
}

extension RecurringKind {
    var title: String {
        switch self {
        case .subscription: String(localized: "Suscripción")
        case .essential: String(localized: "Gasto esencial")
        case .income: String(localized: "Ingreso fijo")
        }
    }

    var pluralTitle: String {
        switch self {
        case .subscription: String(localized: "Suscripciones")
        case .essential: String(localized: "Gastos esenciales")
        case .income: String(localized: "Ingresos fijos")
        }
    }

    var systemImage: String {
        switch self {
        case .subscription: "play.rectangle"
        case .essential: "bolt.house"
        case .income: "banknote"
        }
    }
}
