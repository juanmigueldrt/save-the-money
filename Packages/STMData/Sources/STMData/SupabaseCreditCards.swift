import Foundation
import STMCore
import Supabase

/// Tarjetas de crédito sobre Supabase. El RLS sólo deja ver y tocar las del hogar; un
/// disparador comprueba que la cuenta es una tarjeta y las claves foráneas, que un
/// aplazado es de una compra de esa misma tarjeta.
extension SupabaseBackend: CreditCardService {
    private static let cardColumns = "account_id,household_id,credit_limit_minor,statement_day,payment_day,payment_delay_months,payment_mode,fixed_payment_minor,min_payment_percent,min_payment_minor,revolving_rate,installment_rate,pay_from_account_id,remind_days_before,alert_percent"
    private static let installmentColumns = "id,household_id,account_id,transaction_id,months,rate"

    public func creditCards(in householdId: UUID) async throws -> [CreditCardTerms] {
        try await mapped {
            try await client.from("credit_cards")
                .select(Self.cardColumns)
                .eq("household_id", value: householdId.uuidString)
                .execute()
                .value
        }
    }

    public func saveCreditCard(_ terms: CreditCardTerms) async throws -> CreditCardTerms {
        if let issue = terms.issue { throw AppError.invalidInput(issue) }
        // No se usa upsert: haría UPDATE de la cuenta y el hogar, que no se pueden cambiar.
        let updated: [CreditCardTerms] = try await mapped {
            try await client.from("credit_cards")
                .update(terms)
                .eq("account_id", value: terms.accountId.uuidString)
                .select(Self.cardColumns)
                .execute()
                .value
        }
        if let first = updated.first { return first }
        let row = NewRow(householdId: terms.householdId, fields: NewCard(accountId: terms.accountId, terms: terms))
        return try await mapped {
            try await client.from("credit_cards")
                .insert(row)
                .select(Self.cardColumns)
                .single()
                .execute()
                .value
        }
    }

    public func cardInstallments(in householdId: UUID) async throws -> [CardInstallment] {
        try await mapped {
            try await client.from("card_installments")
                .select(Self.installmentColumns)
                .eq("household_id", value: householdId.uuidString)
                .execute()
                .value
        }
    }

    public func saveInstallment(_ installment: CardInstallment) async throws -> CardInstallment {
        if let issue = installment.issue { throw AppError.invalidInput(issue) }
        let updated: [CardInstallment] = try await mapped {
            try await client.from("card_installments")
                .update(installment)
                .eq("transaction_id", value: installment.movementId.uuidString)
                .select(Self.installmentColumns)
                .execute()
                .value
        }
        if let first = updated.first { return first }
        let row = NewRow(householdId: installment.householdId, fields: NewInstallment(installment: installment))
        return try await mapped {
            try await client.from("card_installments")
                .insert(row)
                .select(Self.installmentColumns)
                .single()
                .execute()
                .value
        }
    }

    public func deleteInstallment(_ installmentId: UUID) async throws {
        try await mapped {
            try await client.from("card_installments").delete().eq("id", value: installmentId.uuidString).execute()
        }
    }
}

/// Fila nueva de condiciones: las columnas editables más la cuenta.
private struct NewCard: Encodable, Sendable {
    var accountId: UUID
    var terms: CreditCardTerms

    private enum CodingKeys: String, CodingKey { case accountId = "account_id" }

    func encode(to encoder: Encoder) throws {
        try terms.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accountId, forKey: .accountId)
    }
}

/// Aplazado nuevo: plazo e interés más la tarjeta y el movimiento.
private struct NewInstallment: Encodable, Sendable {
    var installment: CardInstallment

    private enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case transactionId = "transaction_id"
    }

    func encode(to encoder: Encoder) throws {
        try installment.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(installment.accountId, forKey: .accountId)
        try c.encode(installment.movementId, forKey: .transactionId)
    }
}
