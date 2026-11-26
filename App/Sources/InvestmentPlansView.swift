import SwiftUI
import Charts
import STMCore
import STMUI

// MARK: - Aportaciones automáticas

/// Planes para invertir una cantidad fija cada cierto tiempo, con el calendario del mes.
struct InvestmentPlansView: View {
    @Environment(InvestmentModel.self) private var investments
    @State private var editing: InvestmentPlan?
    @State private var adding = false

    var body: some View {
        let month = MonthKey(investments.day)
        let charges = investments.charges(in: month)
        let counts = investments.planCounts
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    Eyebrow("Aportaciones automáticas")
                    Text(investments.monthlyPlanned.formatted())
                        .titleFont(.largeTitle)
                        .foregroundStyle(Palette.label)
                    Text(summary(counts))
                        .font(Typography.subheadline)
                        .foregroundStyle(Palette.labelSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                AdaptiveColumns {
                    calendarCard(month: month, charges: charges)
                } trailing: {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        ForEach(investments.livePlans) { plan in
                            PlanCard(plan: plan) { editing = plan }
                        }
                        Button("Nuevo plan") { adding = true }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(investments.activeHoldings.isEmpty)
                        if investments.activeHoldings.isEmpty {
                            EmptyHint(text: "Añade antes un activo en la cartera.")
                        }
                    }
                }

                Text("Un plan no compra nada solo: te avisa el día que toca y tú confirmas la compra en la app.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                ErrorText(message: investments.error)
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Aportaciones")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nuevo plan", systemImage: "plus") { adding = true }
                    .disabled(investments.activeHoldings.isEmpty)
            }
        }
        .refreshable { await investments.load() }
        .sheet(isPresented: $adding) { PlanFormView(plan: nil) }
        .sheet(item: $editing) { PlanFormView(plan: $0) }
    }

    private func summary(_ counts: (active: Int, paused: Int)) -> String {
        let active = counts.active == 1 ? "1 plan activo" : "\(counts.active) planes activos"
        let paused = counts.paused == 0 ? "" : " y \(counts.paused) en pausa"
        return "al mes en \(active)\(paused)"
    }

    private func calendarCard(month: MonthKey, charges: [PlanCharge]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text(month.title)
                .titleFont(.title2)
                .foregroundStyle(Palette.label)
            if charges.isEmpty {
                EmptyHint(text: "Este mes no hay aportaciones.")
            } else {
                Chart(charges) { charge in
                    BarMark(x: .value("Día", charge.due.date(), unit: .day), y: .value("Importe", charge.plan.amount.decimal))
                        .foregroundStyle(charge.due < investments.day ? Palette.labelTertiary : Palette.accent)
                        .cornerRadius(4)
                }
                .chartXScale(domain: month.firstDay.date()...month.adding(months: 1).firstDay.date())
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.day())
                    }
                }
                .chartHeight(140)
                .accessibilityLabel("Calendario de aportaciones del mes")
                ForEach(charges) { charge in
                    HStack {
                        Text(charge.due.longTitle)
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.label)
                        Spacer()
                        Text(investments.holding(charge.plan.holdingId)?.trimmedName ?? "")
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.labelSecondary)
                            .lineLimit(1)
                        Text(charge.plan.amount.formatted())
                            .font(Typography.subheadlineEmphasis.monospacedDigit())
                            .foregroundStyle(Palette.label)
                            .fixedSize()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card()
    }
}

/// Tarjeta de un plan con su interruptor.
struct PlanCard: View {
    let plan: InvestmentPlan
    let edit: () -> Void

    @Environment(InvestmentModel.self) private var investments
    @Environment(FinanceModel.self) private var finance

    var body: some View {
        let holding = investments.holding(plan.holdingId)
        let position = holding.map(investments.position(of:))
        VStack(alignment: .leading, spacing: Spacing.s16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(holding?.trimmedName ?? "Activo")
                        .font(Typography.headline)
                        .foregroundStyle(Palette.label)
                    Text(subtitle(holding))
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("Activo", isOn: Binding(get: { !plan.isPaused },
                                               set: { on in Task { await investments.setPaused(!on, plan) } }))
                    .labelsHidden()
            }
            Grid(alignment: .leading, horizontalSpacing: Spacing.s16, verticalSpacing: Spacing.s12) {
                GridRow {
                    figure("Aportación", "\(plan.amount.formatted()) · \(plan.recurrence.title.lowercased())")
                    figure(plan.isPaused ? "Estado" : "Próxima",
                           plan.isPaused ? "En pausa" : plan.nextDue(onOrAfter: investments.day)?.longTitle ?? "Terminado")
                }
                GridRow {
                    figure("Invertido con el plan", plan.invested(trades: investments.trades, through: investments.day).formatted())
                    figure("Rentabilidad del activo", position?.gainFraction.map(InvestmentText.percent) ?? "—",
                           color: position.map { InvestmentText.gainColor($0.gain) } ?? Palette.label)
                }
            }
            Button("Editar plan", action: edit)
                .font(Typography.subheadlineEmphasis)
        }
        .card()
        .opacity(plan.isPaused ? 0.75 : 1)
    }

    private func subtitle(_ holding: Holding?) -> String {
        let who = investments.ownerName(holding?.ownerId)
        guard let id = plan.accountId, let account = finance.account(id) else { return who }
        return "\(who) · desde \(account.name)"
    }

    private func figure(_ title: String, _ value: String, color: Color = Palette.label) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
            Text(value)
                .font(Typography.subheadlineEmphasis)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
