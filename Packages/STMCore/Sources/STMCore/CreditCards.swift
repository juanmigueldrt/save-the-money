import Foundation

// Tarjetas de crédito: condiciones, compras aplazadas y cuánto se paga cada mes.
//
// Cómo funciona el ciclo (con los valores por defecto):
// - El extracto se cierra el día `statementDay` (el 1): lo gastado en enero entra en el extracto del 1 de febrero.
// - Ese extracto se cobra `paymentDelayMonths` meses después (1), el día `paymentDay` (el 1): el 1 de marzo.
// - "Todo a fin de mes" paga el extracto entero sin intereses. "Cuota fija" y "pago mínimo"
//   pagan una parte y el resto genera intereses (TIN `revolvingRate`).
// - Una compra aplazada se paga en N cuotas (sistema francés, TIN `installmentRate`) que se
//   suman al cargo de cada mes, empezando por el extracto de la compra.
// Los movimientos de la tarjeta: negativo = compra o cargo, positivo de una categoría de
// transferencia = pago de la tarjeta, otro positivo = devolución.

// MARK: - Condiciones

public enum CardPaymentMode: String, Codable, CaseIterable, Sendable {
    case full, fixed, minimum

    public var title: String {
        switch self {
        case .full: "Todo a fin de mes"
        case .fixed: "Cuota fija"
        case .minimum: "Pago mínimo"
        }
    }

    public var detail: String {
        switch self {
        case .full: "Pagas el extracto entero cada mes, sin intereses."
        case .fixed: "Pagas la misma cantidad cada mes; lo que queda genera intereses."
        case .minimum: "Pagas lo mínimo que pide el banco; lo que queda genera intereses."
        }
    }

    /// Las formas que dejan deuda pendiente con intereses (revolving).
    public var isRevolving: Bool { self != .full }
}

public struct CreditCardTerms: Identifiable, Hashable, Codable, Sendable {
    public var accountId: UUID
    public var householdId: UUID
    public var creditLimit: Money
    public var statementDay: Int
    public var paymentDay: Int
    public var paymentDelayMonths: Int
    public var paymentMode: CardPaymentMode
    public var fixedPayment: Money?
    /// % del capital del pago mínimo, y su importe mínimo.
    public var minPaymentPercent: Decimal
    public var minPayment: Money
    /// TIN anual en %.
    public var revolvingRate: Decimal
    public var installmentRate: Decimal
    public var payFromAccountId: UUID?
    public var remindDaysBefore: Int?
    /// Aviso al pasar de este % del límite; nil = sin aviso.
    public var alertPercent: Int?
    /// Versión de la fila: el `updated_at` del servidor tal cual llegó (como `Movement.updatedAt`). Nil en unas
    /// condiciones que aún no se han guardado: guardarlas es un alta.
    public var updatedAt: String?

    public var id: UUID { accountId }

    /// TIN anual en % de las compras a plazos cuando la tarjeta no tiene condiciones guardadas (Android usa el mismo).
    public static let defaultInstallmentRate: Decimal = 14

    public init(accountId: UUID, householdId: UUID, creditLimit: Money, statementDay: Int = 1, paymentDay: Int = 1,
                paymentDelayMonths: Int = 1, paymentMode: CardPaymentMode = .full, fixedPayment: Money? = nil,
                minPaymentPercent: Decimal = 3, minPayment: Money = Money(minor: 1500), revolvingRate: Decimal = 20,
                installmentRate: Decimal = CreditCardTerms.defaultInstallmentRate, payFromAccountId: UUID? = nil, remindDaysBefore: Int? = 2,
                alertPercent: Int? = 80, updatedAt: String? = nil) {
        self.updatedAt = updatedAt
        self.accountId = accountId
        self.householdId = householdId
        self.creditLimit = creditLimit
        self.statementDay = statementDay
        self.paymentDay = paymentDay
        self.paymentDelayMonths = paymentDelayMonths
        self.paymentMode = paymentMode
        self.fixedPayment = fixedPayment
        self.minPaymentPercent = minPaymentPercent
        self.minPayment = minPayment
        self.revolvingRate = revolvingRate
        self.installmentRate = installmentRate
        self.payFromAccountId = payFromAccountId
        self.remindDaysBefore = remindDaysBefore
        self.alertPercent = alertPercent
    }

