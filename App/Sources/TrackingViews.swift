import SwiftUI
import Charts
import STMCore
import STMUI

// MARK: - Patrimonio neto

/// Lo que tiene el hogar menos lo que debe, y cómo ha ido en los últimos 12 meses.
struct NetWorthView: View {
    @Environment(FinanceModel.self) private var finance
    @Environment(TrackingModel.self) private var tracking

    var body: some View {
        let now = NetWorth.current(accounts: finance.accounts, balances: finance.balances)
        let history = tracking.history(accounts: finance.accounts)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                VStack(alignment: .leading, spacing: Spacing.s16) {
                    Eyebrow("Patrimonio neto")
                    Text(now.net.formatted())
                        .titleFont(.largeTitle)
                        .foregroundStyle(now.net.isNegative ? Palette.negativeText : Palette.label)
                        .contentTransition(.numericText())
                    HStack(spacing: Spacing.s16) {
                        figure("Lo que tienes", now.assets)
                        figure("Lo que debes", now.liabilities)
                    }
                    if let change = change(in: history) {
                        Text(change)
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.labelSecondary)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: Spacing.s16) {
                    Text("Últimos 12 meses")
                        .titleFont(.title2)
                        .foregroundStyle(Palette.label)
                    if finance.accounts.isEmpty {
                        EmptyHint(text: "Añade tus cuentas para ver cómo evoluciona tu patrimonio.")
                    } else {
                        Chart(history) { point in
                            AreaMark(x: .value("Mes", point.month.firstDay.date(), unit: .month),
                                     y: .value("Patrimonio", point.net.decimal))
                                .foregroundStyle(Palette.accent.opacity(0.12))
                            LineMark(x: .value("Mes", point.month.firstDay.date(), unit: .month),
                                     y: .value("Patrimonio", point.net.decimal))
                                .foregroundStyle(Palette.accent)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month, count: 3)) { _ in
                                AxisValueLabel(format: .dateTime.month(.abbreviated))
                            }
                        }
                        .chartHeight(200)
                        .accessibilityLabel("Gráfico del patrimonio neto de los últimos 12 meses")
                    }
                }
                .card()

                accountsCard(title: "Lo que tienes", accounts: finance.activeAccounts.filter { !finance.balance(of: $0).isNegative })
                accountsCard(title: "Lo que debes", accounts: finance.activeAccounts.filter { finance.balance(of: $0).isNegative })

                Text("Se calcula con el saldo inicial de cada cuenta y sus movimientos. Las cuentas archivadas no cuentan.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                ErrorText(message: tracking.error)
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Patrimonio")
        .task(id: finance.recent) { await tracking.loadHistory() }
        .refreshable {
            await finance.load()
            await tracking.loadHistory()
        }
    }

    private func figure(_ title: String, _ amount: Money) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            Text(title)
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
            Text(amount.formatted())
                .font(Typography.headline)
                .foregroundStyle(Palette.label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func change(in history: [NetWorthPoint]) -> String? {
        guard history.count >= 2 else { return nil }
        let previous = history[history.count - 2], last = history[history.count - 1]
        let diff = last.net - previous.net
        guard diff.minor != 0 else { return "Igual que el mes pasado." }
        return (diff.isNegative ? "Baja " : "Sube ") + Money(minor: abs(diff.minor)).formatted() + " desde el mes pasado."
    }

    @ViewBuilder
    private func accountsCard(title: String, accounts: [Account]) -> some View {
        if !accounts.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s16) {
                Text(title)
                    .titleFont(.title2)
                    .foregroundStyle(Palette.label)
                ForEach(accounts) { account in
                    AccountRow(account: account, balance: finance.balance(of: account))
                }
            }
            .card()
        }
    }
}

// MARK: - Score crediticio

