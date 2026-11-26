import SwiftUI
import Charts
import STMCore
import STMUI

// MARK: - Patrimonio neto

/// Lo que tiene el hogar menos lo que debe, y cómo ha ido en los últimos 12 meses.
struct NetWorthView: View {
    @Environment(FinanceModel.self) private var finance
    @Environment(TrackingModel.self) private var tracking
    @State private var range: NetWorthRange = .sixMonths

    var body: some View {
        let now = NetWorth.current(accounts: finance.accounts, balances: finance.balances)
        let history = tracking.history(accounts: finance.accounts, range: range)
        let rangeChange = NetWorthRange.change(history)
        let projection = NetWorthProjection(history: tracking.history(accounts: finance.accounts, months: 7))
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
                    if history.count >= 2 {
                        Text((rangeChange.isNegative ? "−" : "+") + Money(minor: abs(rangeChange.minor)).formatted() + " " + range.caption)
                            .font(Typography.subheadlineEmphasis)
                            .foregroundStyle(rangeChange.isNegative ? Palette.negativeText : Palette.positiveText)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: Spacing.s16) {
                    Text("Evolución")
                        .titleFont(.title2)
                        .foregroundStyle(Palette.label)
                    CapsuleSegmented("Tramo", selection: $range, options: NetWorthRange.allCases) { $0.title }
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
                            AxisMarks(values: .stride(by: .month, count: max(1, history.count / 4))) { _ in
                                AxisValueLabel(format: .dateTime.month(.abbreviated))
                            }
                        }
                        .chartHeight(200)
                        .accessibilityLabel("Gráfico del patrimonio neto, \(range.caption)")
                    }
                }
                .card()

                if let projection, !finance.accounts.isEmpty {
                    projectionCard(projection)
                }

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

    /// "A final de año: 12.400 €", con la línea discontinua de la predicción.
    private func projectionCard(_ projection: NetWorthProjection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            HStack(alignment: .firstTextBaseline) {
                Text("A final de año")
                    .titleFont(.title2)
                    .foregroundStyle(Palette.label)
                Spacer()
                Text(projection.endOfYear.formatted())
                    .font(Typography.headline)
                    .foregroundStyle(projection.endOfYear.isNegative ? Palette.negativeText : Palette.label)
            }
            Chart(projection.points) { point in
                LineMark(x: .value("Mes", point.month.firstDay.date(), unit: .month),
                         y: .value("Patrimonio", point.net.decimal))
                    .foregroundStyle(Palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                PointMark(x: .value("Mes", point.month.firstDay.date(), unit: .month),
                          y: .value("Patrimonio", point.net.decimal))
                    .foregroundStyle(Palette.accent)
                    .symbolSize(20)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .frame(height: 120)
            .accessibilityLabel("Predicción del patrimonio hasta diciembre")
            Text("Si sigue como los últimos meses (\(projection.monthlyChange.signedText()) al mes de media). Es una estimación, no una promesa.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
        }
        .card()
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
