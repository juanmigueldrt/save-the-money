import SwiftUI
import STMCore
import STMUI

/// Más opciones. En iPhone también da paso a lo que no cabe en la barra inferior.
struct MoreView: View {
    let profile: Profile
    let household: Household

    @Environment(SessionModel.self) private var session
    @Environment(FinanceModel.self) private var finance
    @Environment(PlanningModel.self) private var planning
    @AppStorage(LocalReminders.enabledKey) private var remindersEnabled = true
    @AppStorage(LocalBudgetAlerts.enabledKey) private var budgetAlertsEnabled = true
    @State private var themeError: String?
    @State private var csvFile: URL?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var resetting = false

    var body: some View {
        List {
            #if os(iOS)
            Section {
                NavigationLink {
                    HouseholdView(profile: profile, household: household)
                } label: {
                    Label("Hogar: \(household.name)", systemImage: AppSection.household.systemImage)
                }
                NavigationLink {
                    RecurringView()
                } label: {
                    Label(AppSection.subscriptions.title, systemImage: AppSection.subscriptions.systemImage)
                }
            }
            Section("Seguimiento") {
                ForEach([AppSection.netWorth, .reports, .creditScore]) { section in
                    NavigationLink {
                        switch section {
                        case .netWorth: NetWorthView()
                        case .reports: ReportsView()
                        default: CreditScoreView()
                        }
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }
            }
            #endif

            Section {
                Picker("Tema", selection: themeBinding) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                ErrorText(message: themeError)
            } header: {
                Text("Apariencia")
            } footer: {
                Text("Se guarda en tu perfil. «Automático» sigue el modo claro u oscuro del dispositivo.")
            }

            Section {
                Toggle("Avisos de pagos fijos", isOn: $remindersEnabled)
                    .onChange(of: remindersEnabled) { _, _ in Task { await planning.reschedule() } }
                Toggle("Avisos de límites del presupuesto", isOn: $budgetAlertsEnabled)
            } header: {
                Text("Avisos")
            } footer: {
                Text("Los lanza este dispositivo: antes de cada pago fijo y cuando una categoría o grupo del presupuesto llega al 80 % o se pasa.")
            }

            Section("Categorías") {
                NavigationLink {
                    CategoriesView()
                } label: {
                    Label("Categorías del hogar", systemImage: "tag")
                }
            }

            Section {
                NavigationLink {
                    CSVImportView()
                } label: {
                    Label("Importar CSV del banco", systemImage: "square.and.arrow.down")
                }
                exportRow
                NavigationLink {
                    BillsReportView()
                } label: {
                    Label("PDF de pagos del mes", systemImage: "doc.richtext")
                }
                ErrorText(message: exportError)
            } header: {
                Text("Datos")
            } footer: {
                Text("Los ficheros se crean en este dispositivo y sólo salen de él si tú los compartes.")
            }

            Section {
                Button(role: .destructive) { resetting = true } label: {
                    Label("Borrar datos y empezar de cero", systemImage: "trash")
                        .foregroundStyle(Palette.negativeText)
                }
            } footer: {
                Text("Borra las cuentas, movimientos, presupuestos, pagos fijos y metas de todo el hogar.")
            }
        }
        .brandBackground()
        .navigationTitle("Más opciones")
        .sheet(isPresented: $resetting) { ResetHouseholdView(household: household) }
    }

    private var themeBinding: Binding<AppTheme> {
        Binding(get: { session.theme }, set: { newTheme in
            Task {
                do {
                    themeError = nil
                    try await session.setTheme(newTheme)
                } catch {
                    themeError = (error as? AppError)?.errorDescription ?? AppError.unknown("").errorDescription
                }
            }
        })
    }

    @ViewBuilder
    private var exportRow: some View {
        if let csvFile {
            ShareLink(item: csvFile) {
                Label("Compartir \(csvFile.lastPathComponent)", systemImage: "square.and.arrow.up")
            }
        } else {
            Button {
                Task { await exportCSV() }
            } label: {
                HStack {
                    Label("Exportar CSV para Excel", systemImage: "tablecells")
                    Spacer()
                    if isExporting { ProgressView() }
                }
            }
            .disabled(isExporting)
        }
    }

    private func exportCSV() async {
        isExporting = true
        defer { isExporting = false }
        exportError = nil
        guard let data = await finance.exportCSV() else {
            exportError = finance.error
            return
        }
        do {
            csvFile = try ExportFiles.write(data, named: MovementsCSV.fileName())
        } catch {
            exportError = "No se ha podido crear el fichero."
        }
    }
}

/// Ficheros exportados: van a la carpeta temporal de la app; cada exportación sustituye a la anterior.
enum ExportFiles {
    static func write(_ data: Data, named name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("exportar", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

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
                ErrorText(message: finance.error)
            } footer: {
                Text("Las categorías se comparten con todo el hogar. El grupo decide en qué parte del 50/30/20 cuenta cada gasto.")
            }
        }
        .brandBackground()
        .navigationTitle("Categorías")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nueva categoría", systemImage: "plus.circle.fill") { adding = true }
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
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: CategoryKind = .expense
    @State private var group: BudgetGroup? = .needs
    @State private var icon = "tag"
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }.disabled(isWorking)
                }
            }
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
        var item = category ?? BudgetCategory(householdId: finance.household.id, name: name, kind: kind)
        item.name = name
        item.budgetGroup = kind == .expense ? group : nil
        item.icon = icon
        isWorking = true
        defer { isWorking = false }
        if await finance.save(item) { dismiss() } else { error = finance.error }
    }

    private func delete() async {
        guard let category else { return }
        if await finance.delete(category) { dismiss() } else { error = finance.error }
    }
}

// MARK: - Empezar de cero

struct ResetHouseholdView: View {
    let household: Household

    @Environment(FinanceModel.self) private var finance
    @Environment(PlanningModel.self) private var planning
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var error: String?

    static let word = "BORRAR"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s24) {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Eyebrow("Empezar de cero")
                        Text("Se borrará todo lo apuntado en «\(household.name)»")
                            .titleFont(.title2)
                            .foregroundStyle(Palette.label)
                        Text("Cuentas, movimientos, categorías propias, presupuestos, pagos fijos y metas, para todas las personas del hogar. Las categorías de partida vuelven a estar. Los miembros y las invitaciones se quedan.")
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.labelSecondary)
                        Text("No se puede deshacer. Si quieres guardar una copia, exporta antes el CSV.")
                            .font(Typography.subheadlineEmphasis)
                            .foregroundStyle(Palette.negativeText)
                    }
                    .card()

                    LabeledField(label: "Escribe \(Self.word) para confirmar") {
                        TextField(Self.word, text: $confirmation)
                            .plainIdentifierInput()
                    }

                    ErrorText(message: error)

                    Button {
                        Task { await reset() }
                    } label: {
                        if isWorking { ProgressView().tint(Palette.onAccent) } else { Text("Borrar todo") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!isConfirmed || isWorking)
                }
                .padding(Spacing.s16)
            }
            .background(Palette.bgGrouped)
            .navigationTitle("Borrar datos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }

    private var isConfirmed: Bool {
        confirmation.trimmingCharacters(in: .whitespaces).uppercased() == Self.word
    }

    private func reset() async {
        isWorking = true
        defer { isWorking = false }
        error = nil
        guard await finance.resetHousehold() else {
            error = finance.error
            return
        }
        // Recarga los pagos fijos y metas (y con ellos, los avisos del dispositivo).
        await planning.load()
        dismiss()
    }
}