struct CreditScoreView: View {
    @Environment(TrackingModel.self) private var tracking
    @State private var adding = false
    @State private var deleting: CreditScore?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                if let latest = tracking.latestScore {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Eyebrow("Tu score crediticio")
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                            Text("\(latest.score)")
                                .titleFont(.largeTitle)
                                .foregroundStyle(Palette.label)
                            Text("de \(latest.maxScore)")
                                .font(Typography.subheadline)
                                .foregroundStyle(Palette.labelSecondary)
                            Spacer()
                            Text(latest.rating.title)
                                .font(Typography.subheadlineEmphasis)
                                .foregroundStyle(Palette.onAccent)
                                .padding(.horizontal, Spacing.s16)
                                .padding(.vertical, Spacing.s8)
                                .background(Palette.accent, in: Capsule())
                        }
                        ProgressBar(fraction: latest.fraction)
                        Text([latest.trimmedProvider, latest.recordedOn.longTitle + " de " + String(latest.recordedOn.year)]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.labelSecondary)
                    }
                    .card()
                    .accessibilityElement(children: .combine)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Eyebrow("Tu score crediticio")
                        Text("Apunta el score que te da tu banco o tu proveedor para ver cómo evoluciona.")
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.labelSecondary)
                        Button("Apuntar mi score") { adding = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .card()
                }

                if tracking.creditScores.count >= 2 {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text("Evolución")
                            .titleFont(.title2)
                            .foregroundStyle(Palette.label)
                        Chart(tracking.creditScores.reversed()) { item in
                            LineMark(x: .value("Fecha", item.recordedOn.date()), y: .value("Score", item.score))
                                .foregroundStyle(Palette.accent)
                            PointMark(x: .value("Fecha", item.recordedOn.date()), y: .value("Score", item.score))
                                .foregroundStyle(Palette.accent)
                        }
                        .chartHeight(180)
                        .accessibilityLabel("Gráfico de la evolución del score")
                    }
                    .card()
                }

                if !tracking.creditScores.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text("Historial")
                            .titleFont(.title2)
                            .foregroundStyle(Palette.label)
                        ForEach(tracking.creditScores) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: Spacing.s8) {
                                    Text("\(item.score) de \(item.maxScore) · \(item.rating.title)")
                                        .font(Typography.headline)
                                        .foregroundStyle(Palette.label)
                                    Text([item.recordedOn.shortText, item.trimmedProvider, item.note].compactMap { $0 }
                                        .joined(separator: " · "))
                                        .font(Typography.footnote)
                                        .foregroundStyle(Palette.labelSecondary)
                                }
                                Spacer()
                                Button("Borrar", systemImage: "trash") { deleting = item }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Palette.labelSecondary)
                            }
                        }
                    }
                    .card()
                }

                Text("Sólo lo ves tú: no se comparte con el resto del hogar. Los tramos son orientativos.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                ErrorText(message: tracking.error)
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Score crediticio")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Apuntar score", systemImage: "plus") { adding = true }
            }
        }
        .task { await tracking.loadScores() }
        .refreshable { await tracking.loadScores() }
        .sheet(isPresented: $adding) { CreditScoreFormView(last: tracking.latestScore) }
        .confirmationDialog("¿Borrar este score?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                if let deleting { Task { await tracking.delete(deleting) } }
            }
        }
    }
}

struct CreditScoreFormView: View {
    let last: CreditScore?

    @Environment(TrackingModel.self) private var tracking
    @Environment(\.dismiss) private var dismiss
    @State private var score = ""
    @State private var maxScore = 850
    @State private var provider = ""
    @State private var recordedOn = Date()
    @State private var note = ""
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Score, p. ej. 720", text: $score)
                        .numberInput()
                    Picker("Escala", selection: $maxScore) {
                        ForEach([850, 900, 999, 1000, 100], id: \.self) { Text("Sobre \($0)").tag($0) }
                    }
                    TextField("Proveedor (opcional)", text: $provider)
                    DatePicker("Fecha", selection: $recordedOn, in: ...Date(), displayedComponents: .date)
                    TextField("Nota (opcional)", text: $note)
                } footer: {
                    Text("Sólo lo ves tú. No se comparte con el hogar.")
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle("Apuntar score")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }.disabled(isWorking)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
        .onAppear {
            if let last {
                maxScore = last.maxScore
                provider = last.trimmedProvider ?? ""
            }
        }
    }

    private func save() async {
        guard let value = Int(score.trimmingCharacters(in: .whitespaces)) else {
            error = "Escribe el score con números."
            return
        }
        let item = CreditScore(score: value, maxScore: maxScore, provider: provider, recordedOn: CalendarDay(recordedOn),
                               note: note)
        if let issue = item.issue { error = issue; return }
        isWorking = true
        defer { isWorking = false }
        if await tracking.add(item) { dismiss() } else { error = tracking.error }
    }
}

// MARK: - Informes

struct ReportsView: View {
    @Environment(FinanceModel.self) private var finance
    @Environment(TrackingModel.self) private var tracking

