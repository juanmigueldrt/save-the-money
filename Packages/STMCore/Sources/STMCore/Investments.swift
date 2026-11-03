import Foundation

// Inversiones: activos, precios apuntados a mano, compras y ventas, y planes de aportación.
// Las participaciones y los precios por participación son `Decimal` (admiten fracciones y
// seis decimales, como en la base de datos); los importes en euros son `Money` (céntimos).

// MARK: - Decimales

extension Decimal {
    /// Redondeado a `scale` decimales. Por defecto, al más cercano (0,5 hacia arriba).
    public func rounded(scale: Int, _ mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

extension Money {
    /// Unos euros con decimales, redondeados al céntimo.
    public init(decimal: Decimal, currency: String = "EUR") {
        let cents = (decimal * 100).rounded(scale: 0)
        self.init(minor: NSDecimalNumber(decimal: cents).intValue, currency: currency)
    }
}

/// Lee un `numeric` de Postgres: PostgREST lo envía como número, pero se acepta también como texto.
private func decodeNumeric<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> Decimal {
    if let text = try? c.decode(String.self, forKey: key) {
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "número no válido")
        }
        return value
    }
    // Como número puede llegar con ruido de coma flotante; la base de datos guarda como mucho 8 decimales.
    return try c.decode(Decimal.self, forKey: key).rounded(scale: 8)
}

// MARK: - Tipos

public enum InvestmentKind: String, Codable, CaseIterable, Sendable {
    case fund, etf, stock, bond, crypto, pension, cash, other

    public var title: String {
        switch self {
        case .fund: "Fondo"
        case .etf: "ETF"
        case .stock: "Acción"
        case .bond: "Bono"
        case .crypto: "Cripto"
        case .pension: "Plan de pensiones"
        case .cash: "Liquidez"
        case .other: "Otro"
        }
    }

    /// La clase que se propone al elegir el tipo.
    public var defaultAssetClass: AssetClass {
        switch self {
        case .fund, .etf, .stock, .pension: .equity
        case .bond: .fixedIncome
        case .crypto: .crypto
        case .cash: .cash
        case .other: .other
        }
    }
}

/// Clase de activo, para el gráfico de distribución.
public enum AssetClass: String, Codable, CaseIterable, Sendable {
    case equity
    case fixedIncome = "fixed_income"
    case crypto, cash, other

    public var title: String {
        switch self {
        case .equity: "Renta variable"
        case .fixedIncome: "Renta fija"
        case .crypto: "Cripto"
        case .cash: "Liquidez"
        case .other: "Otros"
        }
    }
}

public enum TradeSide: String, Codable, CaseIterable, Sendable {
    case buy, sell

    public var title: String {
        switch self {
        case .buy: "Compra"
        case .sell: "Venta"
        }
    }
}

// MARK: - Activo