    /// Problema que impide guardarla, en español, o nil si es válida.
    public var issue: String? {
        if creditLimit.minor <= 0 { return "El límite tiene que ser mayor que cero." }
        if !(1...28).contains(statementDay) { return "El día del extracto va del 1 al 28." }
        if !(1...28).contains(paymentDay) { return "El día del cargo va del 1 al 28." }
        if !(0...2).contains(paymentDelayMonths) { return "El cargo puede ser el mismo mes del extracto o hasta dos meses después." }
        if paymentMode == .fixed, (fixedPayment?.minor ?? 0) <= 0 { return "Indica la cuota fija que pagas cada mes." }
        if let fixedPayment, fixedPayment.minor <= 0 { return "La cuota fija tiene que ser mayor que cero." }
        if minPaymentPercent < 0 || minPaymentPercent > 100 { return "El % del pago mínimo va de 0 a 100." }
        if minPayment.minor < 0 { return "El pago mínimo no puede ser negativo." }
        if revolvingRate < 0 || revolvingRate > 60 || installmentRate < 0 || installmentRate > 60 {
            return "El interés tiene que estar entre 0 y 60 %."
        }
        if payFromAccountId == accountId { return "La tarjeta no se puede pagar a sí misma." }
        if let remindDaysBefore, !(0...14).contains(remindDaysBefore) { return "El aviso puede ser de 0 a 14 días antes." }
        if let alertPercent, !(1...100).contains(alertPercent) { return "El aviso del límite va del 1 al 100 %." }
        return nil
    }

    // MARK: Fechas

    /// Día en que se cierra el extracto en el que entra un gasto de `day`.
    public func statementClosing(for day: CalendarDay) -> CalendarDay {
        let thisMonth = CalendarDay(year: day.year, month: day.month, day: statementDay)!
        return day < thisMonth ? thisMonth : thisMonth.adding(months: 1)
    }

    /// Día en que se cobra el extracto que se cierra en `closing`.
    public func paymentDate(forStatement closing: CalendarDay) -> CalendarDay {
        let month = MonthKey(closing).adding(months: paymentDelayMonths)
        return CalendarDay(year: month.year, month: month.month, day: paymentDay)!
    }

