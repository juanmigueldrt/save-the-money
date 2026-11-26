import SwiftUI
import STMCore
import STMUI

/// Presupuesto del mes: los tres semicírculos 50/30/20 y los límites por categoría.
struct BudgetView: View {
    enum Mode: String, CaseIterable {
        case template, flexible

        var title: String {
            switch self {
            case .template: "50/30/20"
            case .flexible: "Flexible"
            }
        }
    }

    @Environment(BudgetModel.self) private var budgets
    @Environment(FinanceModel.self) private var finance
    @Environment(PlanningModel.self) private var planning
    @State private var editing = false
    @State private var editingSchedule = false
    @AppStorage("budgetMode") private var mode: Mode = .template

    var body: some View {
        let report = budgets.report(categories: finance.categories)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                PeriodSwitcher()

                if budgets.isCurrentPeriod { SpendTodayCard() }

                CapsuleSegmented("Tipo de presupuesto", selection: $mode, options: Mode.allCases) { $0.title }

                if mode == .flexible {
                    FlexBudgetCard(flex: budgets.flex(categories: finance.categories, series: planning.series))
                }

                if budgets.budget == nil {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text(budgets.proposal == nil
                             ? "Aún no hay presupuesto para este periodo. Mientras tanto, se reparten los ingresos reales con 50/30/20."
                             : "Aún no hay presupuesto para este periodo. Puedes partir del de \(budgets.proposal!.period.title.lowercased()).")
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.labelSecondary)
                        Button("Crear presupuesto") { editing = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .card()
                }

                if mode == .template {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        HStack(alignment: .top, spacing: Spacing.s16) {
                            ForEach(report.groups, id: \.group) { SemicircleGauge(progress: $0) }
                        }
                        Divider()
                        SummaryLine(title: "Ingresos del periodo", amount: report.income)
                        SummaryLine(title: budgets.budget == nil ? "Base del reparto (ingresos reales)" : "Ingresos previstos",
                                    amount: report.base)
                        SummaryLine(title: "Gastado", amount: report.totalSpent)
                        SummaryLine(title: report.remaining.isNegative ? "Gastado de más" : "Te queda",
                                    amount: report.remaining, highlight: true)
                        if budgets.budget != nil {
                            let insights = budgets.insights(categories: finance.categories)
                            Divider()
                            SummaryLine(title: insights.unbudgeted.isNegative ? "Límites por encima de lo previsto" : "Queda por presupuestar",
                                        amount: insights.unbudgeted)
                            if budgets.isCurrentPeriod {
                                SummaryLine(title: "Al ritmo de hoy gastarás", amount: insights.projectedSpent)
                            }
                        }
                    }
                    .card()
                }

                ForEach(BudgetGroup.allCases, id: \.self) { group in
                    let lines = report.lines(in: group)
                    if !lines.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.s16) {
                            Text(group.title)
                                .titleFont(.title2)
                                .foregroundStyle(Palette.label)
                            ForEach(lines) { CategoryLineRow(line: $0, tint: group.color) }
                        }
                        .card()
                    }
                }

                if report.uncategorized.minor > 0 {
                    VStack(alignment: .leading, spacing: Spacing.s8) {
                        SummaryLine(title: "Gastos sin categoría", amount: report.uncategorized)
                        Text("Ponles categoría en Movimientos para que cuenten en su grupo.")
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.labelSecondary)
                    }
                    .card()
                }

                ExtraBudgetsSection()

                ErrorText(message: budgets.error)
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Presupuesto")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Editar presupuesto", systemImage: "slider.horizontal.3") { editing = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Día de cobro", systemImage: "calendar.badge.clock") { editingSchedule = true }
            }
        }
        .refreshable { await budgets.load() }
        .sheet(isPresented: $editing) { BudgetFormView(initial: budgets.draft) }
        .sheet(isPresented: $editingSchedule) { PayScheduleView() }
    }
}

struct SummaryLine: View {
    let title: String
    let amount: Money
    var highlight = false

    var body: some View {
        HStack {
            Text(title)
                .font(highlight ? Typography.headline : Typography.subheadline)
                .foregroundStyle(highlight ? Palette.label : Palette.labelSecondary)
            Spacer()
            Text(amount.formatted())
                .font(highlight ? Typography.headline : Typography.subheadlineEmphasis)
                .foregroundStyle(amount.isNegative && highlight ? Palette.negativeText : Palette.label)
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
                    .font(Typography.subheadlineEmphasis)
                    .foregroundStyle(Palette.label)
                Spacer()
                Group {
                    if let available = line.available {
                        Text("\(line.spent.formatted()) de \(available.formatted())")
                    } else {
                        Text(line.spent.formatted())
                    }
                }
                .font(Typography.subheadline)
                .foregroundStyle(line.isOver ? Palette.negativeText : Palette.labelSecondary)
            }
            if let fraction = line.fraction {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.bgGrouped)
                        Capsule().fill(line.isOver ? Palette.negative : tint)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 6)
            }
            if line.carried.minor != 0 {
                Text(line.carried.isNegative
                     ? "Incluye \(Money(minor: -line.carried.minor).formatted()) de menos del periodo anterior"
                     : "Incluye \(line.carried.formatted()) que sobró del periodo anterior")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
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
    @State private var carryOver = false
    @State private var warnPercent = 80
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
                        .foregroundStyle(total == 100 ? Palette.labelSecondary : Palette.negativeText)
                }
                Section {
                    Toggle("Pasar lo que sobre al siguiente periodo", isOn: $carryOver)
                    Stepper("Avisarme al \(warnPercent) % del límite", value: $warnPercent, in: 50...100, step: 5)
                } header: {
                    Text("Arrastre y avisos")
                } footer: {
                    Text("Con el arrastre, lo que sobre en una categoría se suma a su límite del siguiente periodo, y lo que te pases se resta.")
                }
                Section {
                    Button("Proponer límites (media de 3 periodos)") { suggest() }
                    Button("Vaciar límites", role: .destructive) { limits = [:] }
                        .disabled(limits.values.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                } footer: {
                    Text("La propuesta usa lo que gastaste de media en cada categoría en los 3 periodos anteriores. Puedes cambiarla antes de guardar.")
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
            .brandBackground()
            .navigationTitle(initial.period.title)
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
        carryOver = initial.carryOver
        warnPercent = initial.warnPercent
    }

    private func suggest() {
        let suggested = budgets.suggestedLimits(categories: finance.categories)
        guard !suggested.isEmpty else {
            error = "Aún no hay gastos en los periodos anteriores para proponer límites."
            return
        }
        error = nil
        limits = suggested.mapValues(\.plainText)
    }

    private func save() async {
        let trimmed = income.trimmingCharacters(in: .whitespaces)
        guard let expected = trimmed.isEmpty ? .zero : Money(entered: trimmed), !expected.isNegative else {
            error = "Los ingresos previstos no son un importe válido."
            return
        }
        var parsed: [UUID: Money] = [:]
        for (id, text) in limits {
            let value = text.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            guard let money = Money(entered: value), !money.isNegative else {
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
        budget.carryOver = carryOver
        budget.warnPercent = warnPercent

        isWorking = true
        defer { isWorking = false }
        if await budgets.save(budget) { dismiss() } else { error = budgets.error }
    }
}