    var body: some View {
        @Bindable var tracking = tracking
        let report = tracking.report(categories: finance.categories)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                VStack(alignment: .leading, spacing: Spacing.s16) {
                    CapsuleSegmented("Qué", selection: $tracking.kind, options: SpendingReport.Kind.allCases) { $0.title }
                    HStack {
                        Picker("Periodo", selection: $tracking.period) {
                            ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
                        }
                        Spacer()
                        categoryMenu
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: Spacing.s16) {
                    Eyebrow("\(tracking.kind.title) · \(tracking.period.title.lowercased())")
                    Text(report.total.formatted())
                        .titleFont(.largeTitle)
                        .foregroundStyle(Palette.label)
                        .contentTransition(.numericText())
                    if report.byMonth.count > 1 {
                        Text("Media de \(report.averagePerMonth.formatted()) al mes")
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.labelSecondary)
                        Chart(report.byMonth) { item in
                            BarMark(x: .value("Mes", item.month.firstDay.date(), unit: .month),
                                    y: .value("Importe", item.amount.decimal))
                                .foregroundStyle(Palette.accent)
                                .cornerRadius(4)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month)) { _ in
                                AxisValueLabel(format: .dateTime.month(.narrow))
                            }
                        }
                        .chartHeight(180)
                        .accessibilityLabel("Gráfico por meses")
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: Spacing.s16) {
                    Text("Por categoría")
                        .titleFont(.title2)
                        .foregroundStyle(Palette.label)
                    if report.byCategory.isEmpty {
                        EmptyHint(text: tracking.isLoading ? "Cargando…" : "No hay movimientos en este periodo.")
                    }
                    ForEach(report.byCategory) { row in
                        VStack(alignment: .leading, spacing: Spacing.s8) {
                            HStack {
                                Label(row.title, systemImage: row.icon ?? "tag")
                                    .font(Typography.subheadlineEmphasis)
                                    .foregroundStyle(Palette.label)
                                Spacer()
                                Text(row.amount.formatted())
                                    .font(Typography.subheadlineEmphasis)
                                    .foregroundStyle(Palette.label)
                            }
                            ProgressBar(fraction: row.share)
                            Text("\(Int((row.share * 100).rounded())) % · \(row.count) movimientos")
                                .font(Typography.footnote)
                                .foregroundStyle(Palette.labelSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()

                ErrorText(message: tracking.error)
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Informes")
        .task(id: tracking.period) { await tracking.loadReport() }
        .refreshable { await tracking.loadReport() }
    }

    private var categoryMenu: some View {
        Menu {
            Button("Todas las categorías") { tracking.categoryFilter = [] }
            Divider()
            ForEach(finance.categories(for: tracking.kind == .expense ? .expense : .income)) { category in
                Button {
                    if tracking.categoryFilter.contains(category.id) {
                        tracking.categoryFilter.remove(category.id)
                    } else {
                        tracking.categoryFilter.insert(category.id)
                    }
                } label: {
                    if tracking.categoryFilter.contains(category.id) {
                        Label(category.name, systemImage: "checkmark")
                    } else {
                        Text(category.name)
                    }
                }
            }
        } label: {
            Label(tracking.categoryFilter.isEmpty ? "Todas" : "\(tracking.categoryFilter.count) categorías",
                  systemImage: "line.3.horizontal.decrease.circle")
                .font(Typography.subheadlineEmphasis)
        }
    }
}

// MARK: - Presupuesto flexible

/// Un solo número para todo lo que no son pagos fijos ni ahorro.
struct FlexBudgetCard: View {
    let flex: FlexBudget

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Eyebrow(flex.isOver ? "Gastado de más en lo flexible" : "Te queda para lo flexible")
            Text(Money(minor: abs(flex.remaining.minor)).formatted())
                .titleFont(.largeTitle)
                .foregroundStyle(flex.isOver ? Palette.negativeText : Palette.label)
                .contentTransition(.numericText())
            ProgressBar(fraction: flex.fraction)
            if let perDay = flex.perDay {
                Text("Unos \(perDay.formatted()) al día durante \(flex.daysLeft) días")
                    .font(Typography.subheadline)
                    .foregroundStyle(Palette.labelSecondary)
            }
            Divider()
            SummaryLine(title: "Ingresos previstos", amount: flex.income)
            SummaryLine(title: "Pagos fijos (de Pagos fijos)", amount: flex.fixed)
            SummaryLine(title: "Ahorro previsto", amount: flex.savings)
            SummaryLine(title: "Para lo flexible", amount: flex.flexible, highlight: true)
            SummaryLine(title: "Gastado en lo flexible", amount: flex.flexibleSpent)
            SummaryLine(title: "Gastado en pagos fijos", amount: flex.fixedSpent)
            Text("Lo flexible es todo lo que no son pagos fijos ni ahorro: compra, ocio, restaurantes… Los gastos cuyas categorías usan tus pagos fijos cuentan como fijos.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
        }
        .card()
    }
}
