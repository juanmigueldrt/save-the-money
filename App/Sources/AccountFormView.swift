import SwiftUI
import Charts
import STMCore
import STMUI

// MARK: Formularios

/// Crear o editar una cuenta.
struct AccountFormView: View {
    let account: Account?
    /// Tipo con el que empieza una cuenta nueva (p. ej. tarjeta, desde la pantalla de tarjetas).
    var initialKind: AccountKind = .checking

    @Environment(FinanceModel.self) private var finance
    @Environment(BudgetModel.self) private var budgets
    @Environment(PlanningModel.self) private var planning
    @Environment(InvestmentModel.self) private var investments
    @Environment(CreditCardModel.self) private var cards
    @Environment(TrackingModel.self) private var tracking
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: AccountKind = .checking
    @State private var openingBalance = ""
    @State private var isShared = true
    @State private var isDefault = false
    @State private var includeInNetWorth = true
    /// Identificador de la cuenta nueva, uno por formulario: reintentar el alta con el mismo no crea otra.
    @State private var newAccountId = UUID()
    @State private var error: String?
    @State private var isWorking = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre, p. ej. Cuenta nómina", text: $name)
                    Picker("Tipo", selection: $kind) {
                        ForEach(AccountKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .disabled(isCardLocked)
                    TextField("Saldo inicial, p. ej. 1.250,00", text: $openingBalance)
                        .decimalInput()
                    Toggle("Compartida con el hogar", isOn: $isShared)
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.s4) {
                        if isCardLocked {
                            Text("Una tarjeta de crédito no puede cambiar de tipo.")
                        }
                        Text("El saldo inicial es lo que había en la cuenta antes del primer movimiento que apuntes o importes.")
                    }
                }
                Section {
                    Toggle("Cuenta predeterminada", isOn: $isDefault)
                    Toggle("Contar en el patrimonio", isOn: $includeInNetWorth)
                } footer: {
                    Text("La predeterminada sale elegida al apuntar un movimiento. Sin «Contar en el patrimonio», la cuenta sigue con su saldo pero no suma en el patrimonio neto.")
                }
                if let account {
                    Section {
                        Button(account.isArchived ? "Desarchivar" : "Archivar") { Task { await toggleArchive() } }
                        Button("Borrar cuenta y sus movimientos", role: .destructive) { confirmingDelete = true }
                    }
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle(account == nil ? "Nueva cuenta" : "Editar cuenta")
            .formToolbar(isWorking: isWorking, cancel: { dismiss() }, save: { await save() })
            .confirmationDialog("¿Borrar esta cuenta?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Borrar cuenta y movimientos", role: .destructive) { Task { await delete() } }
            } message: {
                Text("Se borran también todos sus movimientos, para todo el hogar. No se puede deshacer.")
            }
        }
        .frame(minWidth: 360, minHeight: 360)
        .onAppear(perform: fill)
    }

    /// Una tarjeta ya creada no puede cambiar de tipo (el servidor también lo rechaza).
    private var isCardLocked: Bool { account?.kind == .creditCard }

    private func fill() {
        guard let account else {
            kind = initialKind
            return
        }
        name = account.name
        kind = account.kind
        openingBalance = account.openingBalance.minor == 0 ? "" : account.openingBalance.plainText
        isShared = account.isShared
        isDefault = account.isDefault
        includeInNetWorth = account.includeInNetWorth
    }

    private var parsedOpening: Money? {
        openingBalance.trimmingCharacters(in: .whitespaces).isEmpty ? .zero : Money(entered: openingBalance)
    }

    private var ownerId: UUID? {
        guard !isShared else { return nil }
        if case .ready(let profile, _) = session.state { return account?.ownerId ?? profile.id }
        return nil
    }

    private func save() async {
        guard let opening = parsedOpening else { error = "El saldo inicial no es un importe válido."; return }
        let draft = AccountDraft(id: newAccountId, name: name, kind: kind, openingBalance: opening, ownerId: ownerId)
        if let issue = draft.issue { error = issue; return }
        isWorking = true
        defer { isWorking = false }
        let ok: Bool
        if var updated = account {
            updated.name = draft.trimmedName
            updated.kind = kind
            updated.openingBalance = opening
            updated.ownerId = draft.ownerId
            updated.isDefault = isDefault
            updated.includeInNetWorth = includeInNetWorth
            ok = await finance.updateAccount(updated)
        } else {
            ok = await finance.createAccount(draft)
            // Las dos opciones nuevas se guardan después de crearla (el alta sólo lleva lo básico).
            if ok, isDefault || !includeInNetWorth, var created = finance.account(draft.id) {
                created.isDefault = isDefault
                created.includeInNetWorth = includeInNetWorth
                await finance.updateAccount(created)
            }
        }
        if ok { dismiss() } else { error = finance.error }
    }

    private func toggleArchive() async {
        guard var updated = account else { return }
        updated.archivedAt = updated.isArchived ? nil : Date()
        if await finance.updateAccount(updated) { dismiss() } else { error = finance.error }
    }

    private func delete() async {
        guard let account else { return }
        // Recarga también lo que usaba la cuenta: el servidor lo ha dejado sin ella y con versión nueva.
        let reload = HouseholdReload(finance: finance, budgets: budgets, planning: planning, investments: investments,
                                 cards: cards, tracking: tracking)
        if await reload.deleteAccount(account) { dismiss() } else { error = finance.error }
    }
}