    /// Primer día de gasto que entra en el extracto que se cierra en `closing`.
    public func cycleStart(forStatement closing: CalendarDay) -> CalendarDay { closing.adding(months: -1) }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case householdId = "household_id"
        case creditLimitMinor = "credit_limit_minor"
        case statementDay = "statement_day"
        case paymentDay = "payment_day"
        case paymentDelayMonths = "payment_delay_months"
        case paymentMode = "payment_mode"
        case fixedPaymentMinor = "fixed_payment_minor"
        case minPaymentPercent = "min_payment_percent"
        case minPaymentMinor = "min_payment_minor"
        case revolvingRate = "revolving_rate"
        case installmentRate = "installment_rate"
        case payFromAccountId = "pay_from_account_id"
        case remindDaysBefore = "remind_days_before"
        case alertPercent = "alert_percent"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try c.decode(UUID.self, forKey: .accountId)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        creditLimit = Money(minor: try c.decode(Int.self, forKey: .creditLimitMinor))
        statementDay = try c.decode(Int.self, forKey: .statementDay)
        paymentDay = try c.decode(Int.self, forKey: .paymentDay)
        paymentDelayMonths = try c.decode(Int.self, forKey: .paymentDelayMonths)
        paymentMode = try c.decode(CardPaymentMode.self, forKey: .paymentMode)
        fixedPayment = try c.decodeIfPresent(Int.self, forKey: .fixedPaymentMinor).map { Money(minor: $0) }
        minPaymentPercent = try decodeNumeric(c, .minPaymentPercent)
        minPayment = Money(minor: try c.decode(Int.self, forKey: .minPaymentMinor))
        revolvingRate = try decodeNumeric(c, .revolvingRate)
        installmentRate = try decodeNumeric(c, .installmentRate)
        payFromAccountId = try c.decodeIfPresent(UUID.self, forKey: .payFromAccountId)
        remindDaysBefore = try c.decodeIfPresent(Int.self, forKey: .remindDaysBefore)
        alertPercent = try c.decodeIfPresent(Int.self, forKey: .alertPercent)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    /// Codifica todas las columnas que lee `init(from:)`, para guardarlas y volver a leerlas igual.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accountId, forKey: .accountId)
        try c.encode(householdId, forKey: .householdId)
        try c.encode(creditLimit.minor, forKey: .creditLimitMinor)
        try c.encode(statementDay, forKey: .statementDay)
        try c.encode(paymentDay, forKey: .paymentDay)
        try c.encode(paymentDelayMonths, forKey: .paymentDelayMonths)
        try c.encode(paymentMode, forKey: .paymentMode)
        try c.encode(fixedPayment?.minor, forKey: .fixedPaymentMinor)
        try encodeNumeric(minPaymentPercent, &c, .minPaymentPercent)
        try c.encode(minPayment.minor, forKey: .minPaymentMinor)
        try encodeNumeric(revolvingRate, &c, .revolvingRate)
        try encodeNumeric(installmentRate, &c, .installmentRate)
        try c.encode(payFromAccountId, forKey: .payFromAccountId)
        try c.encode(remindDaysBefore, forKey: .remindDaysBefore)
        try c.encode(alertPercent, forKey: .alertPercent)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - Compras aplazadas

public struct CardInstallment: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var householdId: UUID
    public var accountId: UUID
    public var movementId: UUID
    public var months: Int
    /// TIN anual en %.
    public var rate: Decimal
    /// Versión de la fila: el `updated_at` del servidor tal cual llegó (como `Movement.updatedAt`). Nil en un
    /// aplazado que aún no se ha guardado: guardarlo es un alta.
    public var updatedAt: String?

    public init(id: UUID = UUID(), householdId: UUID, accountId: UUID, movementId: UUID, months: Int, rate: Decimal = 14,
                updatedAt: String? = nil) {
        self.updatedAt = updatedAt
        self.id = id
        self.householdId = householdId
        self.accountId = accountId
        self.movementId = movementId
        self.months = months
        self.rate = rate
    }

    /// Plazos que se ofrecen en la app. La base de datos admite de 2 a 48.
    public static let commonMonths = [3, 6, 9, 12]

    public var issue: String? {
        if !(2...48).contains(months) { return "Se puede aplazar de 2 a 48 meses." }
        if rate < 0 || rate > 60 { return "El interés tiene que estar entre 0 y 60 %." }
        return nil
    }

    /// Cuota mensual de una compra de `principal` (en positivo), sistema francés:
    /// P·r/(1 − (1 + r)^−n) = P·r·(1 + r)^n/((1 + r)^n − 1), con r = TIN/1200.
    /// Con `Decimal` a `Decimal.interestScale` decimales y la cuota al céntimo, mitad hacia arriba (igual en Android).
    public static func payment(principal: Money, months: Int, rate: Decimal) -> Money {
        guard months > 0, principal.minor > 0 else { return .zero }
        let p = Decimal(principal.minor)
        guard rate != 0 else { return Money(minor: p.divided(by: Decimal(months), scale: 0).intValue, currency: principal.currency) }
        let scale = Decimal.interestScale
        let r = rate.divided(by: 1200, scale: scale)
        var growth: Decimal = 1
        for _ in 0..<months { growth = growth.multiplied(by: 1 + r, scale: scale) }
        let factor = r.multiplied(by: growth, scale: scale).divided(by: growth - 1, scale: scale)
        return Money(minor: p.multiplied(by: factor, scale: 0).intValue, currency: principal.currency)
    }

