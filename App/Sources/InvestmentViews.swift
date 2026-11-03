import SwiftUI
import Charts
import STMCore
import STMUI

// MARK: - Formatos

enum InvestmentText {
    private static let spain = Locale(identifier: "es_ES")

    /// "12,5034 €": precio por participación, de 2 a 4 decimales.
    static func price(_ value: Decimal, currency: String = "EUR") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = spain
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// "12,5" participaciones, hasta 6 decimales.
    static func quantity(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = spain
        formatter.maximumFractionDigits = 6
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// "+12,3 %" o "−4,0 %".
    static func percent(_ fraction: Double) -> String {
        let value = (fraction * 1000).rounded() / 10
        let text = String(format: "%.1f", abs(value)).replacingOccurrences(of: ".", with: ",")
        return (value > 0 ? "+" : value < 0 ? "\u{2212}" : "") + text + " %"
    }

    /// "+150,00 €" con signo también cuando gana.
    static func signed(_ amount: Money) -> String {
        amount.minor > 0 ? "+" + amount.formatted() : amount.formatted()
    }

    /// "0,2 %" para la comisión.
    static func rate(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = spain
        formatter.maximumFractionDigits = 3
        return (formatter.string(from: value as NSDecimalNumber) ?? "\(value)") + " %"
    }

    /// Texto editable de un decimal: "12,5".
    static func plain(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = spain
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 8
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    static func gainColor(_ amount: Money) -> Color {
        amount.minor > 0 ? Palette.positiveText : amount.minor < 0 ? Palette.negativeText : Palette.labelSecondary
    }
}

extension AssetClass {
    /// Colores del gráfico de distribución, con los tokens del manual.
    var color: Color {
        switch self {
        case .equity: Palette.accent
        case .fixedIncome: Palette.label
        case .crypto: Palette.positive
        case .cash: Palette.labelSecondary
        case .other: Palette.labelTertiary
        }
    }
}

// MARK: - Cartera

/// Cartera del hogar: total, rentabilidad, evolución, distribución y activos.
struct InvestmentsView: View {
    @Environment(InvestmentModel.self) private var investments
    @State private var addingHolding = false
    @State private var buying = false

    var body: some View {
        let portfolio = investments.portfolio
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                header(portfolio)
                if investments.activeHoldings.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text("Sin inversiones todavía")
                            .titleFont(.title2)
                            .foregroundStyle(Palette.label)
                        EmptyHint(text: "Añade un fondo, un ETF o una acción y apunta tus compras. Los precios los apuntas tú cuando quieras; la app no se conecta a ningún bróker.")
                        Button("Añadir un activo") { addingHolding = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .card()
                } else {
                    AdaptiveColumns {
                        VStack(alignment: .leading, spacing: Spacing.s24) {
                            evolutionCard
                            allocationCard(portfolio)
                        }
                    } trailing: {
                        VStack(alignment: .leading, spacing: Spacing.s24) {
                            holdingsCard
                            actions
                        }
                    }
                }
                Text("Esto no es asesoramiento de inversión. Los valores salen de los precios que apuntas a mano.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                ErrorText(message: investments.error)
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Inversiones")
        .navigationDestination(for: Holding.self) { HoldingDetailView(holdingId: $0.id) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nuevo activo", systemImage: "plus") { addingHolding = true }
            }
        }
        .task { await investments.load() }
        .refreshable { await investments.load() }
        .sheet(isPresented: $addingHolding) { HoldingFormView(holding: nil) }
        .sheet(isPresented: $buying) { BuyPickerView() }
    }

    private func header(_ portfolio: Portfolio) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            Eyebrow("Tu cartera")
            Text(portfolio.value.formatted())
                .titleFont(.largeTitle)
                .foregroundStyle(Palette.label)
                .contentTransition(.numericText())
            if portfolio.cost.minor > 0 {
                HStack(spacing: Spacing.s8) {
                    Text(InvestmentText.signed(portfolio.gain))
                    if let fraction = portfolio.gainFraction { Text("(\(InvestmentText.percent(fraction)))") }
                }
                .font(Typography.subheadlineEmphasis)
                .foregroundStyle(InvestmentText.gainColor(portfolio.gain))
                Text("Invertido: \(portfolio.cost.formatted())")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    private var evolutionCard: some View {
        @Bindable var investments = investments
        let points = investments.evolution
        return VStack(alignment: .leading, spacing: Spacing.s16) {
            Text("Evolución")
                .titleFont(.title2)
                .foregroundStyle(Palette.label)
            CapsuleSegmented("Periodo", selection: $investments.range, options: ChartRange.portfolio) { $0.title }
            Chart(points) { point in
                AreaMark(x: .value("Día", point.day.date()), y: .value("Valor", point.value.decimal))
                    .foregroundStyle(Palette.accent.opacity(0.12))
                LineMark(x: .value("Día", point.day.date()), y: .value("Valor", point.value.decimal))
                    .foregroundStyle(Palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartHeight(180)
            .accessibilityLabel("Gráfico de la evolución de la cartera")
        }
        .card()
    }

    private func allocationCard(_ portfolio: Portfolio) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text("Distribución")
                .titleFont(.title2)
                .foregroundStyle(Palette.label)
            SemicircleDonut(slices: portfolio.allocation)
                .frame(height: 120)
                .frame(maxWidth: 280)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            ForEach(portfolio.allocation) { slice in
                HStack(spacing: Spacing.s8) {
                    Circle().fill(slice.assetClass.color).frame(width: 10, height: 10)
                    Text(slice.assetClass.title)
                        .font(Typography.subheadline)
                        .foregroundStyle(Palette.label)
                    Spacer()
                    Text("\(Int((slice.fraction * 100).rounded())) %")
                        .font(Typography.subheadlineEmphasis)
                        .foregroundStyle(Palette.label)
                    Text(slice.value.formatted())
                        .font(Typography.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.labelSecondary)
                        .frame(minWidth: 96, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private var holdingsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tus activos")
                    .titleFont(.title2)
                    .foregroundStyle(Palette.label)
                Spacer()
                Text("\(investments.activeHoldings.count)")
                    .font(Typography.subheadlineEmphasis)
                    .foregroundStyle(Palette.labelSecondary)
            }
            ForEach(investments.activeHoldings) { holding in
                NavigationLink(value: holding) {
                    HoldingRow(position: investments.position(of: holding),
                               owner: investments.ownerName(holding.ownerId))
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private var actions: some View {
        VStack(spacing: Spacing.s12) {
            Button("Comprar activo") { buying = true }
                .buttonStyle(PrimaryButtonStyle())
            NavigationLink {
                InvestmentPlansView()
            } label: {
                Text("Aportaciones automáticas")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}

/// Fila de un activo: iniciales, nombre, participaciones, valor y rentabilidad.
struct HoldingRow: View {
    let position: Position
    let owner: String

    var body: some View {
        HStack(spacing: Spacing.s16) {
            Text(position.holding.initials)
                .font(Typography.footnote.weight(.semibold))
                .foregroundStyle(Palette.label)
                .frame(width: 36, height: 36)
                .background(Palette.bgGrouped, in: RoundedRectangle(cornerRadius: Radius.input))
            VStack(alignment: .leading, spacing: 2) {
                Text(position.holding.trimmedName)
                    .font(Typography.headline)
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(position.value.formatted())
                    .font(Typography.headline.monospacedDigit())
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                    .fixedSize()
                if let fraction = position.gainFraction {
                    Text(InvestmentText.percent(fraction))
                        .font(Typography.footnote.weight(.semibold))
                        .foregroundStyle(InvestmentText.gainColor(position.gain))
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        position.quantity > 0
            ? "\(InvestmentText.quantity(position.quantity)) participaciones · \(owner)"
            : "\(position.holding.kind.title) · \(owner)"
    }
}

/// Media rosquilla con una porción por clase de activo.
struct SemicircleDonut: View {
    let slices: [AllocationSlice]
    var lineWidth: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width / 2, proxy.size.height) - lineWidth / 2
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height - 2)
            ZStack {
                arc(from: 0, to: 1, center: center, radius: radius)
                    .stroke(Palette.fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    arc(from: segment.start, to: segment.end, center: center, radius: radius)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                }
            }
        }
    }

    /// Cada porción con un hueco pequeño entre una y otra.
    private var segments: [(start: Double, end: Double, color: Color)] {
        var start = 0.0
        let gap = slices.count > 1 ? 0.006 : 0
        return slices.map { slice in
            defer { start += slice.fraction }
            return (start + gap, max(start + gap, start + slice.fraction - gap), slice.assetClass.color)
        }
    }

    private func arc(from start: Double, to end: Double, center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            path.addArc(center: center, radius: radius,
                        startAngle: .degrees(180 + 180 * start), endAngle: .degrees(180 + 180 * end), clockwise: false)
        }
    }
}

// MARK: - Activo y compra

/// Un activo: su precio, tu posición, la compra y las operaciones.
struct HoldingDetailView: View {
    let holdingId: UUID

    @Environment(InvestmentModel.self) private var investments
    @State private var priceRange: ChartRange = .year
    @State private var editing = false
    @State private var recordingPrice = false
    @State private var selling = false
    @State private var deleting: InvestmentTrade?

    var body: some View {
        Group {
            if let holding = investments.holding(holdingId) {
                content(holding)
            } else {
                EmptyHint(text: "Este activo ya no existe.")
                    .pageLayout()
            }
        }
        .background(Palette.bgGrouped)
    }

    private func content(_ holding: Holding) -> some View {
        let position = investments.position(of: holding)
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                AdaptiveColumns {
                    VStack(alignment: .leading, spacing: Spacing.s24) {
                        priceCard(holding)
                        positionCard(position)
                    }
                } trailing: {
                    VStack(alignment: .leading, spacing: Spacing.s24) {
                        BuyCard(holding: holding)
                        tradesCard(holding, position: position)
                    }
                }
                Text("Esto no es asesoramiento de inversión. La compra se apunta en la app; tu bróker no recibe ninguna orden.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                ErrorText(message: investments.error)
            }
            .pageLayout()
        }
        .navigationTitle(holding.trimmedName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Editar", systemImage: "pencil") { editing = true }
            }
        }
        .sheet(isPresented: $editing) { HoldingFormView(holding: holding) }
        .sheet(isPresented: $recordingPrice) { RecordPriceView(holding: holding) }
        .sheet(isPresented: $selling) { SellView(holding: holding) }
        .confirmationDialog("¿Borrar esta operación?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                if let deleting { Task { await investments.delete(deleting) } }
            }
        } message: {
            Text("No borra el movimiento de la cuenta, si lo había.")
        }
    }

    private func priceCard(_ holding: Holding) -> some View {
        let points = investments.priceHistory(of: holding, range: priceRange).map { PricePoint(day: $0.0, price: $0.1) }
        return VStack(alignment: .leading, spacing: Spacing.s16) {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                Eyebrow([holding.kind.title, holding.trimmedSymbol].compactMap { $0 }.joined(separator: " · "))
                Text(InvestmentText.price(holding.price, currency: holding.currency))
                    .titleFont(.title1)
                    .foregroundStyle(Palette.label)
                Text(holding.priceOn.map { "Precio apuntado el \($0.longTitle)" } ?? "Aún no has apuntado ningún precio")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
            }
            if points.count >= 2 {
                CapsuleSegmented("Periodo", selection: $priceRange, options: ChartRange.price) { $0.title }
                Chart(points) { point in
                    LineMark(x: .value("Día", point.day.date()), y: .value("Precio", point.price))
                        .foregroundStyle(Palette.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Día", point.day.date()), y: .value("Precio", point.price))
                        .foregroundStyle(Palette.accent)
                        .symbolSize(20)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartHeight(160)
                .accessibilityLabel("Gráfico del precio")
            }
            if let range = investments.yearRange(of: holding) {
                HStack {
                    figure("Mín. 1 año", InvestmentText.price(range.lowerBound, currency: holding.currency))
                    figure("Máx. 1 año", InvestmentText.price(range.upperBound, currency: holding.currency))
                    figure("Comisión", InvestmentText.rate(holding.feeRate))
                }
            }
            Button("Apuntar precio") { recordingPrice = true }
                .buttonStyle(SecondaryButtonStyle())
        }
        .card()
    }

    private func positionCard(_ position: Position) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text("Tu posición")
                .titleFont(.title2)
                .foregroundStyle(Palette.label)
            if position.quantity > 0 {
                Grid(alignment: .leading, horizontalSpacing: Spacing.s16, verticalSpacing: Spacing.s16) {
                    GridRow {
                        figure("Participaciones", InvestmentText.quantity(position.quantity))
                        figure("Precio medio", InvestmentText.price(position.averagePrice, currency: position.holding.currency))
                    }
                    GridRow {
                        figure("Valor", position.value.formatted())
                        figure("Rentabilidad", [InvestmentText.signed(position.gain),
                                                position.gainFraction.map(InvestmentText.percent)]
                            .compactMap { $0 }.joined(separator: " · "),
                               color: InvestmentText.gainColor(position.gain))
                    }
                }
            } else {
                EmptyHint(text: "Todavía no tienes participaciones. Apunta tu primera compra.")
            }
            if position.realized.minor != 0 {
                Text("Ganancia ya hecha con ventas: \(InvestmentText.signed(position.realized))")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
            }
        }
        .card()
    }

    private func tradesCard(_ holding: Holding, position: Position) -> some View {
        let list = investments.trades(of: holding)
        return VStack(alignment: .leading, spacing: Spacing.s16) {
            HStack {
                Text("Operaciones")
                    .titleFont(.title2)
                    .foregroundStyle(Palette.label)
                Spacer()
                if position.quantity > 0 {
                    Button("Vender") { selling = true }
                        .font(Typography.subheadlineEmphasis)
                }
            }
            if list.isEmpty { EmptyHint(text: "Sin compras ni ventas todavía.") }
            ForEach(list) { trade in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(trade.side.title) · \(InvestmentText.quantity(trade.quantity)) a \(InvestmentText.price(trade.price, currency: holding.currency))")
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.label)
                            .lineLimit(1)
                        Text(trade.fee.minor > 0 ? "\(trade.tradedOn.shortText) · comisión \(trade.fee.formatted())" : trade.tradedOn.shortText)
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.labelSecondary)
                    }
                    .layoutPriority(1)
                    Spacer()
                    Text(trade.cashImpact.formatted())
                        .font(Typography.subheadlineEmphasis.monospacedDigit())
                        .foregroundStyle(trade.side == .sell ? Palette.positiveText : Palette.label)
                        .fixedSize()
                    Button("Borrar", systemImage: "trash") { deleting = trade }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.labelSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private func figure(_ title: String, _ value: String, color: Color = Palette.label) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
            Text(value)
                .font(Typography.headline.monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct PricePoint: Identifiable {
    var day: CalendarDay
    var price: Decimal
    var id: CalendarDay { day }
}

/// "Comprar activo": por importe o por participaciones, con la comisión y el total.
/// Si se elige una cuenta, también apunta el gasto en ella; y puede crear un plan mensual.
struct BuyCard: View {
    let holding: Holding

    enum Mode: String, CaseIterable { case amount, quantity }

    @Environment(InvestmentModel.self) private var investments
    @Environment(FinanceModel.self) private var finance
    @State private var mode: Mode = .amount
    @State private var text = ""
    @State private var accountId: UUID?
    @State private var tradedOn = Date()
    @State private var repeatMonthly = false
    @State private var error: String?
    @State private var done: String?
    @State private var isWorking = false

    private var quote: BuyQuote? {
        switch mode {
        case .amount:
            Money(parsing: text).flatMap { BuyQuote.byAmount($0, price: holding.price, feeRate: holding.feeRate) }
        case .quantity:
            Decimal(parsing: text).flatMap { BuyQuote.byQuantity($0, price: holding.price, feeRate: holding.feeRate) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text("Comprar")
                .titleFont(.title2)
                .foregroundStyle(Palette.label)
            if holding.price <= 0 {
                EmptyHint(text: "Apunta primero el precio de hoy para calcular la compra.")
            } else {
                CapsuleSegmented("Comprar por", selection: $mode, options: Mode.allCases) {
                    $0 == .amount ? "Importe" : "Participaciones"
                }
                LabeledField(label: mode == .amount ? "Importe" : "Participaciones") {
                    TextField(mode == .amount ? "500,00" : "10", text: $text)
                        .decimalInput()
                }
                if let quote {
                    VStack(spacing: Spacing.s8) {
                        QuoteLine(title: "Participaciones", text: InvestmentText.quantity(quote.quantity))
                        QuoteLine(title: "Comisión (\(InvestmentText.rate(holding.feeRate)))", text: quote.fee.formatted())
                        QuoteLine(title: "Total", text: quote.total.formatted(), highlight: true)
                    }
                }
                Picker("Desde", selection: $accountId) {
                    Text("No apuntar en ninguna cuenta").tag(UUID?.none)
                    ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                }
                DatePicker("Fecha", selection: $tradedOn, in: ...Date(), displayedComponents: .date)
                Toggle("Repetir cada mes", isOn: $repeatMonthly)
                Button(quote.map { "Comprar \($0.total.formatted())" } ?? "Comprar") { Task { await buy() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(quote == nil || isWorking)
                if let done {
                    Text(done)
                        .font(Typography.subheadline)
                        .foregroundStyle(Palette.positiveText)
                }
                ErrorText(message: error)
            }
        }
        .card()
        .onAppear { if accountId == nil { accountId = holding.accountId } }
    }

    private func buy() async {
        guard let quote else { return }
        error = nil
        done = nil
        isWorking = true
        defer { isWorking = false }
        let day = CalendarDay(tradedOn)
        guard await investments.add(quote.trade(for: holding, price: holding.price, on: day)) else {
            error = investments.error
            return
        }
        if let accountId {
            let savings = finance.categories.first { $0.kind == .expense && $0.budgetGroup == .savings }
            let draft = MovementDraft(accountId: accountId, categoryId: savings?.id, bookedOn: day,
                                      amount: -quote.total, description: "Compra de \(holding.trimmedName)")
            if !(await finance.add(draft)) { error = finance.error }
        }
        if repeatMonthly {
            let plan = InvestmentPlan(householdId: holding.householdId, holdingId: holding.id, accountId: accountId,
                                      amount: quote.amount, startsOn: day.adding(months: 1))
            if !(await investments.save(plan)) { error = investments.error }
        }
        text = ""
        repeatMonthly = false
        done = "Compra apuntada: \(InvestmentText.quantity(quote.quantity)) participaciones."
    }
}

/// Desde la cartera: elegir qué activo comprar.
struct BuyPickerView: View {
    @Environment(InvestmentModel.self) private var investments
    @Environment(\.dismiss) private var dismiss
    @State private var holdingId: UUID?
    @State private var addingHolding = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s16) {
                    Picker("Activo", selection: $holdingId) {
                        Text("Elige uno").tag(UUID?.none)
                        ForEach(investments.activeHoldings) { Text($0.trimmedName).tag(Optional($0.id)) }
                    }
                    .card()
                    if let holdingId, let holding = investments.holding(holdingId) {
                        BuyCard(holding: holding).id(holding.id)
                    }
                    Button("Añadir otro activo") { addingHolding = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .pageLayout()
            }
            .background(Palette.bgGrouped)
            .navigationTitle("Comprar activo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
            .sheet(isPresented: $addingHolding) { HoldingFormView(holding: nil) }
        }
        .frame(minWidth: 420, minHeight: 560)
        .onAppear { holdingId = holdingId ?? investments.activeHoldings.first?.id }
    }
}

// MARK: - Formularios

/// Crear o editar un activo.
struct HoldingFormView: View {
    let holding: Holding?

    @Environment(InvestmentModel.self) private var investments
    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = ""
    @State private var kind: InvestmentKind = .fund
    @State private var assetClass: AssetClass = .equity
    @State private var ownerId: UUID?
    @State private var accountId: UUID?
    @State private var price = ""
    @State private var feeRate = ""
    @State private var note = ""
    @State private var error: String?
    @State private var isWorking = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre, p. ej. Fondo indexado mundial", text: $name)
                    TextField("Ticker o ISIN (opcional)", text: $symbol)
                        .plainIdentifierInput()
                    Picker("Tipo", selection: $kind) {
                        ForEach(InvestmentKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .onChange(of: kind) { _, new in if holding == nil { assetClass = new.defaultAssetClass } }
                    Picker("Clase", selection: $assetClass) {
                        ForEach(AssetClass.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    TextField("Precio actual por participación", text: $price)
                        .decimalInput()
                    TextField("Comisión de compra en %, p. ej. 0,2", text: $feeRate)
                        .decimalInput()
                } footer: {
                    Text("El precio lo apuntas tú: búscalo en tu bróker o banco cuando quieras actualizarlo.")
                }
                Section {
                    Picker("De quién es", selection: $ownerId) {
                        Text("Compartido").tag(UUID?.none)
                        ForEach(investments.members) { Text($0.profile.name).tag(Optional($0.profile.id)) }
                    }
                    Picker("Dónde está", selection: $accountId) {
                        Text("Ninguna cuenta").tag(UUID?.none)
                        ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    TextField("Nota (opcional)", text: $note)
                } footer: {
                    Text("Todo el hogar ve las inversiones, como las cuentas.")
                }
                if let holding {
                    Section {
                        Button(holding.isArchived ? "Desarchivar" : "Archivar") { Task { await toggleArchive() } }
                        Button("Borrar activo y sus operaciones", role: .destructive) { confirmingDelete = true }
                    }
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle(holding == nil ? "Nuevo activo" : "Editar activo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }.disabled(isWorking)
                }
            }
            .confirmationDialog("¿Borrar este activo?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Borrar activo", role: .destructive) { Task { await delete() } }
            } message: {
                Text("Se borran también sus precios, operaciones y aportaciones automáticas, para todo el hogar. No se puede deshacer.")
            }
        }
        .frame(minWidth: 380, minHeight: 520)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let holding else { return }
        name = holding.name
        symbol = holding.symbol ?? ""
        kind = holding.kind
        assetClass = holding.assetClass
        ownerId = holding.ownerId
        accountId = holding.accountId
        price = holding.price > 0 ? InvestmentText.plain(holding.price) : ""
        feeRate = holding.feeRate > 0 ? InvestmentText.plain(holding.feeRate) : ""
        note = holding.note ?? ""
    }

    private func save() async {
        let trimmedPrice = price.trimmingCharacters(in: .whitespaces)
        let trimmedFee = feeRate.trimmingCharacters(in: .whitespaces)
        guard let priceValue = trimmedPrice.isEmpty ? 0 : Decimal(parsing: trimmedPrice) else {
            error = "Escribe el precio con números, p. ej. 12,50."
            return
        }
        guard let feeValue = trimmedFee.isEmpty ? 0 : Decimal(parsing: trimmedFee) else {
            error = "Escribe la comisión con números, p. ej. 0,2."
            return
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var item = holding ?? Holding(householdId: investments.household.id, name: name)
        let priceChanged = holding.map { $0.price != priceValue } ?? (priceValue > 0)
        item.name = name
        item.symbol = symbol
        item.kind = kind
        item.assetClass = assetClass
        item.ownerId = ownerId
        item.accountId = accountId
        item.feeRate = feeValue
        item.note = trimmedNote.isEmpty ? nil : trimmedNote
        if holding == nil { item.price = priceValue; item.priceOn = priceValue > 0 ? CalendarDay() : nil }
        if let issue = item.issue { error = issue; return }
        isWorking = true
        defer { isWorking = false }
        guard let saved = await investments.save(item) else { error = investments.error; return }
        // Un precio nuevo también queda en el histórico, para el gráfico.
        if priceChanged, priceValue > 0 {
            await investments.recordPrice(priceValue, on: CalendarDay(), for: saved)
        }
        dismiss()
    }

    private func toggleArchive() async {
        guard var item = holding else { return }
        item.archivedAt = item.isArchived ? nil : Date()
        if await investments.save(item) != nil { dismiss() } else { error = investments.error }
    }

    private func delete() async {
        guard let holding else { return }
        if await investments.delete(holding) { dismiss() } else { error = investments.error }
    }
}

/// Apuntar el precio de un día.
struct RecordPriceView: View {
    let holding: Holding

    @Environment(InvestmentModel.self) private var investments
    @Environment(\.dismiss) private var dismiss
    @State private var price = ""
    @State private var pricedOn = Date()
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Precio por participación", text: $price)
                        .decimalInput()
                    DatePicker("Fecha", selection: $pricedOn, in: ...Date(), displayedComponents: .date)
                } footer: {
                    Text("Si ya habías apuntado un precio ese día, se sustituye.")
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle("Apuntar precio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }.disabled(isWorking)
                }
            }
        }
        .frame(minWidth: 340, minHeight: 280)
        .onAppear { if holding.price > 0 { price = InvestmentText.plain(holding.price) } }
    }

    private func save() async {
        guard let value = Decimal(parsing: price), value > 0 else {
            error = "Escribe el precio con números, p. ej. 12,50."
            return
        }
        isWorking = true
        defer { isWorking = false }
        if await investments.recordPrice(value, on: CalendarDay(pricedOn), for: holding) { dismiss() } else {
            error = investments.error
        }
    }
}

/// Apuntar una venta.
struct SellView: View {
    let holding: Holding

    @Environment(InvestmentModel.self) private var investments
    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = ""
    @State private var price = ""
    @State private var fee = ""
    @State private var soldOn = Date()
    @State private var accountId: UUID?
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        let held = investments.position(of: holding).quantity
        NavigationStack {
            Form {
                Section {
                    TextField("Participaciones (tienes \(InvestmentText.quantity(held)))", text: $quantity)
                        .decimalInput()
                    TextField("Precio por participación", text: $price)
                        .decimalInput()
                    TextField("Comisión en € (opcional)", text: $fee)
                        .decimalInput()
                    DatePicker("Fecha", selection: $soldOn, in: ...Date(), displayedComponents: .date)
                }
                Section {
                    Picker("Ingresar en", selection: $accountId) {
                        Text("No apuntar en ninguna cuenta").tag(UUID?.none)
                        ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                } footer: {
                    Text("Si eliges una cuenta, se apunta allí lo que recibes.")
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle("Vender")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }.disabled(isWorking)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 380)
        .onAppear {
            price = InvestmentText.plain(holding.price)
            accountId = holding.accountId
        }
    }

    private func save() async {
        guard let amount = Decimal(parsing: quantity), let priceValue = Decimal(parsing: price) else {
            error = "Escribe las participaciones y el precio con números."
            return
        }
        let trimmedFee = fee.trimmingCharacters(in: .whitespaces)
        guard let feeValue = trimmedFee.isEmpty ? Money.zero : Money(parsing: trimmedFee) else {
            error = "Escribe la comisión con números."
            return
        }
        let day = CalendarDay(soldOn)
        let trade = InvestmentTrade(householdId: holding.householdId, holdingId: holding.id, tradedOn: day, side: .sell,
                                    quantity: amount, price: priceValue, fee: feeValue)
        isWorking = true
        defer { isWorking = false }
        guard await investments.add(trade) else { error = investments.error; return }
        if let accountId {
            let draft = MovementDraft(accountId: accountId, bookedOn: day, amount: trade.cashImpact,
                                      description: "Venta de \(holding.trimmedName)")
            if !(await finance.add(draft)) { error = finance.error; return }
        }
        dismiss()
    }
}

// MARK: - Aportaciones automáticas

/// Planes para invertir una cantidad fija cada cierto tiempo, con el calendario del mes.
struct InvestmentPlansView: View {
    @Environment(InvestmentModel.self) private var investments
    @State private var editing: InvestmentPlan?
    @State private var adding = false

    var body: some View {
        let month = MonthKey(investments.day)
        let charges = investments.charges(in: month)
        let counts = investments.planCounts
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    Eyebrow("Aportaciones automáticas")
                    Text(investments.monthlyPlanned.formatted())
                        .titleFont(.largeTitle)
                        .foregroundStyle(Palette.label)
                    Text(summary(counts))
                        .font(Typography.subheadline)
                        .foregroundStyle(Palette.labelSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                AdaptiveColumns {
                    calendarCard(month: month, charges: charges)
                } trailing: {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        ForEach(investments.livePlans) { plan in
                            PlanCard(plan: plan) { editing = plan }
                        }
                        Button("Nuevo plan") { adding = true }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(investments.activeHoldings.isEmpty)
                        if investments.activeHoldings.isEmpty {
                            EmptyHint(text: "Añade antes un activo en la cartera.")
                        }
                    }
                }

                Text("Un plan no compra nada solo: te avisa el día que toca y tú confirmas la compra en la app.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                ErrorText(message: investments.error)
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Aportaciones")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nuevo plan", systemImage: "plus") { adding = true }
                    .disabled(investments.activeHoldings.isEmpty)
            }
        }
        .refreshable { await investments.load() }
        .sheet(isPresented: $adding) { PlanFormView(plan: nil) }
        .sheet(item: $editing) { PlanFormView(plan: $0) }
    }

    private func summary(_ counts: (active: Int, paused: Int)) -> String {
        let active = counts.active == 1 ? "1 plan activo" : "\(counts.active) planes activos"
        let paused = counts.paused == 0 ? "" : " y \(counts.paused) en pausa"
        return "al mes en \(active)\(paused)"
    }

    private func calendarCard(month: MonthKey, charges: [PlanCharge]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text(month.title)
                .titleFont(.title2)
                .foregroundStyle(Palette.label)
            if charges.isEmpty {
                EmptyHint(text: "Este mes no hay aportaciones.")
            } else {
                Chart(charges) { charge in
                    BarMark(x: .value("Día", charge.due.date(), unit: .day), y: .value("Importe", charge.plan.amount.decimal))
                        .foregroundStyle(charge.due < investments.day ? Palette.labelTertiary : Palette.accent)
                        .cornerRadius(4)
                }
                .chartXScale(domain: month.firstDay.date()...month.adding(months: 1).firstDay.date())
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.day())
                    }
                }
                .chartHeight(140)
                .accessibilityLabel("Calendario de aportaciones del mes")
                ForEach(charges) { charge in
                    HStack {
                        Text(charge.due.longTitle)
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.label)
                        Spacer()
                        Text(investments.holding(charge.plan.holdingId)?.trimmedName ?? "")
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.labelSecondary)
                            .lineLimit(1)
                        Text(charge.plan.amount.formatted())
                            .font(Typography.subheadlineEmphasis.monospacedDigit())
                            .foregroundStyle(Palette.label)
                            .fixedSize()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card()
    }
}

/// Tarjeta de un plan con su interruptor.
struct PlanCard: View {
    let plan: InvestmentPlan
    let edit: () -> Void

    @Environment(InvestmentModel.self) private var investments
    @Environment(FinanceModel.self) private var finance

    var body: some View {
        let holding = investments.holding(plan.holdingId)
        let position = holding.map(investments.position(of:))
        VStack(alignment: .leading, spacing: Spacing.s16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(holding?.trimmedName ?? "Activo")
                        .font(Typography.headline)
                        .foregroundStyle(Palette.label)
                    Text(subtitle(holding))
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("Activo", isOn: Binding(get: { !plan.isPaused },
                                               set: { on in Task { await investments.setPaused(!on, plan) } }))
                    .labelsHidden()
            }
            Grid(alignment: .leading, horizontalSpacing: Spacing.s16, verticalSpacing: Spacing.s12) {
                GridRow {
                    figure("Aportación", "\(plan.amount.formatted()) · \(plan.recurrence.title.lowercased())")
                    figure(plan.isPaused ? "Estado" : "Próxima",
                           plan.isPaused ? "En pausa" : plan.nextDue(onOrAfter: investments.day)?.longTitle ?? "Terminado")
                }
                GridRow {
                    figure("Invertido hasta hoy", plan.invested(trades: investments.trades, through: investments.day).formatted())
                    figure("Rentabilidad", position?.gainFraction.map(InvestmentText.percent) ?? "—",
                           color: position.map { InvestmentText.gainColor($0.gain) } ?? Palette.label)
                }
            }
            Button("Editar plan", action: edit)
                .font(Typography.subheadlineEmphasis)
        }
        .card()
        .opacity(plan.isPaused ? 0.75 : 1)
    }

    private func subtitle(_ holding: Holding?) -> String {
        let who = investments.ownerName(holding?.ownerId)
        guard let id = plan.accountId, let account = finance.account(id) else { return who }
        return "\(who) · desde \(account.name)"
    }

    private func figure(_ title: String, _ value: String, color: Color = Palette.label) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
            Text(value)
                .font(Typography.subheadlineEmphasis)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Crear o editar un plan de aportación.
struct PlanFormView: View {
    let plan: InvestmentPlan?

    @Environment(InvestmentModel.self) private var investments
    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var holdingId: UUID?
    @State private var amount = ""
    @State private var recurrence: Recurrence = .monthly
    @State private var accountId: UUID?
    @State private var startsOn = Date()
    @State private var expectedReturn = "5"
    @State private var remindDaysBefore: Int? = 1
    @State private var error: String?
    @State private var isWorking = false
    @State private var confirmingDelete = false

    private var draft: InvestmentPlan? {
        guard let holdingId, let money = Money(parsing: amount), let rate = Decimal(parsing: expectedReturn) else { return nil }
        var item = plan ?? InvestmentPlan(householdId: investments.household.id, holdingId: holdingId, amount: money,
                                          startsOn: CalendarDay(startsOn))
        item.amount = money
        item.recurrence = recurrence
        item.accountId = accountId
        item.startsOn = CalendarDay(startsOn)
        item.expectedAnnualReturn = rate
        item.remindDaysBefore = remindDaysBefore
        return item
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Activo", selection: $holdingId) {
                        if holdingId == nil { Text("Elige uno").tag(UUID?.none) }
                        ForEach(investments.activeHoldings) { Text($0.trimmedName).tag(Optional($0.id)) }
                    }
                    .disabled(plan != nil)
                    TextField("Importe, p. ej. 150", text: $amount)
                        .decimalInput()
                    Picker("Cada", selection: $recurrence) {
                        ForEach(Recurrence.common, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Sale de", selection: $accountId) {
                        Text("Ninguna cuenta").tag(UUID?.none)
                        ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    DatePicker("Primera aportación", selection: $startsOn, displayedComponents: .date)
                }
                Section {
                    Picker("Aviso", selection: $remindDaysBefore) {
                        Text("Sin aviso").tag(Int?.none)
                        Text("El mismo día").tag(Optional(0))
                        Text("1 día antes").tag(Optional(1))
                        Text("3 días antes").tag(Optional(3))
                    }
                    TextField("Rentabilidad anual supuesta en %", text: $expectedReturn)
                        .decimalInput()
                } footer: {
                    if let draft, draft.issue == nil {
                        Text("Si rinde un \(expectedReturn) % al año, lo aportado en 1 año valdría unos \(draft.projectedValue(months: 12).formatted()) y en 5 años unos \(draft.projectedValue(months: 60).formatted()). Es una estimación, no una promesa.")
                    } else {
                        Text("La rentabilidad supuesta sólo sirve para la proyección.")
                    }
                }
                if plan != nil {
                    Section {
                        Button("Borrar plan", role: .destructive) { confirmingDelete = true }
                    } footer: {
                        Text("Las compras que ya apuntaste no se borran.")
                    }
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle(plan == nil ? "Nuevo plan" : "Editar plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(plan == nil ? "Crear" : "Guardar") { Task { await save() } }.disabled(isWorking)
                }
            }
            .confirmationDialog("¿Borrar este plan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Borrar plan", role: .destructive) { Task { await delete() } }
            }
        }
        .frame(minWidth: 380, minHeight: 520)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let plan else {
            holdingId = investments.activeHoldings.first?.id
            return
        }
        holdingId = plan.holdingId
        amount = plan.amount.plainText
        recurrence = plan.recurrence
        accountId = plan.accountId
        startsOn = plan.startsOn.date()
        expectedReturn = InvestmentText.plain(plan.expectedAnnualReturn)
        remindDaysBefore = plan.remindDaysBefore
    }

    private func save() async {
        guard holdingId != nil else { error = "Elige un activo."; return }
        guard let item = draft else { error = "Escribe el importe y la rentabilidad con números."; return }
        if let issue = item.issue { error = issue; return }
        isWorking = true
        defer { isWorking = false }
        if await investments.save(item) { dismiss() } else { error = investments.error }
    }

    private func delete() async {
        guard let plan else { return }
        if await investments.delete(plan) { dismiss() } else { error = investments.error }
    }
}

/// Una línea del cálculo de la compra: título a la izquierda y valor a la derecha.
private struct QuoteLine: View {
    let title: String
    let text: String
    var highlight = false

    var body: some View {
        HStack {
            Text(title)
                .font(highlight ? Typography.headline : Typography.subheadline)
                .foregroundStyle(highlight ? Palette.label : Palette.labelSecondary)
            Spacer()
            Text(text)
                .font(highlight ? Typography.headline.monospacedDigit() : Typography.subheadlineEmphasis.monospacedDigit())
                .foregroundStyle(Palette.label)
        }
        .accessibilityElement(children: .combine)
    }
}
