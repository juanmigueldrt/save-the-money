import SwiftUI
import STMCore
import STMUI

/// Selector de mes compartido por presupuesto y flujo: ‹ Noviembre de 2026 ›.
struct MonthSwitcher: View {
    @Environment(BudgetModel.self) private var budgets

    var body: some View {
        HStack {
            Button("Mes anterior", systemImage: "chevron.left") {
                Task { await budgets.show(budgets.month.adding(months: -1)) }
            }
            .labelStyle(.iconOnly)
            Spacer()
            VStack(spacing: 2) {
                Text(budgets.month.title)
                    .font(Typography.title20)
                    .foregroundStyle(Palette.ink)
                Text("\(budgets.period.lowerBound.shortText) – \(budgets.period.upperBound.shortText)")
                    .font(Typography.small12)
                    .foregroundStyle(Palette.graphite)
            }
            Spacer()
            Button("Mes siguiente", systemImage: "chevron.right") {
                Task { await budgets.show(budgets.month.adding(months: 1)) }
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.ink)
        .card()
    }
}

/// Presupuesto del mes: los tres semicírculos 50/30/20 y los límites por categoría.
struct BudgetView: View {
    @Environment(BudgetModel.self) private var budgets
    @Environment(FinanceModel.self) private var finance
    @State private var editing = false

    var body: some View {
        let report = budgets.report(categories: finance.categories)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                MonthSwitcher()

                if budgets.budget == nil {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text(budgets.proposal == nil
                             ? "Aún no hay presupuesto para este mes. Mientras tanto, se reparten los ingresos reales con 50/30/20."
                             : "Aún no hay presupuesto para este mes. Puedes partir del de \(budgets.proposal!.month.title.lowercased()).")
                            .font(Typography.body14)
                            .foregroundStyle(Palette.graphite)
                        Button("Crear presupuesto") { editing = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .card()
                }

                VStack(alignment: .leading, spacing: Spacing.s16) {
                    HStack(alignment: .top, spacing: Spacing.s16) {
                        ForEach(report.groups, id: \.group) { SemicircleGauge(progress: $0) }
                    }
                    Divider()
                    SummaryLine(title: "Ingresos del mes", amount: report.income)
                    SummaryLine(title: budgets.budget == nil ? "Base del reparto (ingresos reales)" : "Ingresos previstos",
                                amount: report.base)
                    SummaryLine(title: "Gastado", amount: report.totalSpent)
                    SummaryLine(title: report.remaining.isNegative ? "Gastado de más" : "Te queda",
                                amount: report.remaining, highlight: true)
                }
                .card()

                ForEach(BudgetGroup.allCases, id: \.self) { group in
                    let lines = report.lines(in: group)
                    if !lines.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.s16) {
                            Text(group.title)
                                .font(Typography.title20)
                                .foregroundStyle(Palette.ink)
                            ForEach(lines) { CategoryLineRow(line: $0, tint: group.color) }
                        }
                        .card()
                    }
                }

                if report.uncategorized.minor > 0 {
                    VStack(alignment: .leading, spacing: Spacing.s8) {
                        SummaryLine(title: "Gastos sin categoría", amount: report.uncategorized)
                        Text("Ponles categoría en Movimientos para que cuenten en su grupo.")
                            .font(Typography.small12)
                            .foregroundStyle(Palette.graphite)
                    }
                    .card()
                }

                ErrorText(message: budgets.error)
            }
            .padding(Spacing.s16)
        }
        .background(Palette.linen)
        .navigationTitle("Presupuesto")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Editar presupuesto", systemImage: "slider.horizontal.3") { editing = true }
            }
        }
        .refreshable { await budgets.load() }
        .sheet(isPresented: $editing) { BudgetFormView(initial: budgets.draft) }
    }
}

struct SummaryLine: View {
    let title: String
    let amount: Money
    var highlight = false

