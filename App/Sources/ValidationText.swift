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
        case .dayOutOfRange: "El día de cobro tiene que estar entre 1 y 31."
        case .secondDayNotAfterFirst: "El segundo día de cobro tiene que ir después del primero."
        case .anchorMissing: "Elige un día en que hayas cobrado."
        }
    }
}

extension ExtraBudget.Issue {
    var text: String {
        switch self {
        case .nameMissing: "Ponle un nombre."
        case .nameTooLong: "El nombre es demasiado largo (máximo 60 caracteres)."
        case .limitNotPositive: "El límite tiene que ser mayor que cero."
        case .endsBeforeStart: "La fecha de fin no puede ser anterior a la de inicio."
        case .tooManyFilters: "Demasiadas categorías o cuentas."
        }
    }
}

extension Budget.Issue {
    var text: String {
        switch self {
        case .negativeIncome: "Los ingresos previstos no pueden ser negativos."
        case .negativeLimit: "Los límites no pueden ser negativos."
        case .warnPercentOutOfRange: "El aviso tiene que estar entre el 50 % y el 100 %."
        }
    }
}

extension CSVImportRow.Issue {
    var text: String {
        switch self {
        case .unrecognizedDate(let date): "Fecha no reconocida: «\(date)»"
        case .chargeAndCredit: "Tiene cargo y abono a la vez"
        case .invalidAmount: "Importe vacío o no válido"
        }
    }
}

extension CreditCardTerms.Issue {
    var text: String {
        switch self {
        case .limitNotPositive: "El límite tiene que ser mayor que cero."
        case .statementDayOutOfRange: "El día del extracto va del 1 al 28."
        case .paymentDayOutOfRange: "El día del cargo va del 1 al 28."
        case .paymentDelayOutOfRange: "El cargo puede ser el mismo mes del extracto o hasta dos meses después."
        case .fixedPaymentMissing: "Indica la cuota fija que pagas cada mes."
        case .fixedPaymentNotPositive: "La cuota fija tiene que ser mayor que cero."
        case .minPaymentPercentOutOfRange: "El % del pago mínimo va de 0 a 100."
        case .minPaymentNegative: "El pago mínimo no puede ser negativo."
        case .rateOutOfRange: "El interés tiene que estar entre 0 y 60 %."
        case .paysItself: "La tarjeta no se puede pagar a sí misma."
        case .reminderOutOfRange: "El aviso puede ser de 0 a 14 días antes."
        case .alertPercentOutOfRange: "El aviso del límite va del 1 al 100 %."
        }
    }
}

extension CardInstallment.Issue {
    var text: String {
        switch self {
        case .monthsOutOfRange: "Se puede aplazar de 2 a 48 meses."
        case .rateOutOfRange: "El interés tiene que estar entre 0 y 60 %."
        }
    }
}

extension BudgetCategory.Issue {
    var text: String {
        switch self {
        case .nameMissing: "Ponle un nombre a la categoría."
        case .nameTooLong: "El nombre es demasiado largo (máximo \(BudgetCategory.maxNameLength) letras)."
        case .groupOnlyForExpenses: "Sólo los gastos van en un grupo del 50/30/20."
        case .duplicateName(let kind): "Ya hay una categoría de \(kind.title.lowercased()) con ese nombre."
        }
    }
}

extension MovementDraft.Issue {
    var text: String {
        switch self {
        case .descriptionMissing: "Escribe un concepto."
        case .descriptionTooLong: "El concepto es demasiado largo (máximo 200 caracteres)."
        case .amountZero: "El importe no puede ser cero."
        case .notesTooLong: "Las notas son demasiado largas (máximo 500 caracteres)."
        case .payeeTooLong: "El beneficiario es demasiado largo (máximo 80 caracteres)."
        case .tags(let issue): issue.text
        }
    }
}

extension MovementTags.Issue {
    var text: String {
        switch self {
        case .tooMany: "Como mucho \(MovementTags.maxCount) etiquetas por movimiento."
        case .badLength: "Cada etiqueta debe tener entre 1 y \(MovementTags.maxLength) caracteres."
        case .badCharacters: "Las etiquetas sólo pueden tener letras, números, «-» y «_»."
        }
    }
}

