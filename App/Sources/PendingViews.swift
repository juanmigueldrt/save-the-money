import SwiftUI
import STMCore
import STMUI

// MARK: Pagos fijos pendientes de confirmar

/// Los cargos de pagos fijos que han llegado y esperan confirmación. Sale en Resumen
/// sólo si hay alguno.
struct PendingChargesCard: View {
    @Environment(PlanningModel.self) private var planning
    @Environment(FinanceModel.self) private var finance
    @State private var confirming: PendingCharge?

    var body: some View {
        let pending = planning.pending
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s16) {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    Text("Pendientes de confirmar")
                        .titleFont(.title2)
                        .foregroundStyle(Palette.label)
                    Text("Aún no cuentan en tus saldos ni en el presupuesto.")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                }
                ForEach(pending.prefix(5)) { item in
                    PendingChargeRow(item: item, accountName: item.series.accountId.flatMap { finance.account($0)?.name }) {
                        confirming = item
                    } onSkip: {
                        Task { await planning.skip(item) }
                    }
                }
                if pending.count > 5 {
                    Text("Y \(pending.count - 5) más.")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                }
                ErrorText(message: planning.error)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .sheet(item: $confirming) { ConfirmChargeView(item: $0) }
        }
    }
}

struct PendingChargeRow: View {
    let item: PendingCharge
    let accountName: String?
    let onConfirm: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            HStack(alignment: .firstTextBaseline) {
                Label(item.series.trimmedName, systemImage: item.series.kind.systemImage)
                    .font(Typography.subheadlineEmphasis)
                    .foregroundStyle(Palette.label)
                Spacer()
                Text(item.charge.amount.formatted())
                    .font(Typography.subheadlineEmphasis)
                    .foregroundStyle(item.charge.amount.isNegative ? Palette.label : Palette.positiveText)
            }
            Text([item.charge.dueOn.shortText, accountName].compactMap { $0 }.joined(separator: " · "))
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
            HStack(spacing: Spacing.s8) {
                Button("Confirmar", action: onConfirm)
                    .buttonStyle(PrimaryButtonStyle())
                Button("No se ha cobrado", action: onSkip)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Confirmar un cargo: se puede cambiar el importe, el día y la cuenta antes de apuntarlo.
struct ConfirmChargeView: View {
    let item: PendingCharge

    @Environment(PlanningModel.self) private var planning
    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var day = Date()
    @State private var accountId: UUID?
    @State private var categoryId: UUID?
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(String(localized: "Importe, p. ej. 12,99"), text: $amount)
                    DatePicker("Día", selection: $day, displayedComponents: .date)
                        .environment(\.locale, AppRegion.locale)
                    Picker("Cuenta", selection: $accountId) {
                        Text("Elige una cuenta").tag(UUID?.none)
                        ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Categoría", selection: $categoryId) {
                        Text("Sin categoría").tag(UUID?.none)
                        ForEach(finance.categories(for: item.series.kind == .income ? .income : .expense)) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                } footer: {
                    Text("Se apunta como un movimiento normal. Si el importe ha cambiado, pon el que te han cobrado de verdad.")
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle(item.series.trimmedName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirmar") { Task { await confirm() } }.disabled(isWorking)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 360)
        .onAppear(perform: fill)
    }

    private func fill() {
        amount = Money(minor: abs(item.charge.amount.minor)).plainText
        day = item.charge.dueOn.date()
        accountId = item.series.accountId ?? finance.activeAccounts.first(where: \.isDefault)?.id
        categoryId = item.series.categoryId
    }

    private func confirm() async {
        guard let money = Money(entered: amount), money.minor > 0 else {
            error = String(localized: "Escribe el importe, por ejemplo 12,99.")
            return
        }
        guard let accountId else {
            error = String(localized: "Elige la cuenta del cargo.")
            return
        }
        let signed = item.series.kind == .income ? money : Money(minor: -money.minor)
        let draft = MovementDraft(accountId: accountId, categoryId: categoryId, bookedOn: CalendarDay(day),
                                  amount: signed, description: item.series.trimmedName)
        isWorking = true
        defer { isWorking = false }
        if await planning.confirm(item, with: draft) {
            await finance.load()
            dismiss()
        } else {
            error = planning.error
        }
    }
}

// MARK: Resumen semanal

/// La semana pasada en una línea; lleva al resumen completo.
struct WeeklySummaryCard: View {
    @Environment(FinanceModel.self) private var finance
    @Environment(PlanningModel.self) private var planning

    var body: some View {
        let summary = WeeklySummary(movements: finance.recent, categories: finance.categories, today: planning.day)
        NavigationLink {
            WeeklySummaryView()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                HStack {
                    Eyebrow(String(localized: "La semana pasada · \(summary.title)"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                }
                Text(summary.week.spent.formatted())
                    .titleFont(.title1)
                    .foregroundStyle(Palette.label)
                Text(WeeklySummaryView.changeText(summary))
                    .font(Typography.subheadline)
                    .foregroundStyle(Palette.labelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Resumen de una semana: total frente a la anterior, gastos más grandes, categorías y mapa de calor.
struct WeeklySummaryView: View {
    @Environment(FinanceModel.self) private var finance
    @Environment(PlanningModel.self) private var planning
    @State private var current = false

    var body: some View {
        let summary = WeeklySummary(movements: finance.recent, categories: finance.categories, today: planning.day,
                                    includeCurrent: current)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                CapsuleSegmented(String(localized: "Semana"), selection: $current, options: [false, true]) { $0 ? String(localized: "Esta semana") : String(localized: "La pasada") }

                VStack(alignment: .leading, spacing: Spacing.s8) {
                    Eyebrow(summary.title)
                    Text(summary.week.spent.formatted())
                        .titleFont(.largeTitle)
                        .foregroundStyle(Palette.label)
                    Text(Self.changeText(summary))
                        .font(Typography.subheadline)
                        .foregroundStyle(Palette.labelSecondary)
                    Divider()
                    SummaryLine(title: String(localized: "Ingresos"), amount: summary.week.income)
                    SummaryLine(title: String(localized: "Semana anterior"), amount: summary.previous.spent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                VStack(alignment: .leading, spacing: Spacing.s16) {
                    Text("Gastos más grandes")
                        .titleFont(.title2)
                        .foregroundStyle(Palette.label)
                    if summary.biggest.isEmpty {
                        EmptyHint(text: String(localized: "No hay gastos esta semana."))
                    }
                    ForEach(summary.biggest) { movement in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(movement.description)
                                    .font(Typography.subheadlineEmphasis)
                                    .foregroundStyle(Palette.label)
                                    .lineLimit(1)
                                Text("\(movement.bookedOn.weekdayName.capitalized), \(movement.bookedOn.shortText)")
                                    .font(Typography.footnote)
                                    .foregroundStyle(Palette.labelSecondary)
                            }
                            Spacer()
                            Text(Money(minor: -movement.amount.minor).formatted())
                                .font(Typography.subheadlineEmphasis)
                                .foregroundStyle(Palette.label)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                if !summary.topCategories.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text("En qué se fue")
                            .titleFont(.title2)
                            .foregroundStyle(Palette.label)
                        ForEach(summary.topCategories) { row in
                            VStack(alignment: .leading, spacing: Spacing.s4) {
                                HStack {
                                    Label(row.title, systemImage: row.icon ?? "tag")
                                        .font(Typography.subheadline)
                                        .foregroundStyle(Palette.label)
                                    Spacer()
                                    Text(row.amount.formatted())
                                        .font(Typography.subheadlineEmphasis)
                                        .foregroundStyle(Palette.label)
                                }
                                ProgressBar(fraction: row.share)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                VStack(alignment: .leading, spacing: Spacing.s16) {
                    Text("Día a día")
                        .titleFont(.title2)
                        .foregroundStyle(Palette.label)
                    SpendingHeatmap(weeks: summary.heatmap)
                    Text("Cuanto más oscuro, más gastaste ese día. Las últimas 6 semanas.")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Resumen semanal")
    }

    static func changeText(_ summary: WeeklySummary) -> String {
        guard let percent = summary.change.percent else {
            return summary.previous.spent.minor == 0 ? String(localized: "La semana anterior no hubo gastos.") : ""
        }
        if percent == 0 { return String(localized: "Lo mismo que la semana anterior.") }
        return percent > 0 ? String(localized: "\(percent) % más que la semana anterior") : String(localized: "\(-percent) % menos que la semana anterior")
    }
}

/// Cuadrícula de lunes a domingo, una fila por semana.
struct SpendingHeatmap: View {
    let weeks: [[WeeklySummary.Day]]
    private let letters = ["L", "M", "X", "J", "V", "S", "D"]

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(letters, id: \.self) { letter in
                    Text(letter)
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(week) { day in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(day.spent.minor == 0 ? Palette.bgGrouped : Palette.accent.opacity(0.2 + 0.8 * day.intensity))
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("\(day.day.weekdayName) \(day.day.shortText): \(day.spent.formatted())")
                    }
                }
            }
        }
    }
}
