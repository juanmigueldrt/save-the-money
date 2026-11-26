import SwiftUI
import Charts
import STMCore
import STMUI

/// Apuntar o editar un movimiento.
struct MovementFormView: View {
    let movement: Movement?
    /// Cuenta preseleccionada al crear desde el detalle de una cuenta.
    let accountId: UUID?

    @Environment(FinanceModel.self) private var finance
    @Environment(CreditCardModel.self) private var cards
    @Environment(PlanningModel.self) private var planning
    @Environment(\.dismiss) private var dismiss
    /// Uno por formulario: si «Guardar» se repite tras un fallo de red, el movimiento no se apunta dos veces.
    @State private var newMovementId = UUID()
    @State private var isExpense = true
    @State private var amount = ""
    @State private var concept = ""
    /// Sólo al apuntar un gasto nuevo con tarjeta: normal, a plazos o recurrente.
    @State private var purchaseKind = CardPurchaseKind.normal
    @State private var months = 3
    @State private var recurrence = Recurrence.monthly
    @State private var date = Date()
    @State private var selectedAccount: UUID?
    @State private var selectedCategory: UUID?
    /// Categoría puesta sola por el comercio reconocido (se cambia si el concepto cambia).
    @State private var autoCategory: UUID?
    @State private var notes = ""
    @State private var payee = ""
    @State private var tagsText = ""
    @State private var excluded = false
    @State private var reviewed = false
    @State private var error: String?
    @State private var isWorking = false
    /// Tras cambiar la categoría: otros con el mismo concepto a los que ofrecer el mismo cambio.
    @State private var similar: [Movement] = []
    @State private var confirmingTransferDelete = false

    private var kind: CategoryKind { isExpense ? .expense : .income }

    /// La tarjeta elegida, si se está apuntando un gasto nuevo en una tarjeta de crédito.
    private var newCardPurchase: Account? {
        guard movement == nil, isExpense, let id = selectedAccount, let account = finance.account(id),
              account.kind == .creditCard else { return nil }
        return account
    }

    private var payeeSuggestions: [String] {
        let text = payee.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        return finance.knownPayees.filter { $0.localizedCaseInsensitiveContains(text) && $0 != text }.prefix(3).map { $0 }
    }