    enum CodingKeys: String, CodingKey {
        case id, months, rate
        case householdId = "household_id"
        case accountId = "account_id"
        case movementId = "transaction_id"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        accountId = try c.decode(UUID.self, forKey: .accountId)
        movementId = try c.decode(UUID.self, forKey: .movementId)
        months = try c.decode(Int.self, forKey: .months)
        rate = try decodeNumeric(c, .rate)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    /// Codifica todas las columnas que lee `init(from:)`, para guardarlas y volver a leerlas igual.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(householdId, forKey: .householdId)
        try c.encode(accountId, forKey: .accountId)
        try c.encode(movementId, forKey: .movementId)
        try c.encode(months, forKey: .months)
        try encodeNumeric(rate, &c, .rate)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

/// Condiciones de tarjeta y compras aplazadas del hogar.
public protocol CreditCardService: Sendable {
    func creditCards(in householdId: UUID) async throws -> [CreditCardTerms]
    /// Crea o cambia las condiciones de una tarjeta (una por cuenta). Sin versión (`updatedAt` nil) es un alta:
    /// repetirla devuelve las guardadas y, si ya había otras distintas, falla con `TransferDraft.storedWithOtherData`.
    /// Con versión es un cambio: solo entra si siguen en esa versión; si no, `AppError.movementChanged`.
    func saveCreditCard(_ terms: CreditCardTerms) async throws -> CreditCardTerms
    func cardInstallments(in householdId: UUID) async throws -> [CardInstallment]
    /// Crea o cambia el aplazado de un movimiento (uno por movimiento), con las mismas reglas que `saveCreditCard`:
    /// sin versión es un alta con el `id` que trae; con versión, un cambio de plazo e interés sobre esa versión.
    func saveInstallment(_ installment: CardInstallment) async throws -> CardInstallment
    func deleteInstallment(_ installmentId: UUID) async throws
}

// MARK: - Cálculo

/// Un cargo de la tarjeta en la cuenta de pago.
public struct CardPayment: Hashable, Sendable, Identifiable {
    /// Día en que se cobra.
    public var due: CalendarDay
    /// Extracto que paga (día en que se cierra).
    public var statement: CalendarDay
    /// Lo que se va a cobrar ese día: compras (o la cuota de la deuda) + aplazados.
    public var amount: Money
    /// Parte de compras normales del ciclo (todo a fin de mes) o cuota de la deuda (revolving), con intereses.
    public var purchases: Money
    public var installments: Money
    /// Intereses incluidos en `amount` (del revolving y de los aplazados).
    public var interest: Money
    /// El ciclo aún está abierto: el importe puede subir con nuevas compras.
    public var isEstimate: Bool

