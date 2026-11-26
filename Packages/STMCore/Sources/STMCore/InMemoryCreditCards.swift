import Foundation

/// Tarjetas en memoria, con las mismas reglas que el servidor: cada miembro ve y toca solo lo suyo,
/// sólo cuentas de tipo tarjeta y un aplazado por compra de esa misma tarjeta.
/// Las condiciones de una tarjeta son de quien creó su cuenta (solo se guardan sobre una cuenta propia).
extension InMemoryBackend: CreditCardService {
    private func requireCardMember(of householdId: UUID, _ operation: String = #function) throws -> UUID {
        let user = try requireUser(operation)
        guard isMember(user, of: householdId) else { throw AppError.unknown("no es miembro") }
        return user
    }

    public func creditCards(in householdId: UUID) async throws -> [CreditCardTerms] {
        let user = try requireCardMember(of: householdId)
        return creditCardList.filter { $0.householdId == householdId && isMine($0.accountId, in: householdId, user: user) }
    }

    public func saveCreditCard(_ terms: CreditCardTerms) async throws -> CreditCardTerms {
        let user = try requireCardMember(of: terms.householdId)
        if let issue = terms.issue { throw AppError.invalidInput(issue) }
        guard financeAccounts.contains(where: { $0.id == terms.accountId && $0.householdId == terms.householdId && $0.kind == .creditCard }),
              isMine(terms.accountId, in: terms.householdId, user: user)
        else { throw AppError.invalidInput("La cuenta no es una tarjeta de crédito.") }
        if let payFrom = terms.payFromAccountId,
           !financeAccounts.contains(where: { $0.id == payFrom && $0.householdId == terms.householdId })
            || !isMine(payFrom, in: terms.householdId, user: user) {
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
        let user = try requireCardMember(of: householdId)
        return installmentList.filter { $0.householdId == householdId && isMine($0.id, in: householdId, user: user) }
    }

    public func saveInstallment(_ installment: CardInstallment) async throws -> CardInstallment {
        let user = try requireCardMember(of: installment.householdId)
        if let issue = installment.issue { throw AppError.invalidInput(issue) }
        guard creditCardList.contains(where: { $0.accountId == installment.accountId && $0.householdId == installment.householdId }),
              isMine(installment.accountId, in: installment.householdId, user: user),
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
        creators[installment.id] = user
        return installment
    }

    public func deleteInstallment(_ installmentId: UUID) async throws {
        guard let installment = installmentList.first(where: { $0.id == installmentId }) else { return }
        let user = try requireCardMember(of: installment.householdId)
        guard isMine(installmentId, in: installment.householdId, user: user) else { return }
        installmentList.removeAll { $0.id == installmentId }
    }
}