/// Un fondo, ETF, acción... del hogar. El precio se apunta a mano.
public struct Holding: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var householdId: UUID
    public var name: String
    /// Ticker o ISIN, sólo para reconocerlo.
    public var symbol: String?
    public var kind: InvestmentKind
    public var assetClass: AssetClass
    public var currency: String
    public var accountId: UUID?
    /// nil = compartido; si no, de qué miembro es.
    public var ownerId: UUID?
    /// Último precio por participación.
    public var price: Decimal
    public var priceOn: CalendarDay?
    /// Comisión de compra en % del importe (0,2 = 0,2 %).
    public var feeRate: Decimal
    public var note: String?
    public var archivedAt: Date?

    public init(id: UUID = UUID(), householdId: UUID, name: String, symbol: String? = nil, kind: InvestmentKind = .fund,
                assetClass: AssetClass? = nil, currency: String = "EUR", accountId: UUID? = nil, ownerId: UUID? = nil,
                price: Decimal = 0, priceOn: CalendarDay? = nil, feeRate: Decimal = 0, note: String? = nil,
                archivedAt: Date? = nil) {
        self.id = id
        self.householdId = householdId
        self.name = name
        self.symbol = symbol
        self.kind = kind
        self.assetClass = assetClass ?? kind.defaultAssetClass
        self.currency = currency
        self.accountId = accountId
        self.ownerId = ownerId
        self.price = price
        self.priceOn = priceOn
        self.feeRate = feeRate
        self.note = note
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }
    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var trimmedSymbol: String? {
        let text = symbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text.uppercased()
    }

    /// Dos letras para el icono de la fila: el ticker o las iniciales del nombre.
    public var initials: String {
        if let symbol = trimmedSymbol { return String(symbol.prefix(2)) }
        let words = trimmedName.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let letters = words.count >= 2 ? words.prefix(2).compactMap(\.first) : Array(trimmedName.prefix(2))
        return String(letters).uppercased()
    }

    public var issue: String? {
        if trimmedName.isEmpty { return "Ponle un nombre." }
        if trimmedName.count > 60 { return "El nombre es demasiado largo." }
        if let symbol = trimmedSymbol, symbol.count > 20 { return "El código es demasiado largo." }
        if price < 0 { return "El precio no puede ser negativo." }
        if feeRate < 0 || feeRate > 10 { return "La comisión tiene que estar entre 0 y 10 %." }
        if let note, note.count > 200 { return "La nota es demasiado larga." }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, kind, currency, price, note
        case householdId = "household_id"
        case assetClass = "asset_class"
        case accountId = "account_id"
        case ownerId = "owner_id"
        case priceOn = "price_on"
        case feeRate = "fee_rate"
        case archivedAt = "archived_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        kind = try c.decode(InvestmentKind.self, forKey: .kind)
        assetClass = try c.decode(AssetClass.self, forKey: .assetClass)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "EUR"
        accountId = try c.decodeIfPresent(UUID.self, forKey: .accountId)
        ownerId = try c.decodeIfPresent(UUID.self, forKey: .ownerId)
        price = try decodeNumeric(c, .price)
        priceOn = try c.decodeIfPresent(CalendarDay.self, forKey: .priceOn)
        feeRate = try decodeNumeric(c, .feeRate)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        archivedAt = try c.decodeIfPresent(ServerDate.self, forKey: .archivedAt)?.date
    }

    /// Codifica las columnas editables (sin id, hogar ni moneda, que se fijan al crear).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(trimmedName, forKey: .name)
        try c.encode(trimmedSymbol, forKey: .symbol)
        try c.encode(kind, forKey: .kind)
        try c.encode(assetClass, forKey: .assetClass)
        try c.encode(accountId, forKey: .accountId)
        try c.encode(ownerId, forKey: .ownerId)
        try c.encode(price, forKey: .price)
        try c.encode(priceOn, forKey: .priceOn)
        try c.encode(feeRate, forKey: .feeRate)
        try c.encode(note, forKey: .note)
        try c.encode(archivedAt.map(ServerDate.init), forKey: .archivedAt)
    }
}

/// Un precio apuntado a mano un día concreto (uno por activo y día).
public struct HoldingPrice: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var householdId: UUID
    public var holdingId: UUID
    public var pricedOn: CalendarDay
    public var price: Decimal

    public init(id: UUID = UUID(), householdId: UUID, holdingId: UUID, pricedOn: CalendarDay, price: Decimal) {
        self.id = id
        self.householdId = householdId
        self.holdingId = holdingId
        self.pricedOn = pricedOn
        self.price = price
    }

    enum CodingKeys: String, CodingKey {
        case id, price
        case householdId = "household_id"
        case holdingId = "holding_id"
        case pricedOn = "priced_on"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        holdingId = try c.decode(UUID.self, forKey: .holdingId)
        pricedOn = try c.decode(CalendarDay.self, forKey: .pricedOn)
        price = try decodeNumeric(c, .price)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(householdId, forKey: .householdId)
        try c.encode(holdingId, forKey: .holdingId)
        try c.encode(pricedOn, forKey: .pricedOn)
        try c.encode(price, forKey: .price)
    }
}

// MARK: - Operaciones