    public var id: CalendarDay { due }
}

/// Lo que hay que saber de una tarjeta hoy.
public struct CreditCardSummary: Hashable, Sendable {
    public var terms: CreditCardTerms
    public var today: CalendarDay
    /// Deuda total de la tarjeta (en positivo): lo que resta del límite.
    public var used: Money
    public var available: Money
    /// 0...1 (o más si se pasa del límite).
    public var usedFraction: Double
    /// Extracto que está abierto hoy y lo gastado en él.
    public var openStatement: CalendarDay
    public var spentThisCycle: Money
    /// Próximos cargos, el primero es el siguiente.
    public var payments: [CardPayment]
    /// Deuda con intereses (revolving) que queda tras el último extracto cerrado, sin los aplazados.
    public var revolvingBalance: Money
    /// Intereses que se pagan en los cargos de `payments`.
    public var interestInPayments: Money
    /// Con la forma de pago actual y sin compras nuevas: meses hasta pagar la deuda y sus intereses.
    /// nil si no hay deuda con intereses o si la cuota no llega a cubrir los intereses.
    public var payoff: Payoff?
    /// Aplazados cuya compra no está entre los movimientos recibidos. Sin la compra no se sabe ni la
    /// cuota ni el capital: no salen en `payments` y su deuda queda dentro de `revolvingBalance`.
    /// Si no está vacío, las cifras de la tarjeta no son de fiar.
    public var unresolvedInstallments: [UUID] = []
    /// Abonos sin categoría de los extractos sin cobrar: no se sabe si son un pago de la tarjeta o una
    /// devolución. Hasta que se clasifiquen cuentan como un pago: bajan la deuda, pero no los cargos.
    /// Si no está vacío, hay que pedir que se les ponga categoría.
    public var uncategorizedCredits: [UUID] = []
    /// Los movimientos de los extractos sin cobrar no se han podido cargar todos (hay más que el tope de una
    /// petición): los cargos, lo gastado en el ciclo y la deuda con intereses pueden salir más bajos de lo que son.
    public var movementsTruncated = false

    /// Cuánto tarda en pagarse la deuda con la forma de pago actual y lo que costarán los intereses.
    public struct Payoff: Hashable, Sendable {
        public var months: Int
        public var interest: Money
    }

    public var next: CardPayment? { payments.first }
    public var isOverAlert: Bool {
        guard let alert = terms.alertPercent else { return false }
        return usedFraction * 100 >= Double(alert)
    }
}

public enum CreditCardCalculator {
    /// Extracto (día en que se cierra) más antiguo cuyo cargo aún no ha pasado. Para calcular la tarjeta hacen
    /// falta todos sus movimientos desde `terms.cycleStart(forStatement:)` de este extracto.
    public static func firstUnpaidStatement(terms: CreditCardTerms, today: CalendarDay) -> CalendarDay {
        var closing = terms.statementClosing(for: today).adding(months: -1)
        while terms.paymentDate(forStatement: closing) >= today { closing = closing.adding(months: -1) }
        return closing.adding(months: 1)
    }

