import SwiftUI
import STMCore
import STMUI

// MARK: - Categorías

struct CategoriesView: View {
    @Environment(FinanceModel.self) private var finance
    @State private var editing: BudgetCategory?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                ForEach(finance.categories(for: .income)) { row($0) }
            } header: {
                Text("Ingresos")
            }
            ForEach(BudgetGroup.allCases, id: \.self) { group in
                let items = finance.categories(for: .expense).filter { $0.budgetGroup == group }
                if !items.isEmpty {
                    Section("Gastos: \(group.title.lowercased())") {
                        ForEach(items) { row($0) }
                    }
                }
            }
            let loose = finance.categories(for: .expense).filter { $0.budgetGroup == nil }
            if !loose.isEmpty {
                Section("Gastos sin grupo") {
                    ForEach(loose) { row($0) }
                }
            }
            Section {
            } footer: {
                Text("Las categorías se comparten con todo el hogar. El grupo decide en qué parte del 50/30/20 cuenta cada gasto.")
            }
        }
        .brandBackground()
        .navigationTitle("Categorías")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nueva categoría", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) { CategoryFormView(category: nil) }
        .sheet(item: $editing) { CategoryFormView(category: $0) }
    }

    private func row(_ category: BudgetCategory) -> some View {
        Button { editing = category } label: {
            HStack(spacing: Spacing.s16) {
                Image(systemName: category.icon ?? "tag")
                    .foregroundStyle(Palette.accentText)
                    .frame(width: 28)
                Text(category.name)
                    .font(Typography.body)
                    .foregroundStyle(Palette.label)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CategoryFormView: View {
    let category: BudgetCategory?

    @Environment(FinanceModel.self) private var finance
    @Environment(BudgetModel.self) private var budgets
    @Environment(PlanningModel.self) private var planning
    @Environment(InvestmentModel.self) private var investments
    @Environment(CreditCardModel.self) private var cards
    @Environment(TrackingModel.self) private var tracking
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: CategoryKind = .expense
    @State private var group: BudgetGroup? = .needs
    @State private var icon = "tag"
    /// Identificador de la categoría nueva, uno por formulario: reintentar el alta con el mismo no crea otra.
    @State private var newCategoryId = UUID()
    @State private var error: String?
    @State private var isWorking = false
    @State private var confirmingDelete = false

    /// Iconos para elegir; todos son símbolos del sistema.
    static let icons = ["tag", "house", "cart", "bolt", "car", "cross.case", "shield", "fork.knife", "ticket", "bag",
                        "airplane", "repeat", "banknote", "creditcard", "pawprint", "gift", "graduationcap",
                        "figure.and.child.holdinghands", "tshirt", "wrench.and.screwdriver", "gamecontroller",
                        "book", "heart", "leaf", "phone", "wifi", "drop", "fuelpump", "bus", "dumbbell"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre, p. ej. Mascotas", text: $name)
                    if category == nil {
                        Picker("Tipo", selection: $kind) {
                            Text(CategoryKind.expense.title).tag(CategoryKind.expense)
                            Text(CategoryKind.income.title).tag(CategoryKind.income)
                        }
                    } else {
                        LabeledContent("Tipo", value: kind.title)
                    }
                    if kind == .expense {
                        Picker("Grupo del 50/30/20", selection: $group) {
                            ForEach(BudgetGroup.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                            Text("Sin grupo").tag(BudgetGroup?.none)
                        }
                    }
                }
                Section("Icono") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: Spacing.s8) {
                        ForEach(Self.icons, id: \.self) { symbol in
                            Button { icon = symbol } label: {
                                Image(systemName: symbol)
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(icon == symbol ? Palette.onAccent : Palette.label)
                                    .background(icon == symbol ? Palette.accent : Palette.fill,
                                                in: RoundedRectangle(cornerRadius: Radius.input))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(icon == symbol ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, Spacing.s8)
                }
                if let category {
                    Section {
                        Button("Borrar categoría", role: .destructive) { confirmingDelete = true }
                    } footer: {
                        let uses = finance.recentUses(of: category)
                        if uses > 0 {
                            Text("La usan \(uses) movimientos recientes. Se quedarán sin categoría.")
                        }
                    }
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle(category == nil ? "Nueva categoría" : "Editar categoría")
            .formToolbar(isWorking: isWorking, cancel: { dismiss() }, save: { await save() })
            .confirmationDialog("¿Borrar esta categoría?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) { Task { await delete() } }
            } message: {
                Text("Se borra para todo el hogar. Los movimientos se quedan sin categoría y su límite del presupuesto desaparece.")
            }
        }
        .frame(minWidth: 360, minHeight: 480)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let category else { return }
        name = category.name
        kind = category.kind
        group = category.budgetGroup
        icon = category.icon ?? "tag"
    }

    private func save() async {
        var item = category ?? BudgetCategory(id: newCategoryId, householdId: finance.household.id, name: name, kind: kind)
        item.name = name
        item.budgetGroup = kind == .expense ? group : nil
        item.icon = icon
        isWorking = true
        defer { isWorking = false }
        if await finance.save(item) { dismiss() } else { error = finance.error }
    }

    private func delete() async {
        guard let category else { return }
        // Recarga también lo que usaba la categoría: el servidor lo ha dejado sin ella y con versión nueva.
        let reload = HouseholdReload(finance: finance, budgets: budgets, planning: planning, investments: investments,
                                 cards: cards, tracking: tracking)
        if await reload.delete(category) { dismiss() } else { error = finance.error }
    }
}