    private var tagSuggestions: [String] {
        let current = Set(MovementTags.normalize(tagsText))
        return finance.knownTags.filter { !current.contains($0) }.prefix(6).map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $isExpense) {
                        Text("Gasto").tag(true)
                        Text("Ingreso").tag(false)
                    }
                    .pickerStyle(.segmented)
                    // En una transferencia la salida es siempre un gasto y la entrada un ingreso.
                    .disabled(movement?.transferId != nil)
                    AmountField("Importe, p. ej. 12,50 o 25+7,40", text: $amount)
                    TextField("Concepto", text: $concept)
                        .conceptInput()
                    DatePicker("Fecha", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "es_ES"))
                } footer: {
                    if movement?.transferId != nil { Text(TransferDraft.editNote) }
                }
                Section {
                    Picker("Cuenta", selection: $selectedAccount) {
                        ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Categoría", selection: $selectedCategory) {
                        Text("Sin categoría").tag(UUID?.none)
                        ForEach(finance.categories(for: kind)) { Text($0.name).tag(Optional($0.id)) }
                        ForEach(finance.categories(for: .transfer)) { Text($0.name).tag(Optional($0.id)) }
                    }
                    TextField("Notas (opcional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
                if let card = newCardPurchase {
                    cardPurchaseSection(card)
                }
                Section {
                    TextField("Beneficiario (opcional)", text: $payee)
                    ForEach(payeeSuggestions, id: \.self) { suggestion in
                        Button(suggestion) { payee = suggestion }
                            .font(Typography.subheadline)
                    }
                    TextField("Etiquetas, p. ej. viaje, regalos", text: $tagsText)
                        .autocorrectionDisabled()
                    if !tagSuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Spacing.s8) {
                                ForEach(tagSuggestions, id: \.self) { tag in
                                    Button("#" + tag) {
                                        let current = MovementTags.normalize(tagsText)
                                        tagsText = MovementTags.text(current + [tag])
                                    }
                                    .buttonStyle(.bordered)
                                    .font(Typography.footnote)
                                    .accessibilityLabel("Añadir etiqueta \(tag)")
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Las etiquetas sirven para juntar gastos de distintas categorías, como un viaje. Sepáralas con comas.")
                }
                Section {
                    if movement != nil {
                        Toggle("Revisado", isOn: $reviewed)
                    }
                    Toggle("Excluir del presupuesto e informes", isOn: $excluded)
                } footer: {
                    Text("Un movimiento excluido sigue contando en el saldo de la cuenta, pero no en el presupuesto, los informes ni el flujo de caja.")
                }
                if movement != nil {
                    Section {
                        if movement?.transferId != nil {
                            Button("Borrar transferencia", role: .destructive) { confirmingTransferDelete = true }
                        } else {
                            Button("Borrar movimiento", role: .destructive) { Task { await delete() } }
                        }
                    }
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle(movement == nil ? "Nuevo movimiento" : "Editar movimiento")
            .formToolbar(isWorking: isWorking, cancel: { dismiss() }, save: { await save() })
            .onChange(of: concept) { _, newValue in suggestCategory(for: newValue) }
            .confirmationDialog("¿Borrar la transferencia?", isPresented: $confirmingTransferDelete, titleVisibility: .visible) {
                Button("Borrar los dos movimientos", role: .destructive) { Task { await delete() } }
            } message: {
                Text(TransferDraft.deleteWarning)
            }
            .confirmationDialog(similar.count == 1 ? "Hay 1 movimiento con el mismo concepto"
                                                   : "Hay \(similar.count) movimientos con el mismo concepto",
                                isPresented: Binding(get: { !similar.isEmpty }, set: { if !$0 { similar = []; dismiss() } }),
                                titleVisibility: .visible) {
                Button("Ponerles la misma categoría") {
                    let category = selectedCategory
                    let changed = similar.map { movement -> Movement in
                        var copy = movement
                        copy.categoryId = category
                        return copy
                    }
                    Task {
                        await finance.update(changed)
                        similar = []
                        dismiss()
                    }
                }
                Button("Sólo este", role: .cancel) { similar = []; dismiss() }
            } message: {
                Text("¿Quieres cambiar también su categoría a «\(finance.category(selectedCategory)?.name ?? "Sin categoría")»?")
            }
            .onChange(of: isExpense) { _, _ in
                if let current = finance.category(selectedCategory), current.kind != .transfer, current.kind != kind {
                    selectedCategory = nil
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
        .onAppear(perform: fill)
    }

    @ViewBuilder
    private func cardPurchaseSection(_ card: Account) -> some View {
        Section {
            Picker("Tipo de compra", selection: $purchaseKind) {
                ForEach(CardPurchaseKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            switch purchaseKind {
            case .normal:
                EmptyView()
            case .installments:
                Stepper("\(months) plazos", value: $months, in: CardInstallment.allowedMonths)
                HStack(spacing: Spacing.s8) {
                    ForEach(CardInstallment.commonMonths, id: \.self) { option in
                        Button("\(option)") { months = option }
                            .buttonStyle(.bordered)
                            .tint(option == months ? Palette.accent : nil)
                            .accessibilityLabel("\(option) plazos")
                    }
                }
                if let parsed = Money(entered: amount), parsed.minor != 0 {
                    let principal = Money(minor: abs(parsed.minor))
                    let rate = cards.terms[card.id]?.installmentRate ?? CreditCardTerms.defaultInstallmentRate
                    let quota = CardInstallment.payment(principal: principal, months: months, rate: rate)
                    let total = Money(minor: quota.minor * months)
                    LabeledContent("Cuota al mes", value: quota.formatted())
                    LabeledContent("Total", value: total.formatted())
                    LabeledContent("Intereses (\(CardText.percent(rate)) TIN)", value: (total - principal).formatted())
                }
            case .recurring:
                Picker("Se repite", selection: $recurrence) {
                    ForEach(Recurrence.common, id: \.self) { Text($0.title).tag($0) }
                }
            }
        } footer: {
            switch purchaseKind {
            case .normal:
                Text("Se paga entero en el próximo cargo de la tarjeta.")
            case .installments:
                if let parsed = Money(entered: amount), abs(parsed.minor) < CardInstallment.usualMinimum.minor {
                    Text("Muchos contratos sólo aplazan compras de 50 € o más. La cuota se suma a cada cargo de la tarjeta.")
                } else {
                    Text("La cuota se suma a cada cargo de la tarjeta.")
                }
            case .recurring:
                Text("Además se crea un pago fijo con esta tarjeta. Los próximos cargos saldrán como pendientes de confirmar.")
            }
        }
    }

    private func fill() {
        selectedAccount = accountId ?? finance.defaultAccount?.id
        guard let movement else { return }
        isExpense = movement.isExpense
        amount = Money(minor: abs(movement.amount.minor)).plainText
        concept = movement.description
        date = movement.bookedOn.date()
        selectedAccount = movement.accountId
        selectedCategory = movement.categoryId
        notes = movement.notes ?? ""
        payee = movement.payee ?? ""
        tagsText = MovementTags.text(movement.tags)
        excluded = movement.excluded
        reviewed = movement.isReviewed
    }

    /// Si el concepto es de un comercio conocido y no hay categoría elegida a mano, la pone sola.
    private func suggestCategory(for text: String) {
        if selectedCategory != nil, selectedCategory != autoCategory { return }
        let suggested = MerchantDirectory.suggestedCategory(for: text, isExpense: isExpense, in: finance.categories,
                                                            learned: CategoryLearner(movements: finance.recent))
        selectedCategory = suggested?.id ?? (selectedCategory == autoCategory ? nil : selectedCategory)
        autoCategory = suggested?.id
    }

    private func save() async {
        guard let parsed = Money(entered: amount), parsed.minor != 0 else {
            error = "Escribe un importe, por ejemplo 12,50."
            return
        }
        guard let accountId = selectedAccount else { error = "Elige una cuenta."; return }
        let signed = Money(minor: isExpense ? -abs(parsed.minor) : abs(parsed.minor))
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = MovementDraft(id: newMovementId, accountId: accountId, categoryId: selectedCategory, bookedOn: CalendarDay(date),
                                  amount: signed, description: concept,
                                  notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                                  excluded: excluded, payee: Payee.clean(payee), tags: MovementTags.normalize(tagsText))
        if let issue = draft.issue { error = issue; return }

        isWorking = true
        defer { isWorking = false }
        let ok: Bool
        if let movement {
            var updated = movement
            updated.accountId = draft.accountId
            updated.categoryId = draft.categoryId
            updated.bookedOn = draft.bookedOn
            updated.amount = draft.amount
            updated.description = draft.description
            updated.notes = draft.notes
            updated.excluded = draft.excluded
            updated.payee = draft.payee
            updated.tags = draft.tags
            updated.reviewedAt = reviewed ? (movement.reviewedAt ?? Date()) : nil
            ok = await finance.update(updated)
            if ok, movement.categoryId != draft.categoryId {
                let matches = SimilarMovements.matches(for: updated, in: finance.recent, categoryId: draft.categoryId)
                if !matches.isEmpty {
                    similar = matches
                    return
                }
            }
        } else if let card = newCardPurchase, purchaseKind != .normal {
            guard let created = await finance.addMovement(draft) else { error = finance.error; return }
            switch purchaseKind {
            case .installments:
                ok = await cards.deferPurchase(created, months: months, in: card)
                if !ok { error = "El gasto se ha guardado, pero no se ha podido aplazar: \(cards.error ?? "inténtalo desde la tarjeta.")"; return }
            case .recurring:
                ok = await planning.save(RecurringSeries.fromPurchase(created, recurrence: recurrence))
                if !ok { error = "El gasto se ha guardado, pero no se ha podido crear el pago fijo: \(planning.error ?? "créalo en Pagos fijos.")"; return }
            case .normal:
                ok = true
            }
        } else {
            ok = await finance.add(draft)
        }
        if ok { dismiss() } else { error = finance.error }
    }

    private func delete() async {
        guard let movement else { return }
        if await finance.delete(movement) { dismiss() } else { error = finance.error }
    }
}
