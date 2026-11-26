import SwiftUI
import Charts
import STMCore
import STMUI

/// Crear o editar un plan de aportación.
struct PlanFormView: View {
    let plan: InvestmentPlan?

    @Environment(InvestmentModel.self) private var investments
    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var holdingId: UUID?
    @State private var amount = ""
    @State private var recurrence: Recurrence = .monthly
    @State private var accountId: UUID?
    @State private var startsOn = Date()
    @State private var expectedReturn = "5"
    @State private var remindDaysBefore: Int? = 1
    /// Identificador del plan nuevo, uno por formulario: reintentar el alta con el mismo no crea otro.
    @State private var newPlanId = UUID()
    @State private var error: String?
    @State private var isWorking = false
    @State private var confirmingDelete = false

    private var draft: InvestmentPlan? {
        guard let holdingId, let money = Money(entered: amount), let rate = Decimal(parsing: expectedReturn, maxFractionDigits: 2) else { return nil }
        var item = plan ?? InvestmentPlan(id: newPlanId, householdId: investments.household.id, holdingId: holdingId, amount: money,
                                          startsOn: CalendarDay(startsOn))
        item.amount = money
        item.recurrence = recurrence
        item.accountId = accountId
        item.startsOn = CalendarDay(startsOn)
        item.expectedAnnualReturn = rate
        item.remindDaysBefore = remindDaysBefore
        return item
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Activo", selection: $holdingId) {
                        if holdingId == nil { Text("Elige uno").tag(UUID?.none) }
                        ForEach(investments.activeHoldings) { Text($0.trimmedName).tag(Optional($0.id)) }
                    }
                    .disabled(plan != nil)
                    TextField("Importe, p. ej. 150", text: $amount)
                        .decimalInput()
                    Picker("Cada", selection: $recurrence) {
                        ForEach(Recurrence.common, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Sale de", selection: $accountId) {
                        Text("Ninguna cuenta").tag(UUID?.none)
                        ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    DatePicker("Primera aportación", selection: $startsOn, displayedComponents: .date)
                }
                Section {
                    Picker("Aviso", selection: $remindDaysBefore) {
                        Text("Sin aviso").tag(Int?.none)
                        Text("El mismo día").tag(Optional(0))
                        Text("1 día antes").tag(Optional(1))
                        Text("3 días antes").tag(Optional(3))
                    }
                    TextField("Rentabilidad anual supuesta en %", text: $expectedReturn)
                        .decimalInput()
                } footer: {
                    if let draft, draft.issue == nil {
                        Text("Si rinde un \(expectedReturn) % al año, lo aportado en 1 año valdría unos \(draft.projectedValue(months: 12).formatted()) y en 5 años unos \(draft.projectedValue(months: 60).formatted()). Es una estimación, no una promesa.")
                    } else {
                        Text("La rentabilidad supuesta sólo sirve para la proyección.")
                    }
                }
                if plan != nil {
                    Section {
                        Button("Borrar plan", role: .destructive) { confirmingDelete = true }
                    } footer: {
                        Text("Las compras que ya apuntaste no se borran.")
                    }
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle(plan == nil ? "Nuevo plan" : "Editar plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(plan == nil ? "Crear" : "Guardar") { Task { await save() } }.disabled(isWorking)
                }
            }
            .confirmationDialog("¿Borrar este plan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Borrar plan", role: .destructive) { Task { await delete() } }
            }
        }
        .frame(minWidth: 380, minHeight: 520)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let plan else {
            holdingId = investments.activeHoldings.first?.id
            return
        }
        holdingId = plan.holdingId
        amount = plan.amount.plainText
        recurrence = plan.recurrence
        accountId = plan.accountId
        startsOn = plan.startsOn.date()
        expectedReturn = InvestmentText.plain(plan.expectedAnnualReturn)
        remindDaysBefore = plan.remindDaysBefore
    }

    private func save() async {
        guard holdingId != nil else { error = "Elige un activo."; return }
        guard let item = draft else { error = "Escribe el importe y la rentabilidad con números."; return }
        if let issue = item.issue { error = issue; return }
        isWorking = true
        defer { isWorking = false }
        if await investments.save(item) { dismiss() } else { error = investments.error }
    }

    private func delete() async {
        guard let plan else { return }
        if await investments.delete(plan) { dismiss() } else { error = investments.error }
    }
}