/// Una compra o venta de participaciones.
public struct InvestmentTrade: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var householdId: UUID
    public var holdingId: UUID
    public var tradedOn: CalendarDay
    public var side: TradeSide
    public var quantity: Decimal
    /// Precio por participación en la operación.
    public var price: Decimal
    public var fee: Money
    public var note: String?

    public init(id: UUID = UUID(), householdId: UUID, holdingId: UUID, tradedOn: CalendarDay, side: TradeSide = .buy,
                quantity: Decimal, price: Decimal, fee: Money = .zero, note: String? = nil) {
        self.id = id
        self.householdId = householdId
        self.holdingId = holdingId
        self.tradedOn = tradedOn
        self.side = side
        self.quantity = quantity
        self.price = price
        self.fee = fee
        self.note = note
    }

    /// Participaciones por precio, sin la comisión.
    public var gross: Money { Money(decimal: quantity * price) }

    /// Lo que sale de la cuenta en una compra (más la comisión) o entra en una venta (menos la comisión).
    public var cashImpact: Money { side == .buy ? -(gross + fee) : gross - fee }

    public var issue: String? {
        if quantity <= 0 { return "Indica cuántas participaciones." }
        if quantity.rounded(scale: 8) != quantity { return "Como mucho 8 decimales en las participaciones." }
        if price < 0 { return "El precio no puede ser negativo." }
        if fee.isNegative { return "La comisión no puede ser negativa." }
        if let note, note.count > 200 { return "La nota es demasiado larga." }
        return nil
    }

    /// Además de `issue`: no se pueden vender más participaciones de las que había ese día.
    public func issue(given others: [InvestmentTrade]) -> String? {
        if let issue { return issue }
        guard side == .sell else { return nil }
        let held = Position.quantity(of: holdingId, in: others.filter { $0.id != id }, through: tradedOn)
        return quantity > held ? "No tienes tantas participaciones para vender." : nil
    }

    enum CodingKeys: String, CodingKey {
        case id, side, quantity, price, note
        case householdId = "household_id"
        case holdingId = "holding_id"
        case tradedOn = "traded_on"
        case feeMinor = "fee_minor"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        holdingId = try c.decode(UUID.self, forKey: .holdingId)
        tradedOn = try c.decode(CalendarDay.self, forKey: .tradedOn)
        side = try c.decode(TradeSide.self, forKey: .side)
        quantity = try decodeNumeric(c, .quantity)
        price = try decodeNumeric(c, .price)
        fee = Money(minor: try c.decode(Int.self, forKey: .feeMinor))
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(householdId, forKey: .householdId)
        try c.encode(holdingId, forKey: .holdingId)
        try c.encode(tradedOn, forKey: .tradedOn)
        try c.encode(side, forKey: .side)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(price, forKey: .price)
        try c.encode(fee.minor, forKey: .feeMinor)
        try c.encode(note, forKey: .note)
    }
}

// MARK: - Compra

/// El cálculo de "Comprar activo": por importe o por participaciones.
public struct BuyQuote: Hashable, Sendable {
    /// Lo que se invierte, sin comisión.
    public var amount: Money
    public var quantity: Decimal
    public var fee: Money
    /// Lo que sale de la cuenta.
    public var total: Money { amount + fee }

    /// Comprar por importe: participaciones = importe / precio (hacia abajo, 8 decimales).
    public static func byAmount(_ amount: Money, price: Decimal, feeRate: Decimal) -> BuyQuote? {
        guard amount.minor > 0, price > 0 else { return nil }
        let quantity = (amount.decimal / price).rounded(scale: 8, .down)
        guard quantity > 0 else { return nil }
        return BuyQuote(amount: amount, quantity: quantity, fee: fee(on: amount, rate: feeRate))
    }

    /// Comprar por participaciones: importe = participaciones × precio, al céntimo.
    public static func byQuantity(_ quantity: Decimal, price: Decimal, feeRate: Decimal) -> BuyQuote? {
        guard quantity > 0, price > 0 else { return nil }
        let amount = Money(decimal: quantity.rounded(scale: 8, .down) * price)
        guard amount.minor > 0 else { return nil }
        return BuyQuote(amount: amount, quantity: quantity.rounded(scale: 8, .down), fee: fee(on: amount, rate: feeRate))
    }

    /// Comisión = importe × porcentaje / 100, al céntimo.
    public static func fee(on amount: Money, rate: Decimal) -> Money {
        Money(decimal: amount.decimal * rate / 100, currency: amount.currency)
    }

    /// La operación que se guarda al confirmar.
    public func trade(for holding: Holding, price: Decimal, on day: CalendarDay, note: String? = nil) -> InvestmentTrade {
        InvestmentTrade(householdId: holding.householdId, holdingId: holding.id, tradedOn: day, side: .buy,
                        quantity: quantity, price: price, fee: fee, note: note)
    }
}

// MARK: - Posición