    /// - Parameters:
    ///   - balance: saldo actual de la cuenta de la tarjeta (negativo = se debe).
    ///   - movements: movimientos de la tarjeta (los de otras cuentas se ignoran). Tienen que estar los de
    ///     los extractos sin cobrar y la compra de cada aplazado, por antigua que sea.
    ///   - transferCategories: categorías de tipo transferencia: un positivo con una de ellas es un pago de la tarjeta.
    ///   - count: cuántos cargos futuros calcular.
    public static func summary(terms: CreditCardTerms, balance: Money, movements: [Movement],
                               installments: [CardInstallment], transferCategories: Set<UUID>,
                               today: CalendarDay, count: Int = 6) -> CreditCardSummary {
        let count = max(count, 1)
        let mine = movements.filter { $0.accountId == terms.accountId }
        let byId = Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let own = installments.filter { $0.accountId == terms.accountId }
        let plans = own.compactMap { plan -> (CardInstallment, Movement)? in
            guard let movement = byId[plan.movementId], movement.amount.isNegative else { return nil }
            return (plan, movement)
        }
        let unresolved = own.filter { byId[$0.movementId] == nil }.map(\.id)
        let deferred = Set(plans.map { $0.1.id })
        // Compras normales y devoluciones (sin pagos de la tarjeta ni compras aplazadas), en positivo = se debe.
        // Un abono sin categoría no es una devolución: si fuera el pago del extracto anterior, dejaría el cargo a 0.
        let credits = mine.filter { $0.amount.minor > 0 && $0.categoryId == nil }
        let unclassified = Set(credits.map(\.id))
        let charges = mine.filter {
            !deferred.contains($0.id) && !unclassified.contains($0.id) && !isCardPayment($0, transferCategories)
        }

        let used = Money(minor: max(0, -balance.minor))
        let openStatement = terms.statementClosing(for: today)
        func chargesIn(statement closing: CalendarDay) -> Money {
            let start = terms.cycleStart(forStatement: closing)
            return Money(minor: -charges.filter { $0.bookedOn >= start && $0.bookedOn < closing }.map(\.amount.minor).reduce(0, +))
        }
        let spentThisCycle = chargesIn(statement: openStatement)

        // Cuota de cada aplazado que cae en un extracto, y lo que queda por pagar de cada uno.
        func installmentsDue(in statement: CalendarDay) -> (total: Money, interest: Money) {
            var total = 0, interest = 0
            for (plan, movement) in plans {
                let first = terms.statementClosing(for: movement.bookedOn)
                let index = MonthKey(first).monthsUntil(MonthKey(statement))
                guard index >= 0, index < plan.months else { continue }
                let schedule = amortization(principal: -movement.amount, months: plan.months, rate: plan.rate)
                total += schedule[index].payment
                interest += schedule[index].interest
            }
            return (Money(minor: total), Money(minor: interest))
        }
        // Extractos cuyo cargo aún no ha pasado, del más antiguo al más nuevo.
        var statements: [CalendarDay] = []
        var closing = firstUnpaidStatement(terms: terms, today: today)
        while statements.count < count {
            statements.append(closing)
            closing = closing.adding(months: 1)
        }

        // Capital de los aplazados cuyas cuotas aún no se han cobrado: se pagan aparte, en su cuota.
        let firstUnpaid = statements[0]
        // Sólo se avisa de los abonos que caen en un extracto sin cobrar: los anteriores ya no cambian ningún cargo.
        let firstStart = terms.cycleStart(forStatement: firstUnpaid)
        let uncategorized = credits.filter { $0.bookedOn >= firstStart }.map(\.id)
        let deferredPending = plans.reduce(0) { sum, pair in
            let (plan, movement) = pair
            let first = terms.statementClosing(for: movement.bookedOn)
            let paid = max(0, min(plan.months, MonthKey(first).monthsUntil(MonthKey(firstUnpaid))))
            let schedule = amortization(principal: -movement.amount, months: plan.months, rate: plan.rate)
            return sum + schedule.dropFirst(paid).map(\.principal).reduce(0, +)
        }

        var payments: [CardPayment] = []
        // Deuda con intereses: lo que se debe menos lo que aún no ha entrado en un extracto.
        let unbilled = statements.filter { $0 >= openStatement }.map { chargesIn(statement: $0).minor }.reduce(0, +)
        var revolving = max(0, used.minor - unbilled - deferredPending)
        let revolvingAtStart = revolving
        if !terms.paymentMode.isRevolving {
            for statement in statements {
                let normal = statement > openStatement ? Money.zero : chargesIn(statement: statement)
                let fees = installmentsDue(in: statement)
                payments.append(CardPayment(due: terms.paymentDate(forStatement: statement), statement: statement,
                                            amount: Money(minor: max(0, normal.minor)) + fees.total,
                                            purchases: Money(minor: max(0, normal.minor)), installments: fees.total,
                                            interest: fees.interest, isEstimate: statement >= openStatement))
            }
        } else {
            // El capital de los extractos ya cerrados está en `revolving`; los abiertos se van sumando.
            for statement in statements {
                if statement >= openStatement { revolving += max(0, chargesIn(statement: statement).minor) }
                let step = revolvingStep(capital: revolving, terms: terms)
                revolving = step.remaining
                let fees = installmentsDue(in: statement)
                payments.append(CardPayment(due: terms.paymentDate(forStatement: statement), statement: statement,
                                            amount: Money(minor: step.payment) + fees.total,
                                            purchases: Money(minor: step.payment), installments: fees.total,
                                            interest: Money(minor: step.interest) + fees.interest,
                                            isEstimate: statement >= openStatement))
            }
        }

        var payoff: CreditCardSummary.Payoff?
        if terms.paymentMode.isRevolving, revolvingAtStart + spentThisCycle.minor > 0 {
            var capital = revolvingAtStart + max(0, spentThisCycle.minor)
            var interest = 0
            var months = 0
            while capital > 0 && months < 600 {
                let step = revolvingStep(capital: capital, terms: terms)
                if step.payment <= step.interest && step.remaining >= capital { months = 600; break }
                interest += step.interest
                capital = step.remaining
                months += 1
            }
            if months < 600 { payoff = CreditCardSummary.Payoff(months: months, interest: Money(minor: interest)) }
        }

        let limit = max(terms.creditLimit.minor, 1)
        return CreditCardSummary(
            terms: terms, today: today, used: used, available: terms.creditLimit - used,
            usedFraction: Double(used.minor) / Double(limit), openStatement: openStatement,
            spentThisCycle: spentThisCycle, payments: payments, revolvingBalance: Money(minor: revolvingAtStart),
            interestInPayments: Money(minor: payments.map(\.interest.minor).reduce(0, +)), payoff: payoff,
            unresolvedInstallments: unresolved, uncategorizedCredits: uncategorized)
    }