extension AccountDraft.Issue {
    var text: String {
        switch self {
        case .nameMissing: "Ponle un nombre a la cuenta."
        case .nameTooLong: "El nombre es demasiado largo (máximo 60 caracteres)."
        }
    }
}

extension TransferDraft.Issue {
    var text: String {
        switch self {
        case .sameAccount: "Elige dos cuentas distintas."
        case .amountNotPositive: "El importe tiene que ser mayor que cero."
        case .leg(let issue): issue.text
        }
    }
}

extension Goal.Issue {
    var text: String {
        switch self {
        case .nameMissing: "Ponle un nombre a la meta."
        case .nameTooLong: "El nombre es demasiado largo."
        case .targetNotPositive(let kind): kind == .debt ? "Indica cuánto se debe." : "Indica cuánto quieres juntar."
        case .startingNegative: "Lo que ya tienes no puede ser negativo."
        case .monthlyPlanNegative: "La aportación mensual no puede ser negativa."
        }
    }
}

extension GoalContribution.Issue {
    var text: String {
        switch self {
        case .amountZero: "El importe no puede ser cero."
        case .noteTooLong: "La nota es demasiado larga."
        }
    }
}

extension Holding.Issue {
    var text: String {
        switch self {
        case .nameMissing: "Ponle un nombre."
        case .nameTooLong: "El nombre es demasiado largo."
        case .symbolTooLong: "El código es demasiado largo."
        case .negativePrice: "El precio no puede ser negativo."
        case .priceTooPrecise: "Como mucho 6 decimales en el precio."
        case .feeRateOutOfRange: "La comisión tiene que estar entre 0 y 10 %."
        case .noteTooLong: "La nota es demasiado larga."
        }
    }
}

extension InvestmentTrade.Issue {
    var text: String {
        switch self {
        case .quantityNotPositive: "Indica cuántas participaciones."
        case .quantityTooPrecise: "Como mucho 8 decimales en las participaciones."
        case .negativePrice: "El precio no puede ser negativo."
        case .priceTooPrecise: "Como mucho 6 decimales en el precio."
        case .negativeFee: "La comisión no puede ser negativa."
        case .noteTooLong: "La nota es demasiado larga."
        case .notEnoughShares: "No tienes tantas participaciones para vender."
        case .neededByLaterSale: "No se puede borrar esta compra: una venta posterior se quedaría sin participaciones."
        }
    }
}

extension InvestmentPlan.Issue {
    var text: String {
        switch self {
        case .amountNotPositive: "El importe tiene que ser mayor que cero."
        case .badFrequency: "La frecuencia no es válida."
        case .endsBeforeStart: "No puede terminar antes de empezar."
        case .returnOutOfRange: "La rentabilidad supuesta tiene que estar entre −50 y 50 %."
        case .reminderOutOfRange: "El aviso puede ser de 0 a 14 días antes."
        }
    }
}

extension CreditScore.Issue {
    var text: String {
        switch self {
        case .scaleOutOfRange: "La escala tiene que estar entre 100 y 1000."
        case .scoreOutOfRange(let max): "El score tiene que estar entre 0 y \(max)."
        case .providerTooLong: "El nombre del proveedor es demasiado largo."
        case .noteTooLong: "La nota es demasiado larga."
        }
    }
}

extension RecurringSeries.Issue {
    var text: String {
        switch self {
        case .nameMissing: "Ponle un nombre."
        case .nameTooLong: "El nombre es demasiado largo."
        case .amountNotPositive: "El importe tiene que ser mayor que cero."
        case .badFrequency: "La frecuencia no es válida."
        case .endsBeforeStart: "No puede terminar antes de empezar."
        case .reminderOutOfRange: "El aviso puede ser de 0 a 14 días antes."
        case .introIncomplete: "Indica el precio de oferta y cuántos cargos dura."
        case .introAmountNotPositive: "El precio de oferta tiene que ser mayor que cero."
        case .introChargesOutOfRange: "La oferta puede durar de 1 a 36 cargos."
        }
    }
}