/// Lo que se tiene de un activo, con el método del precio medio:
/// cada compra suma su coste (con comisión); cada venta saca la parte proporcional del coste.
public struct Position: Hashable, Sendable, Identifiable {
    public var holding: Holding
    public var quantity: Decimal
    /// Coste de las participaciones que quedan, con comisiones.
    public var cost: Money
    /// Ganancia ya hecha con las ventas, después de comisiones.
    public var realized: Money
    /// Todo lo comprado, con comisiones.
    public var invested: Money

    public var id: UUID { holding.id }

    /// Coste por participación de las que quedan.
    public var averagePrice: Decimal { quantity > 0 ? (cost.decimal / quantity).rounded(scale: 6) : 0 }
    public var value: Money { Money(decimal: quantity * holding.price, currency: holding.currency) }
    public var gain: Money { value - cost }
    /// Ganancia sobre el coste; nil si no queda nada.
    public var gainFraction: Double? { cost.minor > 0 ? Double(gain.minor) / Double(cost.minor) : nil }

    public init(holding: Holding, trades: [InvestmentTrade], through day: CalendarDay? = nil) {
        self.holding = holding
        var quantity: Decimal = 0
        var costMinor = 0
        var realizedMinor = 0
        var investedMinor = 0
        for trade in Self.ordered(trades, of: holding.id, through: day) {
            switch trade.side {
            case .buy:
                quantity += trade.quantity
                costMinor += trade.gross.minor + trade.fee.minor
                investedMinor += trade.gross.minor + trade.fee.minor
            case .sell:
                guard quantity > 0 else { continue }
                let sold = min(trade.quantity, quantity)
                let removed = Money(decimal: Decimal(costMinor) * sold / quantity / 100).minor
                realizedMinor += Money(decimal: sold * trade.price).minor - trade.fee.minor - removed
                costMinor -= removed
                quantity -= sold
            }
        }
        self.quantity = quantity
        self.cost = Money(minor: quantity > 0 ? costMinor : 0, currency: holding.currency)
        self.realized = Money(minor: realizedMinor, currency: holding.currency)
        self.invested = Money(minor: investedMinor, currency: holding.currency)
    }

    /// Participaciones de un activo después de las operaciones de ese día.
    public static func quantity(of holdingId: UUID, in trades: [InvestmentTrade], through day: CalendarDay?) -> Decimal {
        ordered(trades, of: holdingId, through: day).reduce(Decimal(0)) { held, trade in
            trade.side == .buy ? held + trade.quantity : max(0, held - trade.quantity)
        }
    }

    /// Las operaciones del activo por fecha; el mismo día, las compras antes que las ventas.
    static func ordered(_ trades: [InvestmentTrade], of holdingId: UUID, through day: CalendarDay?) -> [InvestmentTrade] {
        trades.filter { trade in trade.holdingId == holdingId && (day.map { trade.tradedOn <= $0 } ?? true) }
            .sorted { a, b in
                if a.tradedOn != b.tradedOn { return a.tradedOn < b.tradedOn }
                return a.side == .buy && b.side == .sell
            }
    }
}

// MARK: - Cartera

/// Una porción del gráfico de distribución.
public struct AllocationSlice: Hashable, Sendable, Identifiable {
    public var assetClass: AssetClass
    public var value: Money
    public var fraction: Double
    public var id: AssetClass { assetClass }
}

/// Todas las posiciones del hogar con algo dentro.
public struct Portfolio: Hashable, Sendable {
    public var positions: [Position]

    public init(holdings: [Holding], trades: [InvestmentTrade]) {
        positions = holdings.filter { !$0.isArchived }
            .map { Position(holding: $0, trades: trades) }
            .filter { $0.quantity > 0 }
            .sorted { $0.value.minor != $1.value.minor ? $0.value.minor > $1.value.minor : $0.holding.trimmedName < $1.holding.trimmedName }
    }

    public var value: Money { positions.reduce(Money.zero) { $0 + $1.value } }
    public var cost: Money { positions.reduce(Money.zero) { $0 + $1.cost } }
    public var gain: Money { value - cost }
    public var gainFraction: Double? { cost.minor > 0 ? Double(gain.minor) / Double(cost.minor) : nil }