    static func isCardPayment(_ movement: Movement, _ transferCategories: Set<UUID>) -> Bool {
        guard !movement.amount.isNegative, let category = movement.categoryId else { return false }
        return transferCategories.contains(category)
    }

    /// Un mes de revolving: intereses del capital (TIN/12) y la cuota que toca.
    /// Pago mínimo = máx(% del capital + intereses, mínimo), sin pasar de lo que se debe.
    /// Cuota fija = la cuota, sin bajar del mínimo ni pasar de lo que se debe.
    static func revolvingStep(capital: Int, terms: CreditCardTerms) -> (payment: Int, interest: Int, remaining: Int) {
        guard capital > 0 else { return (0, 0, 0) }
        let interest = monthlyInterest(capital, rate: terms.revolvingRate)
        let owed = capital + interest
        let percent = (Decimal(capital) * terms.minPaymentPercent).divided(by: 100, scale: 0).intValue
        let minimum = max(percent + interest, terms.minPayment.minor)
        let wanted = terms.paymentMode == .fixed ? max(terms.fixedPayment?.minor ?? 0, minimum) : minimum
        let payment = min(wanted, owed)
        return (payment, interest, owed - payment)
    }

    /// Intereses de un mes: capital × TIN / 1200, exactos y al céntimo, mitad hacia arriba.
    static func monthlyInterest(_ capital: Int, rate: Decimal) -> Int {
        (Decimal(capital) * rate).divided(by: 1200, scale: 0).intValue
    }

    /// Cuotas de un aplazado: la última ajusta el redondeo para que el capital cuadre.
    static func amortization(principal: Money, months: Int, rate: Decimal) -> [(payment: Int, interest: Int, principal: Int)] {
        let quota = CardInstallment.payment(principal: principal, months: months, rate: rate).minor
        var remaining = principal.minor
        var rows: [(payment: Int, interest: Int, principal: Int)] = []
        for index in 0..<months {
            let interest = monthlyInterest(remaining, rate: rate)
            let part = index == months - 1 ? remaining : min(remaining, quota - interest)
            rows.append((part + interest, interest, part))
            remaining -= part
        }
        return rows
    }
}

extension MonthKey {
    /// Meses de este mes a otro (negativo si el otro es anterior).
    public func monthsUntil(_ other: MonthKey) -> Int {
        (other.year * 12 + other.month) - (year * 12 + month)
    }
}

// MARK: - Avisos

extension ReminderPlanner {
    /// Prefijo de los avisos de cargos de tarjeta.
    public static let cardPrefix = "stm.card."

