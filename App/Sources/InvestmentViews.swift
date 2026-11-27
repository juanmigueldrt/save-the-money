import SwiftUI
import Charts
import STMCore
import STMUI

// MARK: - Formatos

enum InvestmentText {
    private static let spain = AppRegion.locale

    /// "12,5034 €": precio por participación, de 2 a 4 decimales.
    static func price(_ value: Decimal, currency: String = AppRegion.currency) -> String {
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
                        EmptyHint(text: investments.isLoading ? "Cargando…" : "Añade un fondo, un ETF o una acción y apunta tus compras. Los precios los apuntas tú cuando quieras; la app no se conecta a ningún bróker.")
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
