import SwiftUI
import STMCore
import STMUI

/// Resumen: saldo total, cuentas y últimos movimientos.
struct SummaryView: View {
    @Environment(FinanceModel.self) private var finance
    @State private var addingAccount = false
    @State private var addingMovement = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    Text("Saldo total")
                        .font(Typography.body14Medium)
                        .foregroundStyle(Palette.graphite)
                    Text(finance.totalBalance.formatted())
                        .font(Typography.title36)
                        .foregroundStyle(finance.totalBalance.isNegative ? Palette.red : Palette.ink)
                        .contentTransition(.numericText())
                }
                .card()

                VStack(alignment: .leading, spacing: Spacing.s16) {
                    HStack {
                        Text("Cuentas")
                            .font(Typography.title20)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Button("Añadir", systemImage: "plus") { addingAccount = true }
                            .labelStyle(.titleAndIcon)
                            .font(Typography.body14Medium)
                    }
                    if finance.activeAccounts.isEmpty {
                        EmptyHint(text: "Añade tu primera cuenta para empezar a apuntar movimientos o importar un CSV del banco.")
                    }
                    ForEach(finance.activeAccounts) { account in
                        NavigationLink(value: account) {
                            AccountRow(account: account, balance: finance.balance(of: account))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: Spacing.s16) {
                    HStack {
                        Text("Últimos movimientos")
                            .font(Typography.title20)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        NavigationLink("Ver todos") { MovementsView() }
                            .font(Typography.body14Medium)
                    }
                    if finance.recent.isEmpty {
                        EmptyHint(text: "Todavía no hay movimientos.")
                    }
                    ForEach(finance.recent.prefix(8)) { movement in
                        MovementRow(movement: movement, showsAccount: true)
                    }
                }
                .card()

                ErrorText(message: finance.error)
            }
            .padding(Spacing.s16)
        }
        .background(Palette.linen)
        .navigationTitle("Resumen")
        .navigationDestination(for: Account.self) { AccountDetailView(account: $0) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nuevo movimiento", systemImage: "plus.circle.fill") { addingMovement = true }
                    .disabled(finance.activeAccounts.isEmpty)
            }
        }
        .refreshable { await finance.load() }
        .sheet(isPresented: $addingAccount) { AccountFormView(account: nil) }
        .sheet(isPresented: $addingMovement) { MovementFormView(movement: nil, accountId: nil) }
    }
}

struct AccountRow: View {
    let account: Account
    let balance: Money

    var body: some View {
        HStack(spacing: Spacing.s16) {
            Image(systemName: account.kind.systemImage)
                .frame(width: 32, height: 32)
                .foregroundStyle(Palette.ink)
                .background(Palette.linen, in: RoundedRectangle(cornerRadius: Radius.input))
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(Typography.body16Medium)
                    .foregroundStyle(Palette.ink)
                Text(account.isShared ? "\(account.kind.title) · compartida" : account.kind.title)
                    .font(Typography.small12)
                    .foregroundStyle(Palette.graphite)
            }
            Spacer()
            Text(balance.formatted())
                .font(Typography.body16Medium)
                .foregroundStyle(balance.isNegative ? Palette.red : Palette.ink)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct MovementRow: View {
    let movement: Movement
    var showsAccount = false

    @Environment(FinanceModel.self) private var finance

    private var subtitle: String {
        var parts = [movement.bookedOn.shortText]
        if let category = finance.category(movement.categoryId) { parts.append(category.name) }
        if showsAccount, let account = finance.account(movement.accountId) { parts.append(account.name) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Spacing.s16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(movement.description)
                    .font(Typography.body16)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Typography.small12)
                    .foregroundStyle(Palette.graphite)
                    .lineLimit(1)
            }
            Spacer()
            Text(movement.amount.formatted())
                .font(Typography.body16Medium)
                .foregroundStyle(movement.isExpense ? Palette.ink : Palette.ember)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Texto gris para listas vacías.
struct EmptyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.body14)
            .foregroundStyle(Palette.graphite)
    }
}

/// Lista de movimientos agrupada por mes, con búsqueda. Sin cuenta: todos los del hogar.
struct MovementsView: View {
    var account: Account?

