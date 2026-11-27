import SwiftUI
import STMCore
import STMUI

/// Cambiar varios movimientos a la vez: fecha, categoría, cuenta, beneficiario, etiquetas,
/// revisado y excluido. Lo que no se toca se queda como estaba en cada uno.
struct BulkEditView: View {
    let movements: [Movement]
    /// Se llama al guardar bien, para salir del modo «Seleccionar».
    var onDone: () -> Void = {}

    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss

    @State private var changesDate = false
    @State private var date = Date()
    @State private var changesCategory = false
    @State private var categoryId: UUID?
    @State private var changesAccount = false
    @State private var accountId: UUID?
    @State private var changesPayee = false
    @State private var payee = ""
    @State private var addTags = ""
    @State private var removeTags = ""
    @State private var reviewed: Bool?
    @State private var excluded: Bool?
    @State private var error: String?
    @State private var isWorking = false

    private var edit: MovementBulkEdit {
        MovementBulkEdit(bookedOn: changesDate ? CalendarDay(date) : nil,
                         categoryId: changesCategory ? .some(categoryId) : nil,
                         accountId: changesAccount ? accountId : nil,
                         excluded: excluded, reviewed: reviewed,
                         payee: changesPayee ? .some(Payee.clean(payee)) : nil,
                         addTags: MovementTags.normalize(addTags), removeTags: MovementTags.normalize(removeTags))
    }

    private var usedTags: [String] { MovementTags.all(in: movements) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Cambiar la fecha", isOn: $changesDate)
                    if changesDate {
                        DatePicker("Fecha", selection: $date, displayedComponents: .date)
                            .environment(\.locale, AppRegion.locale)
                    }
                    Toggle("Cambiar la categoría", isOn: $changesCategory)
                    if changesCategory {
                        Picker("Categoría", selection: $categoryId) {
                            Text("Sin categoría").tag(UUID?.none)
                            ForEach(finance.categories) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    Toggle("Cambiar la cuenta", isOn: $changesAccount)
                    if changesAccount {
                        Picker("Cuenta", selection: $accountId) {
                            ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    Toggle("Cambiar el beneficiario", isOn: $changesPayee)
                    if changesPayee {
                        TextField("Beneficiario (vacío lo quita)", text: $payee)
                    }
                }
                Section {
                    TextField("Añadir etiquetas, p. ej. viaje", text: $addTags)
                        .autocorrectionDisabled()
                    TextField("Quitar etiquetas", text: $removeTags)
                        .autocorrectionDisabled()
                } header: {
                    Text("Etiquetas")
                } footer: {
                    if !usedTags.isEmpty {
                        Text("Ahora llevan: " + usedTags.map { "#" + $0 }.joined(separator: " "))
                    }
                }
                Section {
                    Picker("Revisado", selection: $reviewed) {
                        Text("No cambiar").tag(Bool?.none)
                        Text("Marcar revisados").tag(Bool?.some(true))
                        Text("Marcar sin revisar").tag(Bool?.some(false))
                    }
                    Picker("Presupuesto e informes", selection: $excluded) {
                        Text("No cambiar").tag(Bool?.none)
                        Text("Excluir").tag(Bool?.some(true))
                        Text("Volver a contar").tag(Bool?.some(false))
                    }
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle(movements.count == 1 ? "Editar 1 movimiento" : "Editar \(movements.count) movimientos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(isWorking || edit.isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 480)
        .onAppear {
            accountId = finance.defaultAccount?.id
            if let first = movements.first { date = first.bookedOn.date() }
        }
    }

    private func save() async {
        let tagsToAdd = MovementTags.normalize(addTags)
        if let issue = MovementTags.issue(tagsToAdd) { error = issue.text; return }
        let changed = edit.changes(for: movements)
        guard !changed.isEmpty else { dismiss(); return }
        isWorking = true
        defer { isWorking = false }
        if await finance.update(changed) {
            onDone()
            dismiss()
        } else {
            error = finance.error
        }
    }
}