    /// Por clase de activo, de mayor a menor, sin las vacías.
    public var allocation: [AllocationSlice] {
        let total = value.minor
        guard total > 0 else { return [] }
        let byClass = Dictionary(grouping: positions, by: \.holding.assetClass)
            .mapValues { $0.reduce(0) { $0 + $1.value.minor } }
        return AssetClass.allCases.compactMap { assetClass in
            guard let minor = byClass[assetClass], minor > 0 else { return nil }
            return AllocationSlice(assetClass: assetClass, value: Money(minor: minor),
                                   fraction: Double(minor) / Double(total))
        }
        .sorted { $0.value.minor > $1.value.minor }
    }
}

// MARK: - Evolución

/// Los rangos del gráfico de evolución y del de precio.
public enum ChartRange: String, CaseIterable, Sendable, Identifiable {
    case day = "1D", week = "1S", month = "1M", halfYear = "6M", year = "1A", fiveYears = "5A", all = "Todo"

    public var id: String { rawValue }
    public var title: String { rawValue }

    /// Los de la cartera y los del gráfico de precio de "Comprar activo".
    public static let portfolio: [ChartRange] = [.week, .month, .halfYear, .year, .all]
    public static let price: [ChartRange] = [.day, .week, .month, .year, .fiveYears]

    /// Primer día del rango; para "Todo", el que se pase.
    public func start(today: CalendarDay, earliest: CalendarDay?) -> CalendarDay {
        switch self {
        case .day: today.adding(days: -1)
        case .week: today.adding(days: -7)
        case .month: today.adding(months: -1)
        case .halfYear: today.adding(months: -6)
        case .year: today.adding(months: -12)
        case .fiveYears: today.adding(months: -60)
        case .all: min(earliest ?? today.adding(months: -1), today)
        }
    }

    /// Días del gráfico: como mucho `maxPoints`, repartidos, siempre con el primero y hoy.
    public func days(today: CalendarDay, earliest: CalendarDay?, maxPoints: Int = 60) -> [CalendarDay] {
        let first = start(today: today, earliest: earliest)
        let span = first.days(until: today)
        guard span > 0 else { return [today] }
        let step = max(1, Int((Double(span) / Double(max(1, maxPoints - 1))).rounded(.up)))
        var days = Array(stride(from: 0, to: span, by: step).map { first.adding(days: $0) })
        days.append(today)
        return days
    }
}

public struct PortfolioPoint: Hashable, Sendable, Identifiable {
    public var day: CalendarDay
    public var value: Money
    public var id: CalendarDay { day }
}

public enum PriceHistory {
    /// Precios conocidos de un activo por fecha: los apuntados, los de las operaciones
    /// y el último del activo. El mismo día manda el apuntado a mano.
    public static func points(for holding: Holding, prices: [HoldingPrice], trades: [InvestmentTrade]) -> [(CalendarDay, Decimal)] {
        var byDay: [CalendarDay: Decimal] = [:]
        for trade in trades where trade.holdingId == holding.id { byDay[trade.tradedOn] = trade.price }
        for price in prices where price.holdingId == holding.id { byDay[price.pricedOn] = price.price }
        if let priceOn = holding.priceOn { byDay[priceOn] = holding.price }
        return byDay.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// El último precio conocido en ese día o antes. Sin ninguno, el primero que haya.
    static func price(on day: CalendarDay, in points: [(CalendarDay, Decimal)], fallback: Decimal) -> Decimal {
        points.last { $0.0 <= day }?.1 ?? points.first?.1 ?? fallback
    }

    /// Valor de la cartera en cada día del rango.
    public static func evolution(holdings: [Holding], prices: [HoldingPrice], trades: [InvestmentTrade],
                                 range: ChartRange, today: CalendarDay) -> [PortfolioPoint] {
        let active = holdings.filter { !$0.isArchived }
        let earliest = trades.filter { t in active.contains { $0.id == t.holdingId } }.map(\.tradedOn).min()
        let series = Dictionary(uniqueKeysWithValues: active.map { ($0.id, points(for: $0, prices: prices, trades: trades)) })
        return range.days(today: today, earliest: earliest).map { day in
            let minor = active.reduce(0) { sum, holding in
                let held = Position.quantity(of: holding.id, in: trades, through: day)
                guard held > 0 else { return sum }
                let price = day >= today ? holding.price : self.price(on: day, in: series[holding.id] ?? [], fallback: holding.price)
                return sum + Money(decimal: held * price).minor
            }
            return PortfolioPoint(day: day, value: Money(minor: minor))
        }
    }

    /// Mínimo y máximo de los precios conocidos en el rango (para "Mín. / Máx. 1 año").
    public static func range(for holding: Holding, prices: [HoldingPrice], trades: [InvestmentTrade],
                             from: CalendarDay, through: CalendarDay) -> ClosedRange<Decimal>? {
        let values = points(for: holding, prices: prices, trades: trades)
            .filter { $0.0 >= from && $0.0 <= through }.map(\.1)
        guard let low = values.min(), let high = values.max() else { return nil }
        return low...high
    }
}

// MARK: - Aportaciones automáticas

/// Un plan para invertir una cantidad fija cada cierto tiempo. No compra solo:
/// avisa el día que toca y la compra se confirma en la app.
public struct InvestmentPlan: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var householdId: UUID
    public var holdingId: UUID
    public var accountId: UUID?
    public var amount: Money
    public var recurrence: Recurrence
    public var startsOn: CalendarDay
    public var endsOn: CalendarDay?
    /// Rentabilidad anual supuesta, en % (5 = 5 %).
    public var expectedAnnualReturn: Decimal
    public var remindDaysBefore: Int?
    public var pausedAt: Date?
    public var archivedAt: Date?

