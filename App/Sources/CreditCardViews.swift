import SwiftUI
import STMCore
import STMUI

/// Las tarjetas de crédito del hogar con lo que se paga en el próximo cargo de cada una.
struct CreditCardsView: View {
    @Environment(CreditCardModel.self) private var cards
    @Environment(FinanceModel.self) private var finance
    @State private var adding = false
    @State private var configuring: Account?

    private var accounts: [Account] { finance.activeAccounts.filter { $0.kind == .creditCard } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                if accounts.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text("Aún no hay tarjetas")
                            .titleFont(.title2)
                            .foregroundStyle(Palette.label)
                        EmptyHint(text: cards.isLoading ? "Cargando…" : "Añade tu tarjeta de crédito y sus condiciones (límite, día del extracto y forma de pago) para saber cuánto te cobrarán cada mes.")
                        Button("Añadir tarjeta") { adding = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .card()
                } else {
                    if accounts.count > 1, cards.nextPaymentsTotal.minor > 0 {
                        VStack(alignment: .leading, spacing: Spacing.s8) {
                            Eyebrow("Próximos cargos de todas las tarjetas")
                            Text(cards.nextPaymentsTotal.formatted())
                                .titleFont(.largeTitle)
                                .foregroundStyle(Palette.label)
                        }
                        .card()
                    }
                    ForEach(accounts) { account in
                        if let summary = cards.summary(for: account) {
                            NavigationLink { CreditCardDetailView(account: account) } label: {
                                CardOverview(name: account.name, summary: summary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .card()
                        } else {
                            VStack(alignment: .leading, spacing: Spacing.s16) {
                                Label(account.name, systemImage: "creditcard")
                                    .font(Typography.headline)
                                    .foregroundStyle(Palette.label)
                                EmptyHint(text: "Pon el límite, el día del extracto y cómo la pagas para calcular tus cargos.")
                                Button("Configurar tarjeta") { configuring = account }
                                    .buttonStyle(PrimaryButtonStyle())
                            }
                            .card()
                        }
                    }
                }
                ErrorText(message: cards.error)
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Tarjetas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nueva tarjeta", systemImage: "plus") { adding = true }
            }
        }
        .refreshable { await reload() }
        .sheet(isPresented: $adding) { AccountFormView(account: nil, initialKind: .creditCard) }
        .sheet(item: $configuring) { CardTermsFormView(account: $0) }
    }

    private func reload() async {
        await finance.load()
        await cards.load(accounts: finance.accounts, balances: finance.balances, categories: finance.categories)
    }
}

/// Resumen de una tarjeta: próximo cargo, uso del límite y lo gastado en el extracto abierto.
struct CardOverview: View {
    let name: String
    let summary: CreditCardSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            HStack {
                Label(name, systemImage: "creditcard")
                    .font(Typography.headline)
                    .foregroundStyle(Palette.label)
                Spacer()
                Text(summary.terms.paymentMode.title)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
            }
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Eyebrow("Próximo cargo")
                Text((summary.next?.amount ?? .zero).formatted())
                    .titleFont(.largeTitle)
                    .foregroundStyle(Palette.label)
                    .contentTransition(.numericText())
                if let next = summary.next {
                    Text(CardText.due(next))
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                }
            }
            LimitBar(summary: summary)
            HStack(alignment: .top) {
                CardFigure(title: "Gastado en este extracto", value: summary.spentThisCycle,
                           detail: "se cobra el \(summary.terms.paymentDate(forStatement: summary.openStatement).longTitle)")
                CardFigure(title: "Disponible", value: summary.available,
                           detail: "de \(summary.terms.creditLimit.formatted())")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Barra de uso del límite; se pone roja al pasar del aviso.
struct LimitBar: View {
    let summary: CreditCardSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.bgGrouped)
                    Capsule().fill(summary.isOverAlert ? Palette.negative : Palette.accent)
                        .frame(width: max(0, proxy.size.width * min(1, summary.usedFraction)))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            HStack {
                Text("Usado \(summary.used.formatted())")
                Spacer()
                Text("\(Int((summary.usedFraction * 100).rounded())) % del límite")
            }
            .font(Typography.footnote.monospacedDigit())
            .foregroundStyle(summary.isOverAlert ? Palette.negativeText : Palette.labelSecondary)
        }
    }
}

struct CardFigure: View {
    let title: String
    let value: Money
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
            Text(value.formatted())
                .font(Typography.subheadlineEmphasis.monospacedDigit())
                .foregroundStyle(Palette.label)
            Text(detail)
                .font(Typography.caption1)
                .foregroundStyle(Palette.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum CardText {
    static func due(_ payment: CardPayment) -> String {
        let estimate = payment.isEstimate ? " · de momento, puede subir con nuevas compras" : ""
        return "El \(payment.due.longTitle)\(estimate)"
    }

    static func breakdown(_ payment: CardPayment, mode: CardPaymentMode) -> String {
        var parts: [String] = []
        if payment.purchases.minor > 0 {
            parts.append(mode.isRevolving ? "cuota \(payment.purchases.formatted())" : "compras \(payment.purchases.formatted())")
        }
        if payment.installments.minor > 0 { parts.append("aplazados \(payment.installments.formatted())") }
        guard !parts.isEmpty else { return "Sin cargos" }
        let text = parts.joined(separator: " · ")
        // Los intereses ya van dentro de las cuotas: se dicen aparte para que no se sumen dos veces.
        return payment.interest.minor > 0 ? "\(text) (incluye \(payment.interest.formatted()) de intereses)" : text
    }

    /// Aviso de abonos sin categoría: no se sabe si son un pago de la tarjeta o una devolución.
    static func uncategorizedCredits(_ count: Int) -> String {
        let credits = count == 1 ? "Hay 1 abono sin categoría" : "Hay \(count) abonos sin categoría"
        return "\(credits). Sin categoría no bajan los cargos: si es una devolución, ponle la suya; si es un pago de la tarjeta, una de transferencia."
    }

    /// Aviso de aplazados cuya compra no se ha podido cargar: sin ella no se sabe la cuota ni el capital.
    static func unresolvedInstallments(_ count: Int) -> String {
        let plans = count == 1 ? "No se ha podido cargar la compra de 1 aplazado" : "No se han podido cargar las compras de \(count) aplazados"
        return "\(plans). Hasta que se carguen, los cargos y la deuda de la tarjeta no son de fiar: vuelve a abrirla en un rato."
    }

    /// Aviso de que los extractos sin cobrar tienen más movimientos de los que se cargan de una vez.
    static func movementsTruncated(_ limit: Int) -> String {
        "Los extractos sin cobrar tienen \(limit) movimientos o más y puede que no se hayan cargado todos: los cargos y lo gastado pueden salir más bajos de lo que son."
    }
}
