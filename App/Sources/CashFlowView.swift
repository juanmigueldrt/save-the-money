import SwiftUI
import STMCore
import STMUI

// MARK: Flujo de caja

/// Flujo de caja del mes como diagrama de Sankey: ingresos → grupos → categorías.
struct CashFlowView: View {
    @Environment(BudgetModel.self) private var budgets
    @Environment(FinanceModel.self) private var finance

    var body: some View {
        let report = budgets.report(categories: finance.categories)
        let flow = CashFlow(report: report)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                PeriodSwitcher()
                VStack(alignment: .leading, spacing: Spacing.s16) {
                    HStack {
                        SummaryLine(title: "Entra", amount: report.income)
                        Divider().frame(height: 20)
                        SummaryLine(title: "Sale", amount: report.totalSpent)
                    }
                    if flow.isEmpty {
                        EmptyHint(text: budgets.isLoading ? "Cargando…" : "No hay movimientos en este periodo. Cuando apuntes o importes ingresos y gastos, aquí verás a dónde va tu dinero.")
                    } else {
                        SankeyDiagram(flow: flow)
                            .chartHeight(max(320, CGFloat(flow.nodes.filter { $0.column == 2 }.count) * 34))
                    }
                }
                .card()
                ErrorText(message: budgets.error)
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Flujo de caja")
        .refreshable { await budgets.load() }
    }
}

/// Dibuja el Sankey con Canvas: nodos como barras y enlaces como bandas curvas.
struct SankeyDiagram: View {
    let flow: CashFlow

    var body: some View {
        GeometryReader { proxy in
            // Etiquetas a los lados; en iPhone se estrechan para dejar sitio al diagrama.
            let labelWidth = min(96, proxy.size.width * 0.26)
            let inner = max(proxy.size.width - labelWidth * 2, 80)
            let layout = SankeyLayout(flow: flow, width: inner, height: proxy.size.height, nodeWidth: 10, gap: 10)
            let colors = Dictionary(uniqueKeysWithValues: flow.nodes.map { ($0.id, color(for: $0.role)) })
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    context.translateBy(x: labelWidth, y: 0)
                    for band in layout.bands {
                        context.fill(path(for: band), with: .color((colors[band.to] ?? Palette.labelTertiary).opacity(0.28)))
                    }
                    for node in flow.nodes {
                        guard let rect = layout.nodes[node.id] else { continue }
                        context.fill(Path(roundedRect: CGRect(x: rect.x, y: rect.y, width: rect.width, height: max(rect.height, 1)),
                                          cornerRadius: 2),
                                     with: .color(colors[node.id] ?? Palette.label))
                    }
                }
                ForEach(flow.nodes) { node in
                    if let rect = layout.nodes[node.id] {
                        label(for: node)
                            .frame(width: labelWidth - 8, alignment: node.column == 0 ? .trailing : .leading)
                            .background(node.column == 1 ? Palette.bgGrouped2.opacity(0.85) : .clear)
                            .position(x: labelX(node: node, rect: rect, inner: inner, labelWidth: labelWidth), y: rect.midY)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func labelX(node: CashFlow.Node, rect: SankeyLayout.Rect, inner: CGFloat, labelWidth: CGFloat) -> CGFloat {
        switch node.column {
        case 0: return labelWidth / 2 - 4
        case 1: return labelWidth + rect.x + rect.width + labelWidth / 2
        default: return labelWidth + inner + labelWidth / 2 + 4
        }
    }

    private func label(for node: CashFlow.Node) -> some View {
        VStack(alignment: node.column == 0 ? .trailing : .leading, spacing: 0) {
            Text(node.title)
                .font(Typography.footnote.weight(.medium))
                .foregroundStyle(Palette.label)
                .lineLimit(1)
            Text(Money(minor: Int(node.value.rounded())).formatted())
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
                .lineLimit(1)
        }
        .minimumScaleFactor(0.8)
    }

    private func path(for band: SankeyLayout.Band) -> Path {
        let midX = (band.sourceX + band.targetX) / 2
        var path = Path()
        path.move(to: CGPoint(x: band.sourceX, y: band.sourceTop))
        path.addCurve(to: CGPoint(x: band.targetX, y: band.targetTop),
                      control1: CGPoint(x: midX, y: band.sourceTop),
                      control2: CGPoint(x: midX, y: band.targetTop))
        path.addLine(to: CGPoint(x: band.targetX, y: band.targetTop + band.thickness))
        path.addCurve(to: CGPoint(x: band.sourceX, y: band.sourceTop + band.thickness),
                      control1: CGPoint(x: midX, y: band.targetTop + band.thickness),
                      control2: CGPoint(x: midX, y: band.sourceTop + band.thickness))
        path.closeSubpath()
        return path
    }

    private func color(for role: CashFlow.Role) -> Color {
        switch role {
        case .income: Palette.accent
        case .fromBalance: Palette.negative
        case .group(let group): group.color
        case .category(let group): group?.color ?? Palette.labelTertiary
        case .uncategorized: Palette.labelTertiary
        case .unspent: Palette.separator
        }
    }

    private var accessibilitySummary: String {
        flow.nodes.filter { $0.column == 1 }
            .map { "\($0.title): \(Money(minor: Int($0.value.rounded())).formatted())" }
            .joined(separator: ", ")
    }
}