    public init(id: UUID = UUID(), householdId: UUID, holdingId: UUID, accountId: UUID? = nil, amount: Money,
                recurrence: Recurrence = .monthly, startsOn: CalendarDay, endsOn: CalendarDay? = nil,
                expectedAnnualReturn: Decimal = 5, remindDaysBefore: Int? = 1, pausedAt: Date? = nil,
                archivedAt: Date? = nil) {
        self.id = id
        self.householdId = householdId
        self.holdingId = holdingId
        self.accountId = accountId
        self.amount = amount
        self.recurrence = recurrence
        self.startsOn = startsOn
        self.endsOn = endsOn
        self.expectedAnnualReturn = expectedAnnualReturn
        self.remindDaysBefore = remindDaysBefore
        self.pausedAt = pausedAt
        self.archivedAt = archivedAt
    }

    public var isPaused: Bool { pausedAt != nil }
    public var isArchived: Bool { archivedAt != nil }

    /// Cuenta en el total mensual y avisa: ni en pausa, ni archivado, ni terminado.
    public func isActive(on day: CalendarDay) -> Bool {
        !isPaused && !isArchived && (endsOn.map { $0 >= day } ?? true)
    }

    /// El calendario de cargos es el mismo que el de un pago recurrente.
    private var schedule: RecurringSeries {
        RecurringSeries(householdId: householdId, name: "plan", amount: amount, recurrence: recurrence,
                        startsOn: startsOn, endsOn: endsOn)
    }

    public func occurrences(from: CalendarDay, through: CalendarDay) -> [CalendarDay] {
        schedule.occurrences(from: from, through: through)
    }

    public func nextDue(onOrAfter day: CalendarDay) -> CalendarDay? {
        isPaused || isArchived ? nil : schedule.nextDue(onOrAfter: day)
    }

    /// Lo que supone al mes, en promedio.
    public var monthlyAmount: Money { schedule.monthlyAmount }

    /// Lo que se ha comprado del activo desde que empezó el plan, con comisiones.
    public func invested(trades: [InvestmentTrade], through day: CalendarDay) -> Money {
        trades.filter { $0.holdingId == holdingId && $0.side == .buy && $0.tradedOn >= startsOn && $0.tradedOn <= day }
            .reduce(Money.zero) { $0 + $1.gross + $1.fee }
    }

    /// Lo que valdrían dentro de `months` meses las aportaciones de ese tiempo, a la
    /// rentabilidad supuesta (interés compuesto mensual, cada aportación al empezar el mes).
    public func projectedValue(months: Int) -> Money {
        guard months > 0 else { return .zero }
        let monthly = Double(monthlyAmount.minor)
        let rate = pow(1 + expectedAnnualReturn.doubleValue / 100, 1.0 / 12) - 1
        let factor = abs(rate) < 1e-12 ? Double(months) : (pow(1 + rate, Double(months)) - 1) / rate * (1 + rate)
        return Money(minor: Int((monthly * factor).rounded()), currency: amount.currency)
    }

