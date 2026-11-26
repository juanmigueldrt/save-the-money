import SwiftUI
import STMCore
import STMUI

/// Detalle de una tarjeta: calendario de cargos, coste del pago aplazado y compras a plazos.
struct CreditCardDetailView: View {
    let account: Account

    @Environment(CreditCardModel.self) private var cards
    @Environment(FinanceModel.self) private var finance
    @State private var editingTerms = false
    @State private var deferring = false
    @State private var recordingPayment = false
    @State private var removingPlan: CardInstallment?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                if let summary = cards.summary(for: account) {
                    CardOverview(name: account.name, summary: summary).card()
                    if summary.isOverAlert, let percent = summary.terms.alertPercent {
                        Label("Has pasado del \(percent) % del límite. Te quedan \(summary.available.formatted()).",
                              systemImage: "exclamationmark.triangle")
                            .font(Typography.subheadlineEmphasis)
                            .foregroundStyle(Palette.negativeText)
                            .card()
                    }
                    if !summary.uncategorizedCredits.isEmpty {
                        Label(CardText.uncategorizedCredits(summary.uncategorizedCredits.count),
                              systemImage: "exclamationmark.triangle")
                            .font(Typography.subheadlineEmphasis)
                            .foregroundStyle(Palette.negativeText)
                            .card()
                    }
                    if !summary.unresolvedInstallments.isEmpty {
                        Label(CardText.unresolvedInstallments(summary.unresolvedInstallments.count),
                              systemImage: "exclamationmark.triangle")
                            .font(Typography.subheadlineEmphasis)
                            .foregroundStyle(Palette.negativeText)
                            .card()
                    }
                    if summary.movementsTruncated {
                        Label(CardText.movementsTruncated(CreditCardModel.cycleLimit), systemImage: "exclamationmark.triangle")
                            .font(Typography.subheadlineEmphasis)
                            .foregroundStyle(Palette.negativeText)
                            .card()
                    }
                    calendar(summary).card()
                    if summary.terms.paymentMode.isRevolving { revolving(summary).card() }
                    installmentsCard(summary).card()
                    payFrom(summary).card()
                } else {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        EmptyHint(text: "Pon el límite, el día del extracto y cómo la pagas para calcular tus cargos.")
                        Button("Configurar tarjeta") { editingTerms = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .card()
                }
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Condiciones", systemImage: "slider.horizontal.3") { editingTerms = true }
            }
        }
        .sheet(isPresented: $editingTerms) { CardTermsFormView(account: account) }
        .sheet(isPresented: $deferring) { DeferPurchaseView(account: account) }
        .sheet(isPresented: $recordingPayment) { CardPaymentFormView(account: account) }
        .confirmationDialog("¿Quitar este aplazado?",
                            isPresented: Binding(get: { removingPlan != nil }, set: { if !$0 { removingPlan = nil } }),
                            titleVisibility: .visible, presenting: removingPlan) { plan in
            Button("Quitar el aplazado", role: .destructive) { Task { await cards.removeInstallment(plan) } }
        } message: { _ in
            Text("La compra se queda en el extracto como un cargo normal. Puedes volver a aplazarla cuando quieras.")
        }
    }

    private func calendar(_ summary: CreditCardSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text("Próximos cargos")
                .titleFont(.title2)
                .foregroundStyle(Palette.label)
            ForEach(summary.payments) { payment in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payment.due.longTitle)
                            .font(Typography.subheadlineEmphasis)
                            .foregroundStyle(Palette.label)
                        Text(CardText.breakdown(payment, mode: summary.terms.paymentMode))
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.labelSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(payment.amount.formatted())
                            .font(Typography.subheadlineEmphasis.monospacedDigit())
                            .foregroundStyle(Palette.label)
                        if payment.isEstimate {
                            Text("estimado")
                                .font(Typography.caption1)
                                .foregroundStyle(Palette.labelSecondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Text("Lo que gastas entra en el extracto del día \(summary.terms.statementDay), que se cobra \(CardText.delay(summary.terms)).")
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
        }
    }

    private func revolving(_ summary: CreditCardSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text("Lo que cuesta aplazar")
                .titleFont(.title2)
                .foregroundStyle(Palette.label)
            HStack(alignment: .top) {
                CardFigure(title: "Deuda con intereses", value: summary.revolvingBalance,
                           detail: "TIN \(CardText.percent(summary.terms.revolvingRate))")
                CardFigure(title: "Intereses en estos cargos", value: summary.interestInPayments,
                           detail: "\(summary.payments.count) meses")
            }
            if let payoff = summary.payoff {
                Text("Sin compras nuevas, terminarías de pagar en \(payoff.months) \(payoff.months == 1 ? "mes" : "meses") y pagarías \(payoff.interest.formatted()) de intereses. Pagando todo a fin de mes no pagarías ninguno.")
                    .font(Typography.subheadline)
                    .foregroundStyle(Palette.label)
            } else if summary.revolvingBalance.minor > 0 {
                Text("La cuota no llega a cubrir los intereses: la deuda no baja. Sube la cuota o paga todo a fin de mes.")
                    .font(Typography.subheadline)
                    .foregroundStyle(Palette.negativeText)
            }
        }
    }

    private func installmentsCard(_ summary: CreditCardSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            HStack {
                Text("Compras a plazos")
                    .titleFont(.title2)
                    .foregroundStyle(Palette.label)
                Spacer()
                Button("Aplazar", systemImage: "plus") { deferring = true }
                    .disabled(cards.deferrable(in: account).isEmpty)
            }
            let plans = cards.installments.filter { $0.accountId == account.id }
            if !plans.isEmpty, cards.deferrable(in: account).isEmpty {
                Text("Para aplazar otra compra tiene que ser de 50 € o más y del extracto abierto.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
            }
            if plans.isEmpty {
                EmptyHint(text: "Las compras de 50 € o más del extracto abierto se pueden pagar en 3, 6, 9 o 12 meses al \(CardText.percent(summary.terms.installmentRate)) TIN. La cuota se suma a cada cargo.")
            }
            ForEach(plans) { plan in
                if let movement = cards.movements(of: account).first(where: { $0.id == plan.movementId }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(MovementText.display(movement.description))
                                .font(Typography.subheadlineEmphasis)
                                .foregroundStyle(Palette.label)
                            Text("\((-movement.amount).formatted()) en \(plan.months) meses · \(movement.bookedOn.shortText)")
                                .font(Typography.footnote)
                                .foregroundStyle(Palette.labelSecondary)
                        }
                        Spacer()
                        Text("\(CardInstallment.payment(principal: -movement.amount, months: plan.months, rate: plan.rate).formatted())/mes")
                            .font(Typography.subheadlineEmphasis.monospacedDigit())
                            .foregroundStyle(Palette.label)
                    }
                    .contextMenu {
                        Button("Quitar el aplazado", role: .destructive) { removingPlan = plan }
                    }
                }
            }
        }
    }

    private func payFrom(_ summary: CreditCardSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            if let id = summary.terms.payFromAccountId, let from = finance.account(id) {
                let balance = finance.balance(of: from)
                CardFigure(title: "Se paga desde \(from.name)", value: balance, detail: "saldo actual")
                if let next = summary.next, balance < next.amount {
                    Label("No llega para el próximo cargo de \(next.amount.formatted()).", systemImage: "exclamationmark.circle")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.negativeText)
                }
            } else {
                EmptyHint(text: "Elige en Condiciones la cuenta desde la que se paga la tarjeta para saber si hay saldo.")
            }
            Button("Apuntar el pago de la tarjeta") { recordingPayment = true }
                .buttonStyle(SecondaryButtonStyle())
            Text("El pago se apunta como transferencia de la cuenta a la tarjeta, así el gasto no cuenta dos veces.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
        }
    }
}

extension CardText {
    static func percent(_ value: Decimal) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "es_ES")))) %"
    }

    static func delay(_ terms: CreditCardTerms) -> String {
        switch terms.paymentDelayMonths {
        case 0: "el día \(terms.paymentDay) de ese mes"
        case 1: "el día \(terms.paymentDay) del mes siguiente"
        default: "el día \(terms.paymentDay), \(terms.paymentDelayMonths) meses después"
        }
    }
}
