import SwiftUI
import Charts
import STMCore
import STMUI

// MARK: - Informes

struct ReportsView: View {
    @Environment(FinanceModel.self) private var finance
    @Environment(TrackingModel.self) private var tracking
    @State private var mode: ReportMode = .incomeAndExpenses

    enum ReportMode: String, CaseIterable, Hashable {
        case incomeAndExpenses, byCategory, byTag, byPayee

        var title: String {
            switch self {
            case .incomeAndExpenses: String(localized: "Ingresos y gastos")
            case .byCategory: String(localized: "Por categoría")
            case .byTag: String(localized: "Por etiqueta")
            case .byPayee: String(localized: "Por beneficiario")
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                CapsuleSegmented(String(localized: "Informe"), selection: $mode, options: ReportMode.allCases) { $0.title }
                switch mode {
                case .incomeAndExpenses: incomeAndExpenses
                case .byCategory: byCategory
                case .byTag: grouped(.tag)
                case .byPayee: grouped(.payee)
                }
                ErrorText(message: tracking.error)
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Informes")
        .task(id: tracking.period) { await tracking.loadReport() }
        .task(id: finance.recent) { await tracking.loadSixMonths() }
        .refreshable {
            await tracking.loadReport()
            await tracking.loadSixMonths()
        }
    }

    // MARK: Ingresos y gastos (últimos 6 meses), como en Android

    private struct MonthBar: Identifiable {
        var month: MonthKey
        var kind: String
        var amount: Money
        var id: String { "\(month.year)-\(month.month)-\(kind)" }
    }

    @ViewBuilder
    private var incomeAndExpenses: some View {
        let startDay = tracking.household.monthStartDay
        let range = ReportPeriod.last6Months.range(monthStartDay: startDay)
        let movements = tracking.sixMonthMovements
        let income = SpendingReport(movements: movements, categories: finance.categories, range: range, kind: .income,
                                    monthStartDay: startDay)
        let spending = SpendingReport(movements: movements, categories: finance.categories, range: range, kind: .expense,
                                      monthStartDay: startDay)
        let bars = income.byMonth.map { MonthBar(month: $0.month, kind: String(localized: "Ingresos"), amount: $0.amount) }
            + spending.byMonth.map { MonthBar(month: $0.month, kind: String(localized: "Gastos"), amount: $0.amount) }
        let saving = income.averagePerMonth - spending.averagePerMonth
        let rise = BiggestRise.find(movements: movements, categories: finance.categories,
                                    month: MonthKey.containing(CalendarDay(), startDay: startDay), monthStartDay: startDay)

        VStack(alignment: .leading, spacing: Spacing.s16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ingresos y gastos")
                    .titleFont(.title2)
                    .foregroundStyle(Palette.label)
                Spacer()
                Text("Últimos 6 meses")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
            }
            Chart(bars) { bar in
                BarMark(x: .value("Mes", bar.month.firstDay.date(), unit: .month),
                        y: .value("Importe", max(0, bar.amount.decimal)))
                    .foregroundStyle(by: .value("Tipo", bar.kind))
                    .position(by: .value("Tipo", bar.kind))
                    .cornerRadius(4)
            }
            .chartForegroundStyleScale([String(localized: "Ingresos"): Palette.positive, String(localized: "Gastos"): Palette.accent])
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartHeight(180)
            .accessibilityLabel("Gráfico de ingresos y gastos de los últimos 6 meses")
        }
        .card()

        VStack(alignment: .leading, spacing: Spacing.s16) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    Text("Ahorro medio")
                        .font(Typography.headline)
                        .foregroundStyle(Palette.label)
                    Text("Lo que te queda cada mes")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                }
                Spacer()
                Text((saving.isNegative ? "−" : "+") + Money(minor: abs(saving.minor)).formatted())
                    .font(Typography.headline)
                    .foregroundStyle(saving.isNegative ? Palette.negativeText : Palette.positiveText)
            }
            .accessibilityElement(children: .combine)
            if let rise {
                Divider()
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    Text("Categoría que más sube")
                        .font(Typography.headline)
                        .foregroundStyle(Palette.label)
                    Text(rise.title + (rise.percent.map { ", +\($0) %" } ?? "") + String(localized: " vs. ") + rise.previous.title.lowercased())
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    // MARK: Por categoría

    @ViewBuilder
    private var byCategory: some View {
        @Bindable var tracking = tracking
        let report = tracking.report(categories: finance.categories)
        let previous = tracking.previousReport(categories: finance.categories)
        VStack(alignment: .leading, spacing: Spacing.s16) {
            CapsuleSegmented(String(localized: "Qué"), selection: $tracking.kind, options: SpendingReport.Kind.allCases) { $0.title }
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
            comparison(report, previous)
            Text("\(report.averagePerDay.formatted()) al día de media · \(report.byCategory.reduce(0) { $0 + $1.count }) movimientos")
                .font(Typography.subheadline)
                .foregroundStyle(Palette.labelSecondary)
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
                EmptyHint(text: tracking.isLoading ? String(localized: "Cargando…") : String(localized: "No hay movimientos en este periodo."))
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
    }

    // MARK: Por etiqueta y por beneficiario

    @ViewBuilder
    private func grouped(_ grouping: GroupedSpending.Grouping) -> some View {
        @Bindable var tracking = tracking
        let rows = GroupedSpending.report(grouping, movements: tracking.reportMovements,
                                          categories: finance.categories, range: tracking.reportRange)
        let top = max(1, rows.map(\.spent.minor).max() ?? 1)
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Picker("Periodo", selection: $tracking.period) {
                ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
            }
        }
        .card()

        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text(grouping.title)
                .titleFont(.title2)
                .foregroundStyle(Palette.label)
            if rows.isEmpty {
                EmptyHint(text: tracking.isLoading ? String(localized: "Cargando…") : grouping == .tag
                          ? String(localized: "No hay movimientos con etiquetas en este periodo. Añádelas al editar un movimiento.")
                          : String(localized: "No hay movimientos con beneficiario en este periodo. Añádelo al editar un movimiento."))
            }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    HStack {
                        Label(grouping == .tag ? "#" + row.title : row.title,
                              systemImage: grouping == .tag ? "number" : "person")
                            .font(Typography.subheadlineEmphasis)
                            .foregroundStyle(Palette.label)
                        Spacer()
                        Text(row.spent.formatted())
                            .font(Typography.subheadlineEmphasis)
                            .foregroundStyle(Palette.label)
                    }
                    ProgressBar(fraction: Double(row.spent.minor) / Double(top))
                    Text(row.income.minor > 0
                         ? "\(row.count) movimientos · ingresos \(row.income.formatted())"
                         : "\(row.count) movimientos")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Un movimiento con varias etiquetas cuenta en cada una. No se incluyen transferencias ni excluidos.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
        }
        .card()
    }

    /// "+12 % (+40,00 €) que el mes pasado a estas alturas". En gastos, subir es malo (rojo); en ingresos, bueno.
    @ViewBuilder
    private func comparison(_ report: SpendingReport, _ previous: SpendingReport) -> some View {
        let change = report.change(from: previous)
        if previous.total.minor > 0 || report.total.minor > 0 {
            let up = change.difference.minor > 0
            let good = tracking.kind == .expense ? !up : up
            let percent = change.percent.map { ($0 > 0 ? "+" : "") + "\($0) % · " } ?? ""
            Text(change.difference.minor == 0
                 ? String(localized: "Igual que \(tracking.period.previousTitle)")
                 : percent + change.difference.signedText() + String(localized: " frente a ") + tracking.period.previousTitle)
                .font(Typography.subheadlineEmphasis)
                .foregroundStyle(change.difference.minor == 0 ? Palette.labelSecondary : (good ? Palette.positiveText : Palette.negativeText))
        }
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
