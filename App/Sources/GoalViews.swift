import SwiftUI
import STMCore
import STMUI

/// Metas de ahorro y de deudas del hogar, con su progreso y cuándo se alcanzarán.
struct GoalsView: View {
    @Environment(PlanningModel.self) private var planning
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                if planning.progress.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text("Sin metas todavía")
                            .titleFont(.title2)
                            .foregroundStyle(Palette.label)
                        EmptyHint(text: "Crea una meta para ahorrar (un viaje, un fondo de emergencia) o para terminar de pagar una deuda. Verás cuánto falta y cuándo llegarás.")
                        Button("Crear una meta") { adding = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .card()
                }
                ForEach(GoalKind.allCases, id: \.self) { kind in
                    let items = planning.progress.filter { $0.goal.kind == kind }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.s16) {
                            Text(kind == .savings ? "Ahorro" : "Deudas")
                                .titleFont(.title2)
                                .foregroundStyle(Palette.label)
                            ForEach(items) { progress in
                                NavigationLink(value: progress.goal) {
                                    GoalCard(progress: progress)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                ErrorText(message: planning.error)
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Metas")
        .navigationDestination(for: Goal.self) { GoalDetailView(goalId: $0.id) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nueva meta", systemImage: "plus") { adding = true }
            }
        }
        .refreshable { await planning.load() }
        .sheet(isPresented: $adding) { GoalFormView(goal: nil) }
    }
}

/// Tarjeta de una meta: barra de progreso y proyección.
struct GoalCard: View {
    let progress: GoalProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            HStack {
                Label(progress.goal.trimmedName, systemImage: progress.goal.icon ?? progress.goal.kind.systemImage)
                    .font(Typography.headline)
                    .foregroundStyle(Palette.label)
                Spacer()
                Text("\(Int((progress.fraction * 100).rounded())) %")
                    .font(Typography.subheadlineEmphasis)
                    .foregroundStyle(progress.isReached ? Palette.positiveText : Palette.labelSecondary)
            }
            ProgressBar(fraction: progress.fraction)
            Text(GoalText.amounts(progress))
                .font(Typography.subheadline)
                .foregroundStyle(Palette.label)
            Text(GoalText.projection(progress))
                .font(Typography.footnote)
                .foregroundStyle(progress.isOnTrack == false ? Palette.negativeText : Palette.labelSecondary)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.bgGrouped)
                Capsule().fill(Palette.accent)
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// Textos de las metas, en un solo sitio para la tarjeta y el detalle.
enum GoalText {
    static func amounts(_ progress: GoalProgress) -> String {
        switch progress.goal.kind {
        case .savings: "\(progress.saved.formatted()) de \(progress.goal.target.formatted())"
        case .debt: "Pagado \(progress.saved.formatted()) de \(progress.goal.target.formatted())"
        }
    }

    static func projection(_ progress: GoalProgress) -> String {
        if progress.isReached { return progress.goal.kind == .savings ? "¡Meta conseguida!" : "¡Deuda pagada!" }
        var parts: [String] = []
        if let pace = progress.monthlyPace, let month = progress.projectedMonth {
            parts.append("A \(pace.formatted()) al mes, la alcanzas en \(month.title.lowercased())")
        } else {
            parts.append("Faltan \(progress.remaining.formatted()). Añade una aportación o un plan mensual para ver cuándo llegarás")
        }
        if let needed = progress.neededMonthly, let date = progress.goal.targetOn {
            let verdict = progress.isOnTrack == true ? "vas bien" : "necesitas \(needed.formatted()) al mes"
            parts.append("Para el \(date.longTitle) de \(date.year), \(verdict)")
        }
        return parts.joined(separator: ". ") + "."
    }
}

/// Detalle de una meta: progreso, aportaciones y botón para aportar.
struct GoalDetailView: View {
    let goalId: UUID

    @Environment(PlanningModel.self) private var planning
    @State private var editing = false
    @State private var contributing = false

    private var goal: Goal? { planning.goals.first { $0.id == goalId } }

    var body: some View {
        Group {
            if let goal {
                content(goal)
            } else {
                EmptyHint(text: "Esta meta ya no existe.")
                    .padding(Spacing.s16)
            }
        }
        .background(Palette.bgGrouped)
    }

    private func content(_ goal: Goal) -> some View {
        let progress = planning.progress(of: goal)
        return List {
            Section {
                GoalCard(progress: progress)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                Button(goal.kind == .savings ? "Añadir aportación" : "Apuntar un pago", systemImage: "plus") {
                    contributing = true
                }
            }
            Section("Historial") {
                let items = planning.contributions(of: goal)
                if items.isEmpty {
                    Text("Todavía no hay aportaciones.")
                        .foregroundStyle(Palette.labelSecondary)
                }
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.s8) {
                            Text(item.madeOn.shortText)
                                .font(Typography.subheadlineEmphasis)
                            if let note = item.note {
                                Text(note)
                                    .font(Typography.footnote)
                                    .foregroundStyle(Palette.labelSecondary)
                            }
                        }
                        Spacer()
                        Text(item.amount.formatted())
                            .font(Typography.subheadlineEmphasis)
                            .foregroundStyle(item.amount.isNegative ? Palette.negativeText : Palette.label)
                    }
                    .swipeActions {
                        Button("Borrar", role: .destructive) { Task { await planning.delete(item) } }
                    }
                    .contextMenu {
                        Button("Borrar", role: .destructive) { Task { await planning.delete(item) } }
                    }
                }
            }
            if let error = planning.error {
                Section { ErrorText(message: error) }
            }
        }
        .brandBackground()
        .navigationTitle(goal.trimmedName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Editar") { editing = true } }
        }
        .sheet(isPresented: $editing) { GoalFormView(goal: goal) }
        .sheet(isPresented: $contributing) { ContributionFormView(goal: goal) }
    }
}

