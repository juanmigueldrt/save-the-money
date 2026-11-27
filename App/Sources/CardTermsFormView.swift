import SwiftUI
import STMCore
import STMUI

/// Condiciones de la tarjeta, con los valores del contrato.
struct CardTermsFormView: View {
    let account: Account

    @Environment(CreditCardModel.self) private var cards
    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var limit = ""
    @State private var statementDay = 1
    @State private var paymentDay = 1
    @State private var delay = 1
    @State private var mode: CardPaymentMode = .full
    @State private var fixed = ""
    @State private var minPercent = "3"
    @State private var minAmount = "15"
    @State private var revolvingRate = "20"
    @State private var installmentRate = CardText.plain(CreditCardTerms.defaultInstallmentRate)
    @State private var payFrom: UUID?
    @State private var reminds = true
    @State private var remindDays = 2
    @State private var alerts = true
    @State private var alertPercent = 80
    /// La versión de las condiciones que se cargó al abrir el formulario (nil: aún no había): se guarda sobre ella.
    @State private var seenVersion: String?
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Límite, p. ej. 3.000", text: $limit)
                        .decimalInput()
                    Stepper("Extracto el día \(statementDay)", value: $statementDay, in: 1...28)
                    Stepper("Cargo el día \(paymentDay)", value: $paymentDay, in: 1...28)
                    Picker("Se cobra", selection: $delay) {
                        Text("El mismo mes del extracto").tag(0)
                        Text("El mes siguiente").tag(1)
                        Text("Dos meses después").tag(2)
                    }
                } footer: {
                    Text("Míralo en tu contrato. Por ejemplo: extracto el día 1 y cargo el día 1 del mes siguiente quiere decir que lo gastado en enero se cobra el 1 de marzo.")
                }
                Section {
                    Picker("Forma de pago", selection: $mode) {
                        ForEach(CardPaymentMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if mode == .fixed {
                        TextField("Cuota al mes, p. ej. 200", text: $fixed)
                            .decimalInput()
                    }
                    if mode.isRevolving {
                        TextField("Interés (TIN %)", text: $revolvingRate)
                            .decimalInput()
                        TextField("Pago mínimo: % de la deuda", text: $minPercent)
                            .decimalInput()
                        TextField("Pago mínimo: al menos (€)", text: $minAmount)
                            .decimalInput()
                    }
                } footer: {
                    Text(mode.detail + (mode.isRevolving ? " El pago mínimo es el % de la deuda más los intereses, y nunca menos del importe mínimo." : ""))
                }
                Section {
                    TextField("Interés de las compras a plazos (TIN %)", text: $installmentRate)
                        .decimalInput()
                } footer: {
                    Text("Se usa al aplazar una compra en 3, 6, 9 o 12 meses.")
                }
                Section {
                    Picker("Se paga desde", selection: $payFrom) {
                        Text("Sin elegir").tag(UUID?.none)
                        ForEach(finance.activeAccounts.filter { $0.id != account.id && !$0.kind.isLiability }) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                    Toggle("Avisarme antes del cargo", isOn: $reminds)
                    if reminds {
                        Stepper(remindDays == 0 ? "El mismo día" : remindDays == 1 ? "1 día antes" : "\(remindDays) días antes",
                                value: $remindDays, in: 0...14)
                    }
                    Toggle("Avisarme al acercarme al límite", isOn: $alerts)
                    if alerts {
                        Stepper("Al pasar del \(alertPercent) %", value: $alertPercent, in: 50...100, step: 5)
                    }
                } footer: {
                    Text("Los avisos los lanza este dispositivo. Puedes apagar todos los avisos en Más opciones.")
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle("Condiciones de \(account.name)")
            .formToolbar(isWorking: isWorking, cancel: { dismiss() }, save: { await save() })
        }
        .frame(minWidth: 380, minHeight: 520)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let terms = cards.terms[account.id] else { return }
        seenVersion = terms.updatedAt
        limit = terms.creditLimit.plainText
        statementDay = terms.statementDay
        paymentDay = terms.paymentDay
        delay = terms.paymentDelayMonths
        mode = terms.paymentMode
        fixed = terms.fixedPayment?.plainText ?? ""
        minPercent = CardText.plain(terms.minPaymentPercent)
        minAmount = terms.minPayment.plainText
        revolvingRate = CardText.plain(terms.revolvingRate)
        installmentRate = CardText.plain(terms.installmentRate)
        payFrom = terms.payFromAccountId
        reminds = terms.remindDaysBefore != nil
        remindDays = terms.remindDaysBefore ?? 2
        alerts = terms.alertPercent != nil
        alertPercent = terms.alertPercent ?? 80
    }

    private func save() async {
        guard let limitMoney = Money(entered: limit), limitMoney.minor > 0 else { error = "El límite no es un importe válido."; return }
        guard let revolving = Decimal(parsing: revolvingRate, maxFractionDigits: 2), let installment = Decimal(parsing: installmentRate, maxFractionDigits: 2),
              let percent = Decimal(parsing: minPercent, maxFractionDigits: 2) else { error = "Revisa los intereses y el pago mínimo."; return }
        guard let minimum = Money(entered: minAmount.isEmpty ? "0" : minAmount) else { error = "El pago mínimo no es un importe válido."; return }
        var fixedMoney: Money?
        if mode == .fixed {
            guard let value = Money(entered: fixed), value.minor > 0 else { error = "La cuota no es un importe válido."; return }
            fixedMoney = value
        }
        let terms = CreditCardTerms(
            accountId: account.id, householdId: account.householdId, creditLimit: limitMoney, statementDay: statementDay,
            paymentDay: paymentDay, paymentDelayMonths: delay, paymentMode: mode, fixedPayment: fixedMoney,
            minPaymentPercent: percent, minPayment: minimum, revolvingRate: revolving, installmentRate: installment,
            payFromAccountId: payFrom, remindDaysBefore: reminds ? remindDays : nil, alertPercent: alerts ? alertPercent : nil,
            updatedAt: seenVersion)
        if let issue = terms.issue { error = issue.text; return }
        isWorking = true
        defer { isWorking = false }
        if await cards.save(terms) { dismiss() } else { error = cards.error }
    }
}

extension CardText {
    /// "14" o "21,5" para los campos de texto.
    static func plain(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(AppRegion.locale))
    }
}
