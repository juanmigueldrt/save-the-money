import SwiftUI
import STMCore
import STMUI

/// Lo que hace falta para pintar el calendario, sacado de los modelos que ya están cargados.
@MainActor
struct PaymentCalendarSource {
    let planning: PlanningModel
    let cards: CreditCardModel
    let investments: InvestmentModel

    var calendar: PaymentCalendar {
        let cardPayments = cards.cardAccounts.flatMap { account in
            (cards.summary(for: account)?.payments ?? []).map { (name: account.name, accountId: account.id, payment: $0) }
        }
        let plans = investments.plans.map { plan in
            (name: investments.holding(plan.holdingId)?.name ?? "Inversión", plan: plan)
        }
        return PaymentCalendar(series: planning.series, cardPayments: cardPayments, plans: plans)
    }
}

/// Calendario de gastos: el mes con los días que tienen pagos; al tocar un día,
/// sus pagos y los siguientes.
struct PaymentCalendarView: View {
    @Environment(PlanningModel.self) private var planning
    @Environment(CreditCardModel.self) private var cards
    @Environment(InvestmentModel.self) private var investments
    @State private var month: MonthKey = MonthKey(CalendarDay())
    @State private var selected: CalendarDay = CalendarDay()

    private var calendar: PaymentCalendar {
        PaymentCalendarSource(planning: planning, cards: cards, investments: investments).calendar
    }

    var body: some View {
        let calendar = self.calendar
        let data = calendar.month(month)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                totals(data).card()
                MonthGrid(month: data, selected: $selected, today: planning.day)
                    .card()
                dayCard(data.payments(on: selected)).card()
                nextCard(calendar.next(after: selected)).card()
                ErrorText(message: planning.error)
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Calendario de pagos")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Mes anterior", systemImage: "chevron.left") { move(-1) }
                Button("Hoy", systemImage: "calendar") { jump(to: planning.day) }
                Button("Mes siguiente", systemImage: "chevron.right") { move(1) }
            }
        }
        .refreshable {
            await planning.load()
            await investments.load()
        }
        .onAppear {
            month = MonthKey(planning.day)
            selected = planning.day
        }
    }

    private func move(_ months: Int) {
        month = month.adding(months: months)
        selected = MonthKey(planning.day) == month ? planning.day : month.firstDay
    }

    private func jump(to day: CalendarDay) {
        month = MonthKey(day)
        selected = day
    }

    private func totals(_ data: PaymentMonth) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            Eyebrow("Pagos de \(data.key.title.lowercased())")
            Text(data.totalOut.formatted())
                .titleFont(.largeTitle)
                .foregroundStyle(Palette.label)
                .contentTransition(.numericText())
            if data.totalIn.minor > 0 {
                Text("Ingresos fijos previstos: \(data.totalIn.formatted())")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.positiveText)
            }
            Text("Pagos fijos, suscripciones, cargos de tarjeta y aportaciones a inversiones.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func dayCard(_ payments: [CalendarPayment]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text(selected.weekdayTitle)
                .titleFont(.title2)
                .foregroundStyle(Palette.label)
            if payments.isEmpty {
                EmptyHint(text: "No hay pagos este día.")
            }
            ForEach(payments) { PaymentRow(payment: $0, showsDay: false) }
            if payments.count > 1 {
                let total = payments.reduce(Money.zero) { $0 + $1.amount }
                HStack {
                    Text("Total del día")
                        .font(Typography.subheadline)
                        .foregroundStyle(Palette.labelSecondary)
                    Spacer()
                    Text(total.formatted())
                        .font(Typography.subheadlineEmphasis)
                        .foregroundStyle(Palette.label)
                }
            }
        }
    }

    private func nextCard(_ payments: [CalendarPayment]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text("Próximos pagos")
                .titleFont(.title2)
                .foregroundStyle(Palette.label)
            if payments.isEmpty {
                EmptyHint(text: "No hay más pagos previstos. Añade tus pagos fijos y suscripciones para verlos aquí.")
            }
            ForEach(payments) { payment in
                Button { jump(to: payment.day) } label: { PaymentRow(payment: payment, showsDay: true) }
                    .buttonStyle(.plain)
            }
        }
    }
}

/// Cuadrícula del mes, de lunes a domingo, con un punto en los días con pagos.
private struct MonthGrid: View {
    let month: PaymentMonth
    @Binding var selected: CalendarDay
    let today: CalendarDay

    private let symbols = ["L", "M", "X", "J", "V", "S", "D"]

    var body: some View {
        let marked = month.daysWithPayments
        VStack(spacing: Spacing.s8) {
            Text(month.key.title)
                .font(Typography.headline)
                .foregroundStyle(Palette.label)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(symbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(Typography.caption1.weight(.semibold))
                        .foregroundStyle(Palette.labelSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            ForEach(Array(month.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        if let day = week[index] {
                            DayCell(day: day, isSelected: day == selected, isToday: day == today,
                                    hasPayments: marked.contains(day)) { selected = day }
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: ControlSize.hitTarget)
                        }
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: CalendarDay
    let isSelected: Bool
    let isToday: Bool
    let hasPayments: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(day.day)")
                    .font(isToday ? Typography.subheadlineEmphasis : Typography.subheadline)
                    .foregroundStyle(isSelected ? Palette.onAccent : (isToday ? Palette.accentText : Palette.label))
                    .frame(width: 34, height: 34)
                    .background {
                        if isSelected {
                            Circle().fill(Palette.accent)
                        } else if isToday {
                            Circle().strokeBorder(Palette.accent, lineWidth: 1.5)
                        }
                    }
                Circle()
                    .fill(hasPayments ? Palette.accent : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: ControlSize.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.longTitle + (hasPayments ? ", con pagos" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Un pago del calendario: nombre, origen, día e importe.
struct PaymentRow: View {
    let payment: CalendarPayment
    let showsDay: Bool

    var body: some View {
        HStack(spacing: Spacing.s12) {
            Image(systemName: payment.source.systemImage)
                .font(Typography.subheadline)
                .foregroundStyle(Palette.labelSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.title)
                    .font(Typography.subheadlineEmphasis)
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                Text(detail)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
            }
            Spacer()
            Text(payment.amount.formatted())
                .font(Typography.subheadlineEmphasis)
                .foregroundStyle(payment.amount.isNegative ? Palette.label : Palette.positiveText)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [payment.source.title]
        if showsDay { parts.insert(payment.day.shortText, at: 0) }
        if payment.isEstimate { parts.append("estimado") }
        return parts.joined(separator: " · ")
    }
}

/// Tarjeta del Resumen con el próximo pago y el acceso al calendario.
struct NextPaymentsCard: View {
    @Environment(PlanningModel.self) private var planning
    @Environment(CreditCardModel.self) private var cards
    @Environment(InvestmentModel.self) private var investments

    var body: some View {
        let calendar = PaymentCalendarSource(planning: planning, cards: cards, investments: investments).calendar
        let next = calendar.next(after: planning.day.adding(days: -1), limit: 3)
        NavigationLink {
            PaymentCalendarView()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.s16) {
                HStack {
                    Text("Calendario de pagos")
                        .titleFont(.title2)
                        .foregroundStyle(Palette.label)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                }
                if next.isEmpty {
                    EmptyHint(text: "Cuando añadas pagos fijos o suscripciones verás aquí los próximos.")
                }
                ForEach(next) { PaymentRow(payment: $0, showsDay: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .card()
        }
        .buttonStyle(.plain)
    }
}
