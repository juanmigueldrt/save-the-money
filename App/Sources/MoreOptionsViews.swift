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
    @Environment(InvestmentModel.self) private var investments
    @Environment(CreditCardModel.self) private var cards
    @AppStorage(LocalReminders.enabledKey) private var remindersEnabled = true
    @AppStorage(LocalBudgetAlerts.enabledKey) private var budgetAlertsEnabled = true
    @AppStorage(HabitSettings.logReminderKey) private var logReminder: HabitSettings.LogReminder = .off
    @AppStorage(HabitSettings.logHourKey) private var logHour = 21
    @AppStorage(HabitSettings.weeklySummaryKey) private var weeklySummary = true
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
                    CreditCardsView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppSection.creditCards.title)
                            Text("Próximo cargo, límite y compras a plazos")
                                .font(Typography.footnote)
                                .foregroundStyle(Palette.labelSecondary)
                        }
                    } icon: {
                        Image(systemName: AppSection.creditCards.systemImage)
                    }
                }
                NavigationLink {
                    RecurringView()
                } label: {
                    Label(AppSection.subscriptions.title, systemImage: AppSection.subscriptions.systemImage)
                }
                NavigationLink {
                    InvestmentsView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppSection.investments.title)
                            Text("Cartera y aportaciones automáticas")
                                .font(Typography.footnote)
                                .foregroundStyle(Palette.labelSecondary)
                        }
                    } icon: {
                        Image(systemName: AppSection.investments.systemImage)
                    }
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

            DisplayOptionsSection()

            AppLockSection()

            ChangePasswordSection()

            Section {
                Toggle("Avisos de pagos fijos", isOn: $remindersEnabled)
                    .onChange(of: remindersEnabled) { _, _ in
                        // Apaga (o vuelve a encender) todos: pagos fijos, tarjetas y aportaciones.
                        Task {
                            await planning.reschedule()
                            await investments.reschedule()
                            await cards.reschedule()
                        }
                    }
                Toggle("Avisos de límites del presupuesto", isOn: $budgetAlertsEnabled)
            } header: {
                Text("Avisos")
            } footer: {
                Text("Los lanza este dispositivo: antes de cada pago fijo, cargo de tarjeta o aportación, y cuando una categoría o grupo del presupuesto llega al 80 % o se pasa.")
            }

            Section {
                Picker("Recordarme apuntar gastos", selection: $logReminder) {
                    ForEach(HabitSettings.LogReminder.allCases) { Text($0.title).tag($0) }
                }
                if logReminder != .off {
                    Stepper("A las \(logHour):00", value: $logHour, in: 6...23)
                }
                Toggle("Resumen semanal los lunes", isOn: $weeklySummary)
            } header: {
                Text("Recordatorios")
            } footer: {
                Text("Un aviso para no olvidar apuntar lo gastado y, cada lunes a las 9:00, otro con el resumen de la semana anterior.")
            }
            .onChange(of: logReminder) { _, _ in Task { await planning.rescheduleHabits() } }
            .onChange(of: logHour) { _, _ in Task { await planning.rescheduleHabits() } }
            .onChange(of: weeklySummary) { _, _ in Task { await planning.rescheduleHabits() } }

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
                Text("Borra lo que creaste tú: cuentas, tarjetas, movimientos, presupuestos, pagos fijos, metas e inversiones. Lo que crearon otros miembros se queda, salvo lo que cuelga de algo tuyo.")
            }

            Section {
                Button { Task { await session.signOut() } } label: {
                    Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text("Sesión iniciada como \(profile.name).")
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

/// Ficheros exportados: van a la carpeta temporal de la app. La carpeta se vacía al arrancar, al cerrar
/// sesión y antes de cada exportación, así no quedan datos de una exportación anterior.
enum ExportFiles {
    static var folder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("exportar", isDirectory: true) }

    static func clear() {
        try? FileManager.default.removeItem(at: folder)
    }

    static func write(_ data: Data, named name: String) throws -> URL {
        clear()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        // En macOS escribir con protección completa falla (EPERM); allí sólo queda el borrado de la carpeta.
        #if os(iOS)
        let options: Data.WritingOptions = [.atomic, .completeFileProtection]
        #else
        let options: Data.WritingOptions = [.atomic]
        #endif
        try data.write(to: url, options: options)
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

// MARK: - Empezar de cero

struct ResetHouseholdView: View {
    let household: Household

    @Environment(FinanceModel.self) private var finance
    @Environment(PlanningModel.self) private var planning
    @Environment(InvestmentModel.self) private var investments
    @Environment(BudgetModel.self) private var budgets
    @Environment(CreditCardModel.self) private var cards
    @Environment(TrackingModel.self) private var tracking
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
                        Text("Se borrará lo que creaste en «\(household.name)»")
                            .titleFont(.title2)
                            .foregroundStyle(Palette.label)
                        Text("Cuentas, tarjetas, movimientos, categorías propias, presupuestos, pagos fijos, metas e inversiones que creaste tú. Lo que crearon otros miembros se queda, salvo lo que cuelga de algo tuyo. Las categorías de partida vuelven a estar. Los miembros y las invitaciones se quedan.")
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
        // Lo mismo que ⌘R: el presupuesto y el resto se recargan aunque no hubiera movimientos que cambiaran.
        await HouseholdReload(finance: finance, budgets: budgets, planning: planning, investments: investments,
                              cards: cards, tracking: tracking).reload()
        dismiss()
    }
}

// MARK: Cambiar la contraseña (ORC-57)

/// Fila de Ajustes que abre el cambio de contraseña, junto al bloqueo de la app.
struct ChangePasswordSection: View {
    @State private var isChanging = false
    @State private var changed = false

    var body: some View {
        Section {
            Button { isChanging = true } label: {
                Label("Cambiar la contraseña", systemImage: "key")
            }
        } footer: {
            Text(changed
                 ? "Contraseña cambiada. Esta sesión sigue abierta; en tus otros dispositivos tendrás que volver a entrar."
                 : "Pide la contraseña actual. Al cambiarla se cierra la sesión en tus otros dispositivos.")
        }
        .sheet(isPresented: $isChanging) {
            ChangePasswordView { changed = true }
        }
    }
}

/// Formulario: contraseña actual y la nueva dos veces, con la misma regla que al crear la cuenta.
struct ChangePasswordView: View {
    var onChanged: () -> Void

    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var form = ChangePasswordForm()
    @State private var error: String?
    @State private var isWorking = false
    @State private var triedToSubmit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.s24) {
                    LabeledField(label: "Contraseña actual") {
                        SecureField("Contraseña actual", text: $form.currentPassword)
                            .textContentType(.password)
                    }
                    LabeledField(label: "Nueva contraseña") {
                        SecureField("Al menos \(SignUpForm.minimumPasswordLength) caracteres", text: $form.newPassword)
                            .newPasswordContentType()
                    }
                    LabeledField(label: "Repite la nueva contraseña") {
                        SecureField("Nueva contraseña", text: $form.newPasswordConfirmation)
                            .newPasswordContentType()
                            .onSubmit(submit)
                    }
                    ErrorText(message: error ?? (triedToSubmit ? form.firstIssue?.message : nil))
                    Button(action: submit) {
                        if isWorking { ProgressView().tint(Palette.onAccent) } else { Text("Cambiar la contraseña") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isWorking)
                }
                .padding(Spacing.s16)
            }
            .background(Palette.bgGrouped)
            .navigationTitle("Contraseña")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }

    private func submit() {
        triedToSubmit = true
        error = nil
        guard form.firstIssue == nil, !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await session.changePassword(form)
                onChanged()
                dismiss()
            } catch let appError as AppError {
                error = appError.errorDescription
            } catch {
                self.error = AppError.unknown("").errorDescription
            }
        }
    }
}
