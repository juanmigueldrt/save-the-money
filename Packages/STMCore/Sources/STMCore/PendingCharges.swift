import Foundation

// Pagos fijos que se apuntan solos: al llegar el día de un cargo se crea un «pendiente»
// que no cuenta en saldos ni presupuesto hasta que lo confirmas. Si el cargo llega antes
// por CSV (o lo apuntas a mano), se empareja con ese movimiento y no se duplica.

public enum ChargeStatus: String, Codable, Sendable, CaseIterable {
    case pending, confirmed, skipped
}

/// Un cargo concreto de un pago fijo.
public struct RecurringCharge: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var householdId: UUID
    public var seriesId: UUID
    public var dueOn: CalendarDay
    /// Con signo, como los movimientos: negativo es un gasto.
    public var amount: Money
    public var status: ChargeStatus
    /// El movimiento que lo confirma.
    public var transactionId: UUID?
    /// Versión de la fila: el `updated_at` del servidor tal cual llegó (como `Movement.updatedAt`). Se devuelve igual al cambiarlo.
    public var updatedAt: String?

    public init(id: UUID = UUID(), householdId: UUID, seriesId: UUID, dueOn: CalendarDay, amount: Money,
                status: ChargeStatus = .pending, transactionId: UUID? = nil, updatedAt: String? = nil) {
        self.updatedAt = updatedAt
        self.id = id
        self.householdId = householdId
        self.seriesId = seriesId
        self.dueOn = dueOn
        self.amount = amount
        self.status = status
        self.transactionId = transactionId
    }

    public var isPending: Bool { status == .pending }

    enum CodingKeys: String, CodingKey {
        case id, status
        case householdId = "household_id"
        case seriesId = "series_id"
        case dueOn = "due_on"
        case amountMinor = "amount_minor"
        case transactionId = "transaction_id"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        seriesId = try c.decode(UUID.self, forKey: .seriesId)
        dueOn = try c.decode(CalendarDay.self, forKey: .dueOn)
        amount = Money(minor: try c.decode(Int.self, forKey: .amountMinor))
        status = try c.decode(ChargeStatus.self, forKey: .status)
        transactionId = try c.decodeIfPresent(UUID.self, forKey: .transactionId)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    /// Las columnas que se insertan (el id lo pone el servidor).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(householdId, forKey: .householdId)
        try c.encode(seriesId, forKey: .seriesId)
        try c.encode(dueOn, forKey: .dueOn)
        try c.encode(amount.minor, forKey: .amountMinor)
    }
}

/// Un pendiente listo para enseñar: el cargo con su pago fijo.
public struct PendingCharge: Identifiable, Hashable, Sendable {
    public var charge: RecurringCharge
    public var series: RecurringSeries

    public init(charge: RecurringCharge, series: RecurringSeries) {
        self.charge = charge
        self.series = series
    }

    public var id: UUID { charge.id }
}

public enum PendingCharges {
    /// Cuántos días hacia atrás se miran como mucho, para no llenar la lista de cargos viejos.
    public static let lookbackDays = 62
    /// Margen de días entre el cargo previsto y el movimiento real para emparejarlos.
    public static let matchWindowDays = 5

    /// Los cargos que han llegado (hasta hoy) y aún no están apuntados.
    public static func missing(series: [RecurringSeries], existing: [RecurringCharge],
                               today: CalendarDay) -> [RecurringCharge] {
        let known = Set(existing.map { "\($0.seriesId.uuidString)|\($0.dueOn.iso)" })
        let floor = today.adding(days: -lookbackDays)
        var result: [RecurringCharge] = []
        for item in series where !item.isArchived && item.createsPending {
            let from = max(item.startsOn, item.pendingFrom ?? today, floor)
            for due in item.occurrences(from: from, through: today)
            where !known.contains("\(item.id.uuidString)|\(due.iso)") {
                let amount = item.amount(on: due)
                result.append(RecurringCharge(householdId: item.householdId, seriesId: item.id, dueOn: due,
                                              amount: item.kind == .income ? amount : -amount))
            }
        }
        return result.sorted { $0.dueOn != $1.dueOn ? $0.dueOn < $1.dueOn : $0.seriesId.uuidString < $1.seriesId.uuidString }
    }

    /// Pendientes con su serie, del más antiguo al más nuevo.
    public static func pending(charges: [RecurringCharge], series: [RecurringSeries]) -> [PendingCharge] {
        let byId = Dictionary(series.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return charges.filter(\.isPending)
            .compactMap { charge in byId[charge.seriesId].map { PendingCharge(charge: charge, series: $0) } }
            .sorted { $0.charge.dueOn != $1.charge.dueOn ? $0.charge.dueOn < $1.charge.dueOn : $0.series.trimmedName < $1.series.trimmedName }
    }

    /// Empareja cada pendiente con un movimiento que ya está apuntado: misma cuenta (si la serie
    /// tiene cuenta), mismo signo, como mucho a `matchWindowDays` días y el mismo importe, o un
    /// importe parecido (±25 %) si el concepto lleva el nombre del pago. Cada movimiento sirve
    /// para un solo cargo, y los que ya confirman otro cargo no cuentan.
    /// Devuelve (cargo, movimiento).
    public static func matches(charges: [RecurringCharge], series: [RecurringSeries],
                               movements: [Movement]) -> [(charge: UUID, movement: UUID)] {
        let byId = Dictionary(series.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var used = Set(charges.compactMap(\.transactionId))
        var result: [(UUID, UUID)] = []
        for charge in charges.filter(\.isPending).sorted(by: { $0.dueOn < $1.dueOn }) {
            guard let item = byId[charge.seriesId] else { continue }
            let words = significantWords(item.trimmedName)
            let candidates = movements.filter { movement in
                guard !used.contains(movement.id),
                      movement.amount.isNegative == charge.amount.isNegative,
                      abs(charge.dueOn.days(until: movement.bookedOn)) <= matchWindowDays else { return false }
                if let account = item.accountId, movement.accountId != account { return false }
                if movement.amount.minor == charge.amount.minor { return true }
                let expected = Double(abs(charge.amount.minor)), actual = Double(abs(movement.amount.minor))
                guard expected > 0, abs(actual - expected) / expected <= 0.25, !words.isEmpty else { return false }
                let text = normalized(movement.description + " " + (movement.payee ?? ""))
                return words.contains { text.contains($0) }
            }
            // Primero el mismo importe, después el día más cercano.
            let best = candidates.min { a, b in
                let exactA = a.amount.minor == charge.amount.minor, exactB = b.amount.minor == charge.amount.minor
                if exactA != exactB { return exactA }
                return abs(charge.dueOn.days(until: a.bookedOn)) < abs(charge.dueOn.days(until: b.bookedOn))
            }
            if let best {
                used.insert(best.id)
                result.append((charge.id, best.id))
            }
        }
        return result
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
    }

    /// Palabras del nombre que sirven para reconocerlo (de 3 letras o más).
    static func significantWords(_ name: String) -> [String] {
        normalized(name).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 }
    }
}