    @Environment(FinanceModel.self) private var finance
    @State private var accountMovements: [Movement] = []
    @State private var search = ""
    @State private var editing: Movement?
    @State private var adding = false

    private var source: [Movement] { account == nil ? finance.recent : accountMovements }

    private var filtered: [Movement] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return source }
        return source.filter {
            $0.description.localizedCaseInsensitiveContains(query)
                || (finance.category($0.categoryId)?.name.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var months: [(key: MonthKey, items: [Movement])] {
        Dictionary(grouping: filtered) { MonthKey(year: $0.bookedOn.year, month: $0.bookedOn.month) }
            .map { (key: $0.key, items: $0.value) }
            .sorted { $0.key > $1.key }
    }

    var body: some View {
        List {
            if source.isEmpty {
                EmptyHint(text: "No hay movimientos. Apunta uno con + o importa un CSV desde Más opciones.")
            }
            ForEach(months, id: \.key) { month in
                Section(month.key.title) {
                    ForEach(month.items) { movement in
                        Button { editing = movement } label: {
                            MovementRow(movement: movement, showsAccount: account == nil)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Borrar", systemImage: "trash", role: .destructive) {
                                Task { await delete(movement) }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Buscar concepto o categoría")
        .navigationTitle(account?.name ?? "Movimientos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nuevo movimiento", systemImage: "plus.circle.fill") { adding = true }
                    .disabled(finance.activeAccounts.isEmpty)
            }
        }
        .task(id: finance.recent) { await reloadAccount() }
        .refreshable { await finance.load() }
        .sheet(item: $editing) { MovementFormView(movement: $0, accountId: nil) }
        .sheet(isPresented: $adding) { MovementFormView(movement: nil, accountId: account?.id) }
    }

    private func reloadAccount() async {
        guard let account else { return }
        accountMovements = await finance.movements(of: account)
    }

    private func delete(_ movement: Movement) async {
        await finance.delete(movement)
    }
}

/// Detalle de una cuenta: saldo, sus movimientos y editarla.
struct AccountDetailView: View {
    let account: Account

    @Environment(FinanceModel.self) private var finance
    @State private var editing = false

    private var current: Account { finance.account(account.id) ?? account }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saldo")
                        .font(Typography.body14Medium)
                        .foregroundStyle(Palette.graphite)
                    Text(finance.balance(of: current).formatted())
                        .font(Typography.title32)
                        .foregroundStyle(finance.balance(of: current).isNegative ? Palette.red : Palette.ink)
                }
                Spacer()
            }
            .padding(Spacing.s16)
            .background(Palette.paper)
            MovementsView(account: current)
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button("Editar cuenta", systemImage: "pencil") { editing = true }
            }
        }
        .sheet(isPresented: $editing) { AccountFormView(account: current) }
    }
}

struct MonthKey: Hashable, Comparable {
    let year: Int
    let month: Int

    var title: String {
        let date = CalendarDay(year: year, month: month, day: 1)?.date() ?? Date()
        return date.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "es_ES"))).capitalized
    }

    static func < (lhs: MonthKey, rhs: MonthKey) -> Bool { (lhs.year, lhs.month) < (rhs.year, rhs.month) }
}

extension CalendarDay {
    /// "3 oct" para las filas.
    var shortText: String {
        date().formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_ES")))
    }
}

// MARK: Formularios

/// Crear o editar una cuenta.
struct AccountFormView: View {
    let account: Account?

