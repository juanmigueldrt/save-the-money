import SwiftUI
import STMCore
import STMUI

/// Apunta el pago de la tarjeta como una transferencia: sale de la cuenta de pago y entra en la tarjeta.
struct CardPaymentFormView: View {
    let account: Account

    @Environment(CreditCardModel.self) private var cards
    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var day = Date()
    @State private var from: UUID?
    @State private var error: String?
    @State private var isWorking = false
    /// Uno por formulario: si «Apuntar» se repite tras un fallo de red, el pago no se guarda dos veces.
    @State private var transferId = UUID()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Importe", text: $amount)
                        .decimalInput()
                    DatePicker("Día", selection: $day, displayedComponents: .date)
                    Picker("Desde", selection: $from) {
                        Text("Elige una cuenta").tag(UUID?.none)
                        ForEach(finance.activeAccounts.filter { $0.id != account.id && !$0.kind.isLiability }) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                } footer: {
                    Text("Se apuntan dos movimientos de transferencia: la salida de la cuenta y la entrada en la tarjeta.")
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle("Pago de \(account.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apuntar") { Task { await save() } }.disabled(isWorking || from == nil)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .onAppear {
            let summary = cards.summary(for: account)
            from = summary?.terms.payFromAccountId
            if let next = summary?.next, next.amount.minor > 0 {
                amount = next.amount.plainText
                if next.due <= CalendarDay() { day = next.due.date() }
            }
        }
    }

    private func save() async {
        guard let money = Money(entered: amount), money.minor > 0 else { error = "El importe no es válido."; return }
        guard let source = finance.accounts.first(where: { $0.id == from }) else {
            error = "Elige la cuenta desde la que pagas."
            return
        }
        isWorking = true
        defer { isWorking = false }
        let paid = await finance.transfer(id: transferId, from: source, to: account, amount: money, on: CalendarDay(day),
                                          description: "Pago de \(account.name)", toDescription: "Pago de la tarjeta")
        guard paid else { error = finance.error; return }
        dismiss()
    }
}
