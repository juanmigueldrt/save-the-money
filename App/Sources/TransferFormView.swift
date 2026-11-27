import SwiftUI
import Charts
import STMCore
import STMUI

/// Transferencia entre dos cuentas propias, como en Android.
struct TransferFormView: View {
    /// Cuenta de origen preseleccionada.
    let fromId: UUID?

    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var from: UUID?
    @State private var to: UUID?
    @State private var amount = ""
    @State private var concept = ""
    @State private var date = Date()
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Desde", selection: $from) {
                        ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Hacia", selection: $to) {
                        ForEach(finance.activeAccounts.filter { $0.id != from }) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section {
                    AmountField(String(localized: "Importe, p. ej. 200"), text: $amount)
                    TextField("Concepto (opcional)", text: $concept)
                    DatePicker("Fecha", selection: $date, displayedComponents: .date)
                        .environment(\.locale, AppRegion.locale)
                } footer: {
                    Text("Se apuntan dos movimientos con la categoría de transferencia. No cuentan como gasto ni como ingreso.")
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle("Transferencia")
            .formToolbar(isWorking: isWorking, cancel: { dismiss() }, save: { await save() })
            .onAppear {
                if from == nil { from = fromId ?? finance.defaultAccount?.id }
                if to == nil { to = finance.activeAccounts.first { $0.id != from }?.id }
            }
        }
    }

    private func save() async {
        error = nil
        guard let source = from.flatMap(finance.account), let target = to.flatMap(finance.account), source.id != target.id else {
            error = String(localized: "Elige dos cuentas distintas.")
            return
        }
        guard let money = Money(entered: amount), money.minor > 0 else {
            error = String(localized: "Escribe un importe mayor que cero.")
            return
        }
        isWorking = true
        defer { isWorking = false }
        if await finance.transfer(from: source, to: target, amount: money, on: CalendarDay(date), description: concept) {
            dismiss()
        } else {
            error = finance.error
        }
    }
}
