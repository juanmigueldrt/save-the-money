import SwiftUI
import STMCore
import STMUI

/// Elegir una compra del extracto abierto y en cuántos meses pagarla.
struct DeferPurchaseView: View {
    let account: Account

    @Environment(CreditCardModel.self) private var cards
    @Environment(\.dismiss) private var dismiss
    @State private var movementId: UUID?
    @State private var months = 3
    @State private var error: String?
    @State private var isWorking = false

    private var candidates: [Movement] { cards.deferrable(in: account) }
    private var rate: Decimal { cards.terms[account.id]?.installmentRate ?? CreditCardTerms.defaultInstallmentRate }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Compra", selection: $movementId) {
                        Text("Elige una compra").tag(UUID?.none)
                        ForEach(candidates) { movement in
                            Text("\(MovementText.display(movement.description)) · \((-movement.amount).formatted())").tag(Optional(movement.id))
                        }
                    }
                    Picker("Plazo", selection: $months) {
                        ForEach(CardInstallment.commonMonths, id: \.self) { Text("\($0) meses").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Sólo compras de 50 € o más del extracto que aún está abierto, como en la mayoría de contratos.")
                }
                if let movement = candidates.first(where: { $0.id == movementId }) {
                    let quota = CardInstallment.payment(principal: -movement.amount, months: months, rate: rate)
                    let total = Money(minor: quota.minor * months)
                    Section("Lo que pagarás") {
                        LabeledContent("Cuota al mes", value: quota.formatted())
                        LabeledContent("Total", value: total.formatted())
                        LabeledContent("Intereses", value: (total + movement.amount).formatted())
                    }
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle("Aplazar una compra")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplazar") { Task { await save() } }.disabled(movementId == nil || isWorking)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 360)
    }

    private func save() async {
        guard !isWorking, let movement = candidates.first(where: { $0.id == movementId }) else { return }
        isWorking = true
        defer { isWorking = false }
        if await cards.deferPurchase(movement, months: months, in: account) { dismiss() } else { error = cards.error }
    }
}
