import Foundation

/// Tarjetas en memoria, con las mismas reglas que el servidor: sólo miembros del hogar,
/// sólo cuentas de tipo tarjeta y un aplazado por compra de esa misma tarjeta.
extension InMemoryBackend: CreditCardService {
    private func requireCardMember(of householdId: UUID) throws {
        let user = try requireUser()
        guard isMember(user, of: householdId) else { throw AppError.unknown("no es miembro") }
    }

    public func creditCards(in householdId: UUID) async throws -> [CreditCardTerms] {
        try requireCardMember(of: householdId)
        return creditCardList.filter { $0.householdId == householdId }
    }

    public func saveCreditCard(_ terms: CreditCardTerms) async throws -> CreditCardTerms {
        try requireCardMember(of: terms.householdId)
        if let issue = terms.issue { throw AppError.invalidInput(issue) }
        guard financeAccounts.contains(where: { $0.id == terms.accountId && $0.householdId == terms.householdId && $0.kind == .creditCard })
        else { throw AppError.invalidInput("La cuenta no es una tarjeta de crédito.") }
        if let payFrom = terms.payFromAccountId,
           !financeAccounts.contains(where: { $0.id == payFrom && $0.householdId == terms.householdId }) {
            throw AppError.unknown("cuenta de otro hogar")
        }
        if let index = creditCardList.firstIndex(where: { $0.accountId == terms.accountId }) {
            creditCardList[index] = terms
        } else {
            creditCardList.append(terms)
        }
        return terms
    }

    public func cardInstallments(in householdId: UUID) async throws -> [CardInstallment] {
        try requireCardMember(of: householdId)
        return installmentList.filter { $0.householdId == householdId }
    }

    public func saveInstallment(_ installment: CardInstallment) async throws -> CardInstallment {
        try requireCardMember(of: installment.householdId)
        if let issue = installment.issue { throw AppError.invalidInput(issue) }
        guard creditCardList.contains(where: { $0.accountId == installment.accountId && $0.householdId == installment.householdId }),
              financeMovements.contains(where: { $0.id == installment.movementId && $0.accountId == installment.accountId })
        else { throw AppError.invalidInput("Sólo se puede aplazar una compra de esta tarjeta.") }
        if let index = installmentList.firstIndex(where: { $0.movementId == installment.movementId }) {
            var saved = installmentList[index]
            saved.months = installment.months
            saved.rate = installment.rate
            installmentList[index] = saved
            return saved
        }
        installmentList.append(installment)
        return installment
    }

    public func deleteInstallment(_ installmentId: UUID) async throws {
        guard let installment = installmentList.first(where: { $0.id == installmentId }) else { return }
        try requireCardMember(of: installment.householdId)
        installmentList.removeAll { $0.id == installmentId }
    }
}