    var body: some View {
        HStack {
            Text(title)
                .font(highlight ? Typography.body16Medium : Typography.body14)
                .foregroundStyle(highlight ? Palette.ink : Palette.graphite)
            Spacer()
            Text(amount.formatted())
                .font(highlight ? Typography.body16Medium : Typography.body14Medium)
                .foregroundStyle(amount.isNegative && highlight ? Palette.red : Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Una categoría: gastado, límite y barra de progreso.
struct CategoryLineRow: View {
    let line: BudgetReport.CategoryLine
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            HStack {
                Label(line.category.name, systemImage: line.category.icon ?? "tag")
                    .font(Typography.body14Medium)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Group {
                    if let limit = line.limit {
                        Text("\(line.spent.formatted()) de \(limit.formatted())")
                    } else {
                        Text(line.spent.formatted())
                    }
                }
                .font(Typography.body14)
                .foregroundStyle(line.isOver ? Palette.red : Palette.graphite)
            }
            if let fraction = line.fraction {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.linen)
                        Capsule().fill(line.isOver ? Palette.red : tint)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 6)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Crear o editar el presupuesto del mes: ingresos previstos, reparto y límites.
struct BudgetFormView: View {
    let initial: Budget

    @Environment(BudgetModel.self) private var budgets
    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var income = ""
    @State private var needs = 50
    @State private var wants = 30
    @State private var savings = 20
    @State private var limits: [UUID: String] = [:]
    @State private var error: String?
    @State private var isWorking = false

    private var total: Int { needs + wants + savings }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ingresos previstos, p. ej. 2.400,00", text: $income)
                        .decimalInput()
                } footer: {
                    Text("Si lo dejas vacío, el reparto se hace con lo que entre de verdad este mes.")
                }
                Section {
                    Stepper("Necesidades: \(needs) %", value: $needs, in: 0...100, step: 5)
                    Stepper("Deseos: \(wants) %", value: $wants, in: 0...100, step: 5)
                    Stepper("Ahorro: \(savings) %", value: $savings, in: 0...100, step: 5)
                    Button("Volver a 50/30/20") { (needs, wants, savings) = (50, 30, 20) }
                } header: {
                    Text("Reparto")
                } footer: {
                    Text(total == 100 ? "Suma 100 %." : "Ahora suma \(total) %. Tiene que sumar 100 %.")
                        .foregroundStyle(total == 100 ? Palette.graphite : Palette.red)
                }
                ForEach(BudgetGroup.allCases, id: \.self) { group in
                    Section("Límites de \(group.title.lowercased()) (opcional)") {
                        ForEach(finance.categories(for: .expense).filter { $0.budgetGroup == group }) { category in
                            HStack {
                                Text(category.name)
                                Spacer()
                                TextField("Sin límite", text: binding(for: category.id))
                                    .multilineTextAlignment(.trailing)
                                    .decimalInput()
                                    .frame(maxWidth: 140)
                            }
                        }
                    }
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(initial.month.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }.disabled(isWorking || total != 100)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 480)
        .onAppear(perform: fill)
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding { limits[id] ?? "" } set: { limits[id] = $0 }
    }

    private func fill() {
        income = initial.expectedIncome.minor == 0 ? "" : initial.expectedIncome.plainText
        (needs, wants, savings) = (initial.template.needs, initial.template.wants, initial.template.savings)
        limits = initial.limits.mapValues(\.plainText)
    }

    private func save() async {
        let trimmed = income.trimmingCharacters(in: .whitespaces)
        guard let expected = trimmed.isEmpty ? .zero : Money(parsing: trimmed), !expected.isNegative else {
            error = "Los ingresos previstos no son un importe válido."
            return
        }
        var parsed: [UUID: Money] = [:]
        for (id, text) in limits {
            let value = text.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            guard let money = Money(parsing: value), !money.isNegative else {
                let name = finance.category(id)?.name ?? "una categoría"
                error = "El límite de \(name) no es un importe válido."
                return
            }
            if money.minor > 0 { parsed[id] = money }
        }
        guard total == 100 else { error = "El reparto tiene que sumar 100 %."; return }

        var budget = initial
        budget.expectedIncome = expected
        budget.template = BudgetTemplate(needs: needs, wants: wants, savings: savings)
        budget.limits = parsed

        isWorking = true
        defer { isWorking = false }
        if await budgets.save(budget) { dismiss() } else { error = budgets.error }
    }
}

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
                MonthSwitcher()
                VStack(alignment: .leading, spacing: Spacing.s16) {
                    HStack {
                        SummaryLine(title: "Entra", amount: report.income)
                        Divider().frame(height: 20)
                        SummaryLine(title: "Sale", amount: report.totalSpent)
                    }
                    if flow.isEmpty {
                        EmptyHint(text: "No hay movimientos este mes. Cuando apuntes o importes ingresos y gastos, aquí verás a dónde va tu dinero.")
                    } else {
                        SankeyDiagram(flow: flow)
                            .frame(height: max(320, CGFloat(flow.nodes.filter { $0.column == 2 }.count) * 34))
                    }
                }
                .card()
                ErrorText(message: budgets.error)
            }
            .padding(Spacing.s16)
        }
        .background(Palette.linen)
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
                        context.fill(path(for: band), with: .color((colors[band.to] ?? Palette.smoke).opacity(0.28)))
                    }
                    for node in flow.nodes {
                        guard let rect = layout.nodes[node.id] else { continue }
                        context.fill(Path(roundedRect: CGRect(x: rect.x, y: rect.y, width: rect.width, height: max(rect.height, 1)),
                                          cornerRadius: 2),
                                     with: .color(colors[node.id] ?? Palette.ink))
                    }
                }
                ForEach(flow.nodes) { node in
                    if let rect = layout.nodes[node.id] {
                        label(for: node)
                            .frame(width: labelWidth - 8, alignment: node.column == 0 ? .trailing : .leading)
                            .background(node.column == 1 ? Palette.paper.opacity(0.85) : .clear)
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
                .font(Typography.small12.weight(.medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Text(Money(minor: Int(node.value.rounded())).formatted())
                .font(Typography.small12)
                .foregroundStyle(Palette.graphite)
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
        case .income: Palette.ember
        case .fromBalance: Palette.red
        case .group(let group): group.color
        case .category(let group): group?.color ?? Palette.smoke
        case .uncategorized: Palette.smoke
        case .unspent: Palette.stone
        }
    }

    private var accessibilitySummary: String {
        flow.nodes.filter { $0.column == 1 }
            .map { "\($0.title): \(Money(minor: Int($0.value.rounded())).formatted())" }
            .joined(separator: ", ")
    }
}