/// Crear o editar una meta.
struct GoalFormView: View {
    let goal: Goal?

    @Environment(PlanningModel.self) private var planning
    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: GoalKind = .savings
    @State private var target = ""
    @State private var starting = ""
    @State private var monthlyPlan = ""
    @State private var hasDate = false
    @State private var targetOn = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var accountId: UUID?
    @State private var error: String?
    @State private var isWorking = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $kind) {
                        ForEach(GoalKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField(kind == .savings ? "Nombre, p. ej. Viaje de verano" : "Nombre, p. ej. Préstamo del coche", text: $name)
                    TextField(kind == .savings ? "Cuánto quieres juntar" : "Cuánto se debía al empezar", text: $target)
                        .decimalInput()
                    TextField(kind == .savings ? "Lo que ya tienes ahorrado (opcional)" : "Lo que ya has pagado (opcional)", text: $starting)
                        .decimalInput()
                }
                Section {
                    TextField("Aportación mensual prevista (opcional)", text: $monthlyPlan)
                        .decimalInput()
                    Toggle("Tiene fecha objetivo", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Fecha objetivo", selection: $targetOn, in: Date()..., displayedComponents: .date)
                    }
                    Picker("Cuenta asociada", selection: $accountId) {
                        Text("Ninguna").tag(UUID?.none)
                        ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                } footer: {
                    Text("Sin aportación prevista, la proyección usa la media de tus aportaciones de los últimos 3 meses. La meta se comparte con todo el hogar.")
                }
                if let goal {
                    Section {
                        Button(goal.isArchived ? "Desarchivar" : "Archivar") { Task { await toggleArchive() } }
                        Button("Borrar meta y aportaciones", role: .destructive) { confirmingDelete = true }
                    }
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle(goal == nil ? "Nueva meta" : "Editar meta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }.disabled(isWorking)
                }
            }
            .confirmationDialog("¿Borrar esta meta?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Borrar meta", role: .destructive) { Task { await delete() } }
            } message: {
                Text("Se borran también sus aportaciones, para todo el hogar. No se puede deshacer.")
            }
        }
        .frame(minWidth: 360, minHeight: 460)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let goal else { return }
        name = goal.name
        kind = goal.kind
        target = goal.target.plainText
        starting = goal.starting.minor == 0 ? "" : goal.starting.plainText
        monthlyPlan = goal.monthlyPlan.map(\.plainText) ?? ""
        hasDate = goal.targetOn != nil
        if let date = goal.targetOn?.date() { targetOn = date }
        accountId = goal.accountId
    }

    /// Un campo vacío es cero (o nada); si no se entiende, devuelve nil.
    private func amount(_ text: String) -> Money?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        return Money(parsing: trimmed).map { .some($0) }
    }

    private func save() async {
        guard let targetMoney = Money(parsing: target), targetMoney.minor > 0 else {
            error = kind == .savings ? "Indica cuánto quieres juntar." : "Indica cuánto se debía."
            return
        }
        guard let startingMoney = amount(starting), let plan = amount(monthlyPlan) else {
            error = "Algún importe no es válido."
            return
        }
        var item = goal ?? Goal(householdId: planning.household.id, name: name, target: targetMoney)
        item.name = name
        item.kind = kind
        item.target = targetMoney
        item.starting = startingMoney ?? .zero
        item.monthlyPlan = plan
        item.targetOn = hasDate ? CalendarDay(targetOn) : nil
        item.accountId = accountId
        if let issue = item.issue { error = issue; return }
        isWorking = true
        defer { isWorking = false }
        if await planning.save(item) { dismiss() } else { error = planning.error }
    }

    private func toggleArchive() async {
        guard var item = goal else { return }
        item.archivedAt = item.isArchived ? nil : Date()
        if await planning.save(item) { dismiss() } else { error = planning.error }
    }

    private func delete() async {
        guard let goal else { return }
        if await planning.delete(goal) { dismiss() } else { error = planning.error }
    }
}

/// Apuntar una aportación (o un pago de la deuda). Con "Sacar dinero", resta.
struct ContributionFormView: View {
    let goal: Goal

    @Environment(PlanningModel.self) private var planning
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var isWithdrawal = false
    @State private var madeOn = Date()
    @State private var note = ""
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Importe, p. ej. 100", text: $amount)
                        .decimalInput()
                    if goal.kind == .savings {
                        Toggle("Sacar dinero de la meta", isOn: $isWithdrawal)
                    }
                    DatePicker("Fecha", selection: $madeOn, displayedComponents: .date)
                    TextField("Nota (opcional)", text: $note)
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle(goal.kind == .savings ? "Aportación" : "Pago de la deuda")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }.disabled(isWorking)
                }
            }
        }
        .frame(minWidth: 340, minHeight: 300)
    }

    private func save() async {
        guard let money = Money(parsing: amount), money.minor > 0 else {
            error = "El importe no es válido."
            return
        }
        isWorking = true
        defer { isWorking = false }
        let signed = isWithdrawal ? -money : money
        if await planning.contribute(signed, to: goal, on: CalendarDay(madeOn), note: note) {
            dismiss()
        } else {
            error = planning.error
        }
    }
}
