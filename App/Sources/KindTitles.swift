import STMCore

// ORC-103: títulos e iconos de los tipos del dominio que pinta la app. Estaban en STMCore.

extension AccountKind {
    var title: String {
        switch self {
        case .checking: "Cuenta corriente"
        case .savings: "Ahorro"
        case .creditCard: "Tarjeta de crédito"
        case .cash: "Efectivo"
        case .investment: "Inversión"
        case .loan: "Préstamo"
        case .other: "Otra"
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
        case .income: "Ingreso"
        case .expense: "Gasto"
        case .transfer: "Transferencia"
        }
    }
}

extension GoalKind {
    var title: String {
        switch self {
        case .savings: "Ahorro"
        case .debt: "Pagar una deuda"
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
        case .subscription: "Suscripción"
        case .essential: "Gasto esencial"
        case .income: "Ingreso fijo"
        }
    }

    var pluralTitle: String {
        switch self {
        case .subscription: "Suscripciones"
        case .essential: "Gastos esenciales"
        case .income: "Ingresos fijos"
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
