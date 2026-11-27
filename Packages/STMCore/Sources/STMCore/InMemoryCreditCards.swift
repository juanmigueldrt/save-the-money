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
        if let issue = terms.issue { throw AppError.validation(.cardTerms(issue)) }
        let index = creditCardList.firstIndex(where: { $0.accountId == terms.accountId })
        if terms.updatedAt != nil {
            // Cambio: solo de unas condiciones propias y sobre la versión leída (el STM05 del servidor).
            guard let index, isMine(terms.accountId, in: terms.householdId, user: user),
                  creditCardList[index].updatedAt == terms.updatedAt else { throw AppError.movementChanged }
        }
        guard financeAccounts.contains(where: { $0.id == terms.accountId && $0.householdId == terms.householdId && $0.kind == .creditCard }),
              isMine(terms.accountId, in: terms.householdId, user: user)
        else { throw AppError.invalidInput(localized("La cuenta no es una tarjeta de crédito.")) }
        if let payFrom = terms.payFromAccountId,
           !financeAccounts.contains(where: { $0.id == payFrom && $0.householdId == terms.householdId })
            || !isMine(payFrom, in: terms.householdId, user: user) {
            throw AppError.unknown("cuenta de otro hogar")
        }
        var saved = terms
        saved.updatedAt = nextVersion()
        if terms.updatedAt != nil, let index {
            creditCardList[index] = saved
            return saved
        }
        // Alta: repetirla solo vale con el mismo límite, días y forma de pago.
        if let stored = try replayed(index.map { creditCardList[$0] }, by: user, same: {
            $0.householdId == terms.householdId && $0.creditLimit.minor == terms.creditLimit.minor
                && $0.statementDay == terms.statementDay && $0.paymentDay == terms.paymentDay
                && $0.paymentMode == terms.paymentMode
        }) { return stored }
        creditCardList.append(saved)
        return saved
    }

    public func cardInstallments(in householdId: UUID) async throws -> [CardInstallment] {
        let user = try requireCardMember(of: householdId)
        return installmentList.filter { $0.householdId == householdId && isMine($0.id, in: householdId, user: user) }
    }

    public func saveInstallment(_ installment: CardInstallment) async throws -> CardInstallment {
        let user = try requireCardMember(of: installment.householdId)
        if let issue = installment.issue { throw AppError.validation(.installment(issue)) }
        if installment.updatedAt != nil {
            // Cambio: solo plazo e interés, de un aplazado propio y sobre la versión leída (el STM05 del servidor).
            guard let index = installmentList.firstIndex(where: { $0.id == installment.id }),
                  isMine(installment.id, in: installmentList[index].householdId, user: user),
                  installmentList[index].updatedAt == installment.updatedAt else { throw AppError.movementChanged }
            var saved = installmentList[index]
            saved.months = installment.months
            saved.rate = installment.rate
            saved.updatedAt = nextVersion()
            installmentList[index] = saved
            return saved
        }
        guard creditCardList.contains(where: { $0.accountId == installment.accountId && $0.householdId == installment.householdId }),
              isMine(installment.accountId, in: installment.householdId, user: user),
              financeMovements.contains(where: { $0.id == installment.movementId && $0.accountId == installment.accountId })
        else { throw AppError.invalidInput(localized("Sólo se puede aplazar una compra de esta tarjeta.")) }
        // Alta: repetirla solo vale con la misma compra, plazo e interés.
        if let stored = try replayed(installmentList.first(where: { $0.id == installment.id }), by: user, same: {
            $0.movementId == installment.movementId && $0.months == installment.months && $0.rate == installment.rate
        }) { return stored }
        // Como el índice único del servidor: un aplazado por compra.
        guard !installmentList.contains(where: { $0.movementId == installment.movementId }) else {
            throw AppError.idUsedBySomeoneElse
        }
        var saved = installment
        saved.updatedAt = nextVersion()
        installmentList.append(saved)
        creators[saved.id] = user
        return saved
    }

    public func deleteInstallment(_ installmentId: UUID) async throws {
        guard let installment = installmentList.first(where: { $0.id == installmentId }) else { return }
        let user = try requireCardMember(of: installment.householdId)
        guard isMine(installmentId, in: installment.householdId, user: user) else { return }
        installmentList.removeAll { $0.id == installmentId }
    }
}
