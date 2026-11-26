import SwiftUI
import Charts
import STMCore
import STMUI

/// Detalle de una cuenta: saldo, sus movimientos y editarla.
struct AccountDetailView: View {
    let account: Account

    @Environment(FinanceModel.self) private var finance
    @State private var editing = false
    @State private var adjusting = false
    @State private var movements: [Movement] = []
    @State private var chartError: String?

    private var current: Account { finance.account(account.id) ?? account }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saldo")
                        .font(Typography.subheadlineEmphasis)
                        .foregroundStyle(Palette.labelSecondary)
                    Text(finance.balance(of: current).formatted())
                        .titleFont(.title1)
                        .foregroundStyle(finance.balance(of: current).isNegative ? Palette.negativeText : Palette.label)
                }
                Spacer()
            }
            .padding(Spacing.s16)
            .background(Palette.bgGrouped2)
            AccountBalanceChart(account: current, movements: movements)
                .padding(.horizontal, Spacing.s16)
                .padding(.bottom, Spacing.s12)
                .background(Palette.bgGrouped2)
            if let chartError {
                ErrorText(message: chartError)
                    .padding(.horizontal, Spacing.s16)
                    .padding(.bottom, Spacing.s12)
                    .background(Palette.bgGrouped2)
            }
            if current.kind == .creditCard {
                NavigationLink {
                    CreditCardDetailView(account: current)
                } label: {
                    Label("Próximo cargo, límite y aplazados", systemImage: "creditcard")
                        .font(Typography.subheadlineEmphasis)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.s16)
                        .padding(.vertical, Spacing.s12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accentText)
                .background(Palette.bgGrouped2)
            }
            MovementsView(account: current)
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button("Actualizar saldo", systemImage: "equal.circle") { adjusting = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Editar cuenta", systemImage: "pencil") { editing = true }
            }
        }
        .sheet(isPresented: $editing) { AccountFormView(account: current) }
        .sheet(isPresented: $adjusting) { BalanceAdjustmentView(account: current) }
        .task(id: finance.recent) {
            do {
                movements = try await finance.movements(of: current)
                chartError = nil
            } catch is CancellationError {
                return
            } catch {
                chartError = "No se han podido cargar los movimientos del gráfico. " + ((error as? AppError)?.errorDescription ?? "")
            }
        }
    }
}

extension CalendarDay {
    /// "Hoy", "Ayer" o "lunes, 3 de noviembre" para las cabeceras de la lista por días.
    var dayHeader: String {
        let today = CalendarDay()
        if self == today { return "Hoy" }
        if self == today.adding(days: -1) { return "Ayer" }
        let style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_ES"))
        let text = date().formatted(year == today.year ? style : style.year())
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "3 oct" para las filas.
    var shortText: String {
        date().formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_ES")))
    }
}

/// Saldo de una cuenta al final de cada uno de los últimos 6 meses, como en Android.
struct AccountBalanceChart: View {
    let account: Account
    let movements: [Movement]

    private struct Point: Identifiable {
        var month: MonthKey
        var balance: Money
        var id: MonthKey { month }
    }

    var body: some View {
        let points = NetWorth.history(accounts: [account], movements: movements, months: 6, through: MonthKey(CalendarDay()))
            .map { Point(month: $0.month, balance: $0.net) }
        Chart(points) { point in
            LineMark(x: .value("Mes", point.month.firstDay.date(), unit: .month),
                     y: .value("Saldo", point.balance.decimal))
                .foregroundStyle(Palette.accent)
                .lineStyle(StrokeStyle(lineWidth: 2))
            PointMark(x: .value("Mes", point.month.firstDay.date(), unit: .month),
                      y: .value("Saldo", point.balance.decimal))
                .foregroundStyle(Palette.accent)
                .symbolSize(24)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .frame(height: 120)
        .accessibilityLabel("Saldo de la cuenta en los últimos 6 meses")
    }
}

/// «Actualizar saldo»: escribes lo que marca el banco y se apunta un ajuste por la diferencia.
struct BalanceAdjustmentView: View {
    let account: Account

    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var actual = ""
    @State private var error: String?
    @State private var isWorking = false

    private var current: Money { finance.balance(of: account) }

    private var difference: Money? {
        Money(entered: actual).map { Money(minor: $0.minor - current.minor) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Saldo en la app", value: current.formatted())
                    AmountField("Saldo real, p. ej. 1.250,00", text: $actual)
                    if let difference, difference.minor != 0 {
                        LabeledContent("Ajuste", value: difference.signedText())
                    }
                } footer: {
                    Text("Se apunta un movimiento «Ajuste de saldo» por la diferencia, hoy. No cuenta como gasto ni como ingreso.")
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle("Actualizar saldo")
            .formToolbar(isWorking: isWorking, cancel: { dismiss() }, save: { await save() })
        }
        .frame(minWidth: 360, minHeight: 300)
    }

    private func save() async {
        guard let money = Money(entered: actual) else {
            error = "Escribe el saldo, por ejemplo 1.250,00."
            return
        }
        isWorking = true
        defer { isWorking = false }
        if await finance.adjustBalance(of: account, to: money) { dismiss() } else { error = finance.error }
    }
}
