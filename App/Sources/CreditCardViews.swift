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
                        EmptyHint(text: "Añade tu tarjeta de crédito y sus condiciones (límite, día del extracto y forma de pago) para saber cuánto te cobrarán cada mes.")
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
}

/// Detalle de una tarjeta: calendario de cargos, coste del pago aplazado y compras a plazos.
struct CreditCardDetailView: View {
    let account: Account

    @Environment(CreditCardModel.self) private var cards
    @Environment(FinanceModel.self) private var finance
    @State private var editingTerms = false
    @State private var deferring = false
    @State private var recordingPayment = false

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
                ErrorText(message: cards.error)
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
                            Text(movement.description)
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
                        Button("Quitar el aplazado", role: .destructive) { Task { await cards.removeInstallment(plan) } }
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
    @State private var installmentRate = "14"
    @State private var payFrom: UUID?
    @State private var reminds = true
    @State private var remindDays = 2
    @State private var alerts = true
    @State private var alertPercent = 80
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }.disabled(isWorking)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 520)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let terms = cards.terms[account.id] else { return }
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
        guard let limitMoney = Money(parsing: limit), limitMoney.minor > 0 else { error = "El límite no es un importe válido."; return }
        guard let revolving = Decimal(parsing: revolvingRate), let installment = Decimal(parsing: installmentRate),
              let percent = Decimal(parsing: minPercent) else { error = "Revisa los intereses y el pago mínimo."; return }
        guard let minimum = Money(parsing: minAmount.isEmpty ? "0" : minAmount) else { error = "El pago mínimo no es un importe válido."; return }
        var fixedMoney: Money?
        if mode == .fixed {
            guard let value = Money(parsing: fixed), value.minor > 0 else { error = "La cuota no es un importe válido."; return }
            fixedMoney = value
        }
        let terms = CreditCardTerms(
            accountId: account.id, householdId: account.householdId, creditLimit: limitMoney, statementDay: statementDay,
            paymentDay: paymentDay, paymentDelayMonths: delay, paymentMode: mode, fixedPayment: fixedMoney,
            minPaymentPercent: percent, minPayment: minimum, revolvingRate: revolving, installmentRate: installment,
            payFromAccountId: payFrom, remindDaysBefore: reminds ? remindDays : nil, alertPercent: alerts ? alertPercent : nil)
        if let issue = terms.issue { error = issue; return }
        isWorking = true
        defer { isWorking = false }
        if await cards.save(terms) { dismiss() } else { error = cards.error }
    }
}

extension CardText {
    /// "14" o "21,5" para los campos de texto.
    static func plain(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "es_ES")))
    }
}

/// Elegir una compra del extracto abierto y en cuántos meses pagarla.
struct DeferPurchaseView: View {
    let account: Account

    @Environment(CreditCardModel.self) private var cards
    @Environment(\.dismiss) private var dismiss
    @State private var movementId: UUID?
    @State private var months = 3
    @State private var error: String?

    private var candidates: [Movement] { cards.deferrable(in: account) }
    private var rate: Decimal { cards.terms[account.id]?.installmentRate ?? 14 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Compra", selection: $movementId) {
                        Text("Elige una compra").tag(UUID?.none)
                        ForEach(candidates) { movement in
                            Text("\(movement.description) · \((-movement.amount).formatted())").tag(Optional(movement.id))
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
                    Button("Aplazar") { Task { await save() } }.disabled(movementId == nil)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 360)
    }

    private func save() async {
        guard let movement = candidates.first(where: { $0.id == movementId }) else { return }
        if await cards.deferPurchase(movement, months: months, in: account) { dismiss() } else { error = cards.error }
    }
}

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
        guard let money = Money(parsing: amount), money.minor > 0 else { error = "El importe no es válido."; return }
        guard let from else { error = "Elige la cuenta desde la que pagas."; return }
        let transfer = finance.categories(for: .transfer).first?.id
        let date = CalendarDay(day)
        isWorking = true
        defer { isWorking = false }
        let out = MovementDraft(accountId: from, categoryId: transfer, bookedOn: date, amount: -money,
                                description: "Pago de \(account.name)")
        let inbound = MovementDraft(accountId: account.id, categoryId: transfer, bookedOn: date, amount: money,
                                    description: "Pago de la tarjeta")
        guard await finance.add(out) else { error = finance.error; return }
        guard await finance.add(inbound) else { error = finance.error; return }
        dismiss()
    }
}
