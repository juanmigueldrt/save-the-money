import Foundation
import STMCore
import Supabase

/// Tarjetas de crédito sobre Supabase. El RLS sólo deja ver y tocar las del hogar; un
/// disparador comprueba que la cuenta es una tarjeta y las claves foráneas, que un
/// aplazado es de una compra de esa misma tarjeta.
extension SupabaseBackend: CreditCardService {
    private static let cardColumns = "account_id,household_id,credit_limit_minor,statement_day,payment_day,payment_delay_months,payment_mode,fixed_payment_minor,min_payment_percent,min_payment_minor,revolving_rate,installment_rate,pay_from_account_id,remind_days_before,alert_percent,updated_at"
    private static let installmentColumns = "id,household_id,account_id,transaction_id,months,rate,updated_at"

    public func creditCards(in householdId: UUID) async throws -> [CreditCardTerms] {
        try await allRows {
            client.from("credit_cards")
                .select(Self.cardColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("account_id")
        }
    }

    public func saveCreditCard(_ terms: CreditCardTerms) async throws -> CreditCardTerms {
        if let issue = terms.issue { throw AppError.invalidInput(issue) }
        var params: [String: AnyJSON] = [
            "card": .uuid(terms.accountId), "credit_limit": .integer(terms.creditLimit.minor),
            "statement": .integer(terms.statementDay), "payment": .integer(terms.paymentDay),
            "delay_months": .integer(terms.paymentDelayMonths), "mode": .string(terms.paymentMode.rawValue),
            "fixed_payment": .int(terms.fixedPayment?.minor), "min_percent": .decimal(terms.minPaymentPercent),
            "min_payment": .integer(terms.minPayment.minor), "revolving": .decimal(terms.revolvingRate),
            "installments": .decimal(terms.installmentRate), "pay_from": .uuid(terms.payFromAccountId),
            "remind_days": .int(terms.remindDaysBefore), "alert": .int(terms.alertPercent)
        ]
        // Sin versión son condiciones nuevas: `create_credit_card` no las repite si ya estaban guardadas.
        guard let seen = terms.updatedAt else {
            params["household"] = .uuid(terms.householdId)
            return try await saved("create_credit_card", columns: Self.cardColumns, params)
        }
        // `update_credit_card` compara la versión y cambia la fila en la misma sentencia; si no coincide falla con STM05.
        params["seen"] = .string(seen)
        return try await saved("update_credit_card", columns: Self.cardColumns, params)
    }

    public func cardInstallments(in householdId: UUID) async throws -> [CardInstallment] {
        try await allRows {
            client.from("card_installments")
                .select(Self.installmentColumns)
                .eq("household_id", value: householdId.uuidString)
                .order("id")
        }
    }

    public func saveInstallment(_ installment: CardInstallment) async throws -> CardInstallment {
        if let issue = installment.issue { throw AppError.invalidInput(issue) }
        // Sin versión es un aplazado nuevo: `create_card_installment` no lo repite si ya estaba guardado.
        guard let seen = installment.updatedAt else {
            return try await saved("create_card_installment", columns: Self.installmentColumns, [
                "installment": .uuid(installment.id), "household": .uuid(installment.householdId),
                "card": .uuid(installment.accountId), "movement": .uuid(installment.movementId),
                "plan_months": .integer(installment.months), "plan_rate": .decimal(installment.rate)
            ])
        }
        return try await saved("update_card_installment", columns: Self.installmentColumns, [
            "installment": .uuid(installment.id), "seen": .string(seen),
            "plan_months": .integer(installment.months), "plan_rate": .decimal(installment.rate)
        ])
    }

    public func deleteInstallment(_ installmentId: UUID) async throws {
        try await mapped {
            try await client.from("card_installments").delete().eq("id", value: installmentId.uuidString).execute()
        }
    }
}