    @Environment(FinanceModel.self) private var finance
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: AccountKind = .checking
    @State private var openingBalance = ""
    @State private var isShared = true
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
                    TextField("Saldo inicial, p. ej. 1.250,00", text: $openingBalance)
                        .decimalInput()
                    Toggle("Compartida con el hogar", isOn: $isShared)
                } footer: {
                    Text("El saldo inicial es lo que había en la cuenta antes del primer movimiento que apuntes o importes.")
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
            .navigationTitle(account == nil ? "Nueva cuenta" : "Editar cuenta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }.disabled(isWorking)
                }
            }
            .confirmationDialog("¿Borrar esta cuenta?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Borrar cuenta y movimientos", role: .destructive) { Task { await delete() } }
            } message: {
                Text("Se borran también todos sus movimientos, para todo el hogar. No se puede deshacer.")
            }
        }
        .frame(minWidth: 360, minHeight: 360)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let account else { return }
        name = account.name
        kind = account.kind
        openingBalance = account.openingBalance.minor == 0 ? "" : account.openingBalance.plainText
        isShared = account.isShared
    }

    private var parsedOpening: Money? {
        openingBalance.trimmingCharacters(in: .whitespaces).isEmpty ? .zero : Money(parsing: openingBalance)
    }

    private var ownerId: UUID? {
        guard !isShared else { return nil }
        if case .ready(let profile, _) = session.state { return account?.ownerId ?? profile.id }
        return nil
    }

    private func save() async {
        guard let opening = parsedOpening else { error = "El saldo inicial no es un importe válido."; return }
        let draft = AccountDraft(name: name, kind: kind, openingBalance: opening, ownerId: ownerId)
        if let issue = draft.issue { error = issue; return }
        isWorking = true
        defer { isWorking = false }
        let ok: Bool
        if var updated = account {
            updated.name = draft.trimmedName
            updated.kind = kind
            updated.openingBalance = opening
            updated.ownerId = draft.ownerId
            ok = await finance.updateAccount(updated)
        } else {
            ok = await finance.createAccount(draft)
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
        if await finance.deleteAccount(account) { dismiss() } else { error = finance.error }
    }
}

/// Apuntar o editar un movimiento.
struct MovementFormView: View {
    let movement: Movement?
    /// Cuenta preseleccionada al crear desde el detalle de una cuenta.
    let accountId: UUID?

    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var isExpense = true
    @State private var amount = ""
    @State private var concept = ""
    @State private var date = Date()
    @State private var selectedAccount: UUID?
    @State private var selectedCategory: UUID?
    @State private var notes = ""
    @State private var error: String?
    @State private var isWorking = false

    private var kind: CategoryKind { isExpense ? .expense : .income }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $isExpense) {
                        Text("Gasto").tag(true)
                        Text("Ingreso").tag(false)
                    }
                    .pickerStyle(.segmented)
                    TextField("Importe, p. ej. 12,50", text: $amount)
                        .decimalInput()
                    TextField("Concepto", text: $concept)
                    DatePicker("Fecha", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "es_ES"))
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
                if movement != nil {
                    Section {
                        Button("Borrar movimiento", role: .destructive) { Task { await delete() } }
                    }
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(movement == nil ? "Nuevo movimiento" : "Editar movimiento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }.disabled(isWorking)
                }
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

    private func fill() {
        selectedAccount = accountId ?? finance.activeAccounts.first?.id
        guard let movement else { return }
        isExpense = movement.isExpense
        amount = Money(minor: abs(movement.amount.minor)).plainText
        concept = movement.description
        date = movement.bookedOn.date()
        selectedAccount = movement.accountId
        selectedCategory = movement.categoryId
        notes = movement.notes ?? ""
    }

    private func save() async {
        guard let parsed = Money(parsing: amount), parsed.minor != 0 else {
            error = "Escribe un importe, por ejemplo 12,50."
            return
        }
        guard let accountId = selectedAccount else { error = "Elige una cuenta."; return }
        let signed = Money(minor: isExpense ? -abs(parsed.minor) : abs(parsed.minor))
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = MovementDraft(accountId: accountId, categoryId: selectedCategory, bookedOn: CalendarDay(date),
                                  amount: signed, description: concept,
                                  notes: trimmedNotes.isEmpty ? nil : trimmedNotes)
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
            ok = await finance.update(updated)
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

extension Money {
    /// "1250,5" -> "1250,50" sin símbolo, para rellenar un campo editable.
    var plainText: String {
        let sign = minor < 0 ? "-" : ""
        let value = abs(minor)
        return "\(sign)\(value / 100),\(String(format: "%02d", value % 100))"
    }
}

extension View {
    /// Teclado numérico con coma en iPhone.
    func decimalInput() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}
