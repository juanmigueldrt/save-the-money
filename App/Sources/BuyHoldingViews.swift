import SwiftUI
import Charts
import STMCore
import STMUI

/// "Comprar activo": por importe o por participaciones, con la comisión y el total.
/// Si se elige una cuenta, también apunta el gasto en ella; y puede crear un plan mensual.
struct BuyCard: View {
    let holding: Holding

    enum Mode: String, CaseIterable { case amount, quantity }

    @Environment(InvestmentModel.self) private var investments
    @Environment(FinanceModel.self) private var finance
    @State private var mode: Mode = .amount
    @State private var text = ""
    @State private var accountId: UUID?
    @State private var tradedOn = Date()
    @State private var repeatMonthly = false
    /// Uno por compra: reintentar tras un fallo no la duplica. Se cambia al guardarla.
    @State private var tradeId = UUID()
    @State private var error: String?
    @State private var done: String?
    @State private var isWorking = false

    private var quote: BuyQuote? {
        switch mode {
        case .amount:
            Money(entered: text).flatMap { BuyQuote.byAmount($0, price: holding.price, feeRate: holding.feeRate) }
        case .quantity:
            Decimal(parsing: text).flatMap { BuyQuote.byQuantity($0, price: holding.price, feeRate: holding.feeRate) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text("Comprar")
                .titleFont(.title2)
                .foregroundStyle(Palette.label)
            if holding.price <= 0 {
                EmptyHint(text: String(localized: "Apunta primero el precio de hoy para calcular la compra."))
            } else {
                CapsuleSegmented(String(localized: "Comprar por"), selection: $mode, options: Mode.allCases) {
                    $0 == .amount ? String(localized: "Importe") : String(localized: "Participaciones")
                }
                LabeledField(label: mode == .amount ? String(localized: "Importe") : String(localized: "Participaciones")) {
                    TextField(mode == .amount ? "500,00" : "10", text: $text)
                        .decimalInput()
                }
                if let quote {
                    VStack(spacing: Spacing.s8) {
                        QuoteLine(title: String(localized: "Participaciones"), text: InvestmentText.quantity(quote.quantity))
                        QuoteLine(title: String(localized: "Comisión (\(InvestmentText.rate(holding.feeRate)))"), text: quote.fee.formatted())
                        QuoteLine(title: String(localized: "Total"), text: quote.total.formatted(), highlight: true)
                    }
                } else if mode == .quantity, !text.trimmingCharacters(in: .whitespaces).isEmpty, Decimal(parsing: text) == nil {
                    ErrorText(message: String(localized: "Escribe las participaciones con coma para los decimales, p. ej. 0,125."))
                }
                Picker("Desde", selection: $accountId) {
                    Text("No apuntar en ninguna cuenta").tag(UUID?.none)
                    ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                }
                DatePicker("Fecha", selection: $tradedOn, in: ...Date(), displayedComponents: .date)
                Toggle("Repetir cada mes", isOn: $repeatMonthly)
                Button(quote.map { "Comprar \($0.total.formatted())" } ?? "Comprar") { Task { await buy() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(quote == nil || isWorking)
                if let done {
                    Text(done)
                        .font(Typography.subheadline)
                        .foregroundStyle(Palette.positiveText)
                }
                ErrorText(message: error)
            }
        }
        .card()
        .onAppear { if accountId == nil { accountId = holding.accountId } }
    }

    private func buy() async {
        guard let quote else { return }
        error = nil
        done = nil
        isWorking = true
        defer { isWorking = false }
        let day = CalendarDay(tradedOn)
        let trade = quote.trade(for: holding, price: holding.price, on: day, id: tradeId)
        guard await investments.buy(trade, of: holding, paying: quote.total, from: accountId, finance: finance) else {
            error = investments.error
            return
        }
        let monthly = repeatMonthly
        tradeId = UUID()
        text = ""
        repeatMonthly = false
        done = String(localized: "Compra apuntada: \(InvestmentText.quantity(quote.quantity)) participaciones.")
        // El plan va aparte: la compra ya está guardada entera, y si el plan falla se dice solo eso.
        if monthly {
            // Con el id de la compra (uno por cada vez que se pulsa «Comprar»): el plan no se crea dos veces.
            let plan = InvestmentPlan(id: trade.id, householdId: holding.householdId, holdingId: holding.id, accountId: accountId,
                                      amount: quote.amount, startsOn: day.adding(months: 1))
            if !(await investments.save(plan)) {
                error = String(localized: "La compra está apuntada, pero no se pudo crear la aportación mensual. Créala en Aportaciones automáticas.")
            }
        }
    }
}

/// Desde la cartera: elegir qué activo comprar.
struct BuyPickerView: View {
    @Environment(InvestmentModel.self) private var investments
    @Environment(\.dismiss) private var dismiss
    @State private var holdingId: UUID?
    @State private var addingHolding = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s16) {
                    Picker("Activo", selection: $holdingId) {
                        Text("Elige uno").tag(UUID?.none)
                        ForEach(investments.activeHoldings) { Text($0.trimmedName).tag(Optional($0.id)) }
                    }
                    .card()
                    if let holdingId, let holding = investments.holding(holdingId) {
                        BuyCard(holding: holding).id(holding.id)
                    }
                    Button("Añadir otro activo") { addingHolding = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .pageLayout()
            }
            .background(Palette.bgGrouped)
            .navigationTitle("Comprar activo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
            .sheet(isPresented: $addingHolding) { HoldingFormView(holding: nil) }
        }
        .frame(minWidth: 420, minHeight: 560)
        .onAppear { holdingId = holdingId ?? investments.activeHoldings.first?.id }
    }
}

/// Una línea del cálculo de la compra: título a la izquierda y valor a la derecha.
private struct QuoteLine: View {
    let title: String
    let text: String
    var highlight = false

    var body: some View {
        HStack {
            Text(title)
                .font(highlight ? Typography.headline : Typography.subheadline)
                .foregroundStyle(highlight ? Palette.label : Palette.labelSecondary)
            Spacer()
            Text(text)
                .font(highlight ? Typography.headline.monospacedDigit() : Typography.subheadlineEmphasis.monospacedDigit())
                .foregroundStyle(Palette.label)
        }
        .accessibilityElement(children: .combine)
    }
}