    public var issue: String? {
        if amount.minor <= 0 { return "El importe tiene que ser mayor que cero." }
        if !(1...52).contains(recurrence.every) { return "La frecuencia no es válida." }
        if let endsOn, endsOn < startsOn { return "No puede terminar antes de empezar." }
        if expectedAnnualReturn < -50 || expectedAnnualReturn > 50 { return "La rentabilidad supuesta tiene que estar entre −50 y 50 %." }
        if let days = remindDaysBefore, !(0...14).contains(days) { return "El aviso puede ser de 0 a 14 días antes." }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, every, unit
        case householdId = "household_id"
        case holdingId = "holding_id"
        case accountId = "account_id"
        case amountMinor = "amount_minor"
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case expectedAnnualReturn = "expected_annual_return"
        case remindDaysBefore = "remind_days_before"
        case pausedAt = "paused_at"
        case archivedAt = "archived_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdId = try c.decode(UUID.self, forKey: .householdId)
        holdingId = try c.decode(UUID.self, forKey: .holdingId)
        accountId = try c.decodeIfPresent(UUID.self, forKey: .accountId)
        amount = Money(minor: try c.decode(Int.self, forKey: .amountMinor))
        recurrence = Recurrence(every: try c.decode(Int.self, forKey: .every), unit: try c.decode(RecurrenceUnit.self, forKey: .unit))
        startsOn = try c.decode(CalendarDay.self, forKey: .startsOn)
        endsOn = try c.decodeIfPresent(CalendarDay.self, forKey: .endsOn)
        expectedAnnualReturn = try decodeNumeric(c, .expectedAnnualReturn)
        remindDaysBefore = try c.decodeIfPresent(Int.self, forKey: .remindDaysBefore)
        pausedAt = try c.decodeIfPresent(ServerDate.self, forKey: .pausedAt)?.date
        archivedAt = try c.decodeIfPresent(ServerDate.self, forKey: .archivedAt)?.date
    }

    /// Codifica las columnas editables (sin id, hogar ni activo, que se fijan al crear).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accountId, forKey: .accountId)
        try c.encode(amount.minor, forKey: .amountMinor)
        try c.encode(recurrence.every, forKey: .every)
        try c.encode(recurrence.unit, forKey: .unit)
        try c.encode(startsOn, forKey: .startsOn)
        try c.encode(endsOn, forKey: .endsOn)
        try c.encode(expectedAnnualReturn, forKey: .expectedAnnualReturn)
        try c.encode(remindDaysBefore, forKey: .remindDaysBefore)
        try c.encode(pausedAt.map(ServerDate.init), forKey: .pausedAt)
        try c.encode(archivedAt.map(ServerDate.init), forKey: .archivedAt)
    }
}

/// Una aportación concreta del calendario.
public struct PlanCharge: Hashable, Sendable, Identifiable {
    public var plan: InvestmentPlan
    public var due: CalendarDay
    public var id: String { "\(plan.id.uuidString)-\(due.iso)" }
}

extension Array where Element == InvestmentPlan {
    /// Aportaciones de los planes activos en un mes, por fecha (para el calendario).
    public func charges(in month: MonthKey) -> [PlanCharge] {
        let first = month.firstDay
        let last = month.adding(months: 1).firstDay.adding(days: -1)
        return filter { !$0.isPaused && !$0.isArchived }
            .flatMap { plan in plan.occurrences(from: first, through: last).map { PlanCharge(plan: plan, due: $0) } }
            .sorted { $0.due != $1.due ? $0.due < $1.due : $0.plan.amount.minor > $1.plan.amount.minor }
    }

    /// Lo que suman al mes los planes activos ("420 € al mes").
    public func monthlyTotal(on day: CalendarDay) -> Money {
        filter { $0.isActive(on: day) }.reduce(Money.zero) { $0 + $1.monthlyAmount }
    }

    /// Cuántos están activos y cuántos en pausa (los archivados no cuentan).
    public func counts(on day: CalendarDay) -> (active: Int, paused: Int) {
        let live = filter { !$0.isArchived && ($0.endsOn.map { $0 >= day } ?? true) }
        return (live.filter { !$0.isPaused }.count, live.filter(\.isPaused).count)
    }
}