    /// Aviso antes de cada cargo de tarjeta que tenga importe. `payFromBalance`: saldo de la cuenta de pago, si se conoce.
    public static func plan(cards: [(summary: CreditCardSummary, name: String, payFromBalance: Money?)],
                            today: CalendarDay, limit: Int = 10, hour: Int = 9) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        for card in cards {
            guard let before = card.summary.terms.remindDaysBefore else { continue }
            for payment in card.summary.payments.prefix(3) where payment.amount.minor > 0 {
                let fire = payment.due.adding(days: -before)
                guard fire >= today else { continue }
                let when = before == 0 ? "Hoy" : before == 1 ? "Mañana" : "En \(before) días"
                var body = "Se cobran \(payment.amount.formatted()) el \(payment.due.longTitle)"
                body += payment.isEstimate ? " (de momento; puede subir con nuevas compras)." : "."
                if let balance = card.payFromBalance, balance < payment.amount {
                    body += " En la cuenta de pago sólo hay \(balance.formatted())."
                }
                result.append(PlannedReminder(id: "\(cardPrefix)\(card.summary.terms.accountId.uuidString).\(payment.due.iso)",
                                              fireOn: fire, hour: hour, title: "\(when): cargo de \(card.name)", body: body))
            }
        }
        return Array(result.sorted { $0.fireOn != $1.fireOn ? $0.fireOn < $1.fireOn : $0.id < $1.id }.prefix(limit))
    }
}

extension BudgetAlertPlanner {
    /// Aviso inmediato al pasar del % del límite de una tarjeta; uno por extracto.
    public static func cardAlert(for summary: CreditCardSummary, name: String) -> BudgetAlert? {
        guard summary.isOverAlert, let percent = summary.terms.alertPercent else { return nil }
        return BudgetAlert(id: "\(prefix)card.\(summary.openStatement.iso).\(summary.terms.accountId.uuidString)",
                           title: "\(name): has usado el \(Int((summary.usedFraction * 100).rounded())) % del límite",
                           body: "Te quedan \(summary.available.formatted()) de \(summary.terms.creditLimit.formatted()). El aviso salta al \(percent) %.")
    }
}

// MARK: - Tipo de compra al apuntar un gasto con tarjeta

/// Al apuntar un gasto en una tarjeta: una compra normal, una a plazos o un pago que se repite.
public enum CardPurchaseKind: String, CaseIterable, Sendable {
    case normal, installments, recurring

    public var title: String {
        switch self {
        case .normal: "Normal"
        case .installments: "A plazos"
        case .recurring: "Recurrente"
        }
    }
}

extension CardInstallment {
    /// Plazos que se pueden elegir al apuntar una compra (lo mismo que admite la base de datos).
    public static let allowedMonths = 2...48
    /// Muchos contratos sólo aplazan compras de este importe o más (sólo se avisa, no se bloquea).
    public static let usualMinimum = Money(minor: 5_000)
}

extension RecurringSeries {
    /// El pago fijo que nace de un gasto apuntado con tarjeta: mismo nombre, importe, cuenta y
    /// categoría, empezando ese día. Ese primer cargo ya es el movimiento, así que los pendientes
    /// empiezan al día siguiente. Lleva el id del movimiento (que el formulario elige una vez): guardar otra vez
    /// el mismo formulario no crea otro pago fijo.
    public static func fromPurchase(_ movement: Movement, recurrence: Recurrence = .monthly) -> RecurringSeries {
        RecurringSeries(id: movement.id, householdId: movement.householdId, name: movement.description,
                        kind: movement.amount.isNegative ? .subscription : .income,
                        amount: Money(minor: abs(movement.amount.minor), currency: movement.amount.currency),
                        accountId: movement.accountId, categoryId: movement.categoryId, recurrence: recurrence,
                        startsOn: movement.bookedOn, pendingFrom: movement.bookedOn.adding(days: 1))
    }
}
