import STMCore

// ORC-103: el texto de los problemas de validación de los modelos. El dominio los devuelve tipados y la app
// pone aquí, en un solo sitio, lo que ve el usuario.

extension AppError {
    /// El texto para la pantalla: el de la validación tipada o, si no, el de `errorDescription`.
    var text: String? {
        if case .validation(let issue) = self { return issue.text }
        return errorDescription
    }
}

extension ValidationIssue {
    var text: String {
        switch self {
        case .paySchedule(let issue): issue.text
        case .extraBudget(let issue): issue.text
        case .budget(let issue): issue.text
        case .cardTerms(let issue): issue.text
        case .installment(let issue): issue.text
        case .category(let issue): issue.text
        case .movement(let issue): issue.text
        case .account(let issue): issue.text
        case .transfer(let issue): issue.text
        case .goal(let issue): issue.text
        case .contribution(let issue): issue.text
        case .holding(let issue): issue.text
        case .trade(let issue): issue.text
        case .plan(let issue): issue.text
        case .creditScore(let issue): issue.text
        case .recurring(let issue): issue.text
        }
    }
}

extension PaySchedule.Issue {
    var text: String {
        switch self {
        case .dayOutOfRange: String(localized: "El día de cobro tiene que estar entre 1 y 31.")
        case .secondDayNotAfterFirst: String(localized: "El segundo día de cobro tiene que ir después del primero.")
        case .anchorMissing: String(localized: "Elige un día en que hayas cobrado.")
        }
    }
}

extension ExtraBudget.Issue {
    var text: String {
        switch self {
        case .nameMissing: String(localized: "Ponle un nombre.")
        case .nameTooLong: String(localized: "El nombre es demasiado largo (máximo 60 caracteres).")
        case .limitNotPositive: String(localized: "El límite tiene que ser mayor que cero.")
        case .endsBeforeStart: String(localized: "La fecha de fin no puede ser anterior a la de inicio.")
        case .tooManyFilters: String(localized: "Demasiadas categorías o cuentas.")
        }
    }
}

extension Budget.Issue {
    var text: String {
        switch self {
        case .negativeIncome: String(localized: "Los ingresos previstos no pueden ser negativos.")
        case .negativeLimit: String(localized: "Los límites no pueden ser negativos.")
        case .warnPercentOutOfRange: String(localized: "El aviso tiene que estar entre el 50 % y el 100 %.")
        }
    }
}

extension CSVImportRow.Issue {
    var text: String {
        switch self {
        case .unrecognizedDate(let date): String(localized: "Fecha no reconocida: «\(date)»")
        case .chargeAndCredit: String(localized: "Tiene cargo y abono a la vez")
        case .invalidAmount: String(localized: "Importe vacío o no válido")
        }
    }
}

extension CreditCardTerms.Issue {
    var text: String {
        switch self {
        case .limitNotPositive: String(localized: "El límite tiene que ser mayor que cero.")
        case .statementDayOutOfRange: String(localized: "El día del extracto va del 1 al 28.")
        case .paymentDayOutOfRange: String(localized: "El día del cargo va del 1 al 28.")
        case .paymentDelayOutOfRange: String(localized: "El cargo puede ser el mismo mes del extracto o hasta dos meses después.")
        case .fixedPaymentMissing: String(localized: "Indica la cuota fija que pagas cada mes.")
        case .fixedPaymentNotPositive: String(localized: "La cuota fija tiene que ser mayor que cero.")
        case .minPaymentPercentOutOfRange: String(localized: "El % del pago mínimo va de 0 a 100.")
        case .minPaymentNegative: String(localized: "El pago mínimo no puede ser negativo.")
        case .rateOutOfRange: String(localized: "El interés tiene que estar entre 0 y 60 %.")
        case .paysItself: String(localized: "La tarjeta no se puede pagar a sí misma.")
        case .reminderOutOfRange: String(localized: "El aviso puede ser de 0 a 14 días antes.")
        case .alertPercentOutOfRange: String(localized: "El aviso del límite va del 1 al 100 %.")
        }
    }
}

extension CardInstallment.Issue {
    var text: String {
        switch self {
        case .monthsOutOfRange: String(localized: "Se puede aplazar de 2 a 48 meses.")
        case .rateOutOfRange: String(localized: "El interés tiene que estar entre 0 y 60 %.")
        }
    }
}

extension BudgetCategory.Issue {
    var text: String {
        switch self {
        case .nameMissing: String(localized: "Ponle un nombre a la categoría.")
        case .nameTooLong: String(localized: "El nombre es demasiado largo (máximo \(BudgetCategory.maxNameLength) letras).")
        case .groupOnlyForExpenses: String(localized: "Sólo los gastos van en un grupo del 50/30/20.")
        case .duplicateName(let kind): String(localized: "Ya hay una categoría de \(kind.title.lowercased()) con ese nombre.")
        }
    }
}

extension MovementDraft.Issue {
    var text: String {
        switch self {
        case .descriptionMissing: String(localized: "Escribe un concepto.")
        case .descriptionTooLong: String(localized: "El concepto es demasiado largo (máximo 200 caracteres).")
        case .amountZero: String(localized: "El importe no puede ser cero.")
        case .notesTooLong: String(localized: "Las notas son demasiado largas (máximo 500 caracteres).")
        case .payeeTooLong: String(localized: "El beneficiario es demasiado largo (máximo 80 caracteres).")
        case .tags(let issue): issue.text
        }
    }
}

