import SwiftUI
import Charts
import STMCore
import STMUI

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
                EmptyHint(text: investments.isLoading ? "Cargando…" : "Todavía no tienes participaciones. Apunta tu primera compra.")
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