extension MovementTags.Issue {
    var text: String {
        switch self {
        case .tooMany: String(localized: "Como mucho \(MovementTags.maxCount) etiquetas por movimiento.")
        case .badLength: String(localized: "Cada etiqueta debe tener entre 1 y \(MovementTags.maxLength) caracteres.")
        case .badCharacters: String(localized: "Las etiquetas sólo pueden tener letras, números, «-» y «_».")
        }
    }
}

extension AccountDraft.Issue {
    var text: String {
        switch self {
        case .nameMissing: String(localized: "Ponle un nombre a la cuenta.")
        case .nameTooLong: String(localized: "El nombre es demasiado largo (máximo 60 caracteres).")
        }
    }
}

extension TransferDraft.Issue {
    var text: String {
        switch self {
        case .sameAccount: String(localized: "Elige dos cuentas distintas.")
        case .amountNotPositive: String(localized: "El importe tiene que ser mayor que cero.")
        case .leg(let issue): issue.text
        }
    }
}

extension Goal.Issue {
    var text: String {
        switch self {
        case .nameMissing: String(localized: "Ponle un nombre a la meta.")
        case .nameTooLong: String(localized: "El nombre es demasiado largo.")
        case .targetNotPositive(let kind): kind == .debt ? String(localized: "Indica cuánto se debe.") : String(localized: "Indica cuánto quieres juntar.")
        case .startingNegative: String(localized: "Lo que ya tienes no puede ser negativo.")
        case .monthlyPlanNegative: String(localized: "La aportación mensual no puede ser negativa.")
        }
    }
}

extension GoalContribution.Issue {
    var text: String {
        switch self {
        case .amountZero: String(localized: "El importe no puede ser cero.")
        case .noteTooLong: String(localized: "La nota es demasiado larga.")
        }
    }
}

extension Holding.Issue {
    var text: String {
        switch self {
        case .nameMissing: String(localized: "Ponle un nombre.")
        case .nameTooLong: String(localized: "El nombre es demasiado largo.")
        case .symbolTooLong: String(localized: "El código es demasiado largo.")
        case .negativePrice: String(localized: "El precio no puede ser negativo.")
        case .priceTooPrecise: String(localized: "Como mucho 6 decimales en el precio.")
        case .feeRateOutOfRange: String(localized: "La comisión tiene que estar entre 0 y 10 %.")
        case .noteTooLong: String(localized: "La nota es demasiado larga.")
        }
    }
}

extension InvestmentTrade.Issue {
    var text: String {
        switch self {
        case .quantityNotPositive: String(localized: "Indica cuántas participaciones.")
        case .quantityTooPrecise: String(localized: "Como mucho 8 decimales en las participaciones.")
        case .negativePrice: String(localized: "El precio no puede ser negativo.")
        case .priceTooPrecise: String(localized: "Como mucho 6 decimales en el precio.")
        case .negativeFee: String(localized: "La comisión no puede ser negativa.")
        case .noteTooLong: String(localized: "La nota es demasiado larga.")
        case .notEnoughShares: String(localized: "No tienes tantas participaciones para vender.")
        case .neededByLaterSale: String(localized: "No se puede borrar esta compra: una venta posterior se quedaría sin participaciones.")
        }
    }
}

extension InvestmentPlan.Issue {
    var text: String {
        switch self {
        case .amountNotPositive: String(localized: "El importe tiene que ser mayor que cero.")
        case .badFrequency: String(localized: "La frecuencia no es válida.")
        case .endsBeforeStart: String(localized: "No puede terminar antes de empezar.")
        case .returnOutOfRange: String(localized: "La rentabilidad supuesta tiene que estar entre −50 y 50 %.")
        case .reminderOutOfRange: String(localized: "El aviso puede ser de 0 a 14 días antes.")
        }
    }
}

extension CreditScore.Issue {
    var text: String {
        switch self {
        case .scaleOutOfRange: String(localized: "La escala tiene que estar entre 100 y 1000.")
        case .scoreOutOfRange(let max): String(localized: "El score tiene que estar entre 0 y \(String(max)).")
        case .providerTooLong: String(localized: "El nombre del proveedor es demasiado largo.")
        case .noteTooLong: String(localized: "La nota es demasiado larga.")
        }
    }
}

extension RecurringSeries.Issue {
    var text: String {
        switch self {
        case .nameMissing: String(localized: "Ponle un nombre.")
        case .nameTooLong: String(localized: "El nombre es demasiado largo.")
        case .amountNotPositive: String(localized: "El importe tiene que ser mayor que cero.")
        case .badFrequency: String(localized: "La frecuencia no es válida.")
        case .endsBeforeStart: String(localized: "No puede terminar antes de empezar.")
        case .reminderOutOfRange: String(localized: "El aviso puede ser de 0 a 14 días antes.")
        case .introIncomplete: String(localized: "Indica el precio de oferta y cuántos cargos dura.")
        case .introAmountNotPositive: String(localized: "El precio de oferta tiene que ser mayor que cero.")
        case .introChargesOutOfRange: String(localized: "La oferta puede durar de 1 a 36 cargos.")
        }
    }
}
