import SwiftUI
import Charts
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
                NavigationLink {
                    NetWorthView()
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.s8) {
                        HStack {
                            Eyebrow("Patrimonio neto")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(Typography.footnote)
                                .foregroundStyle(Palette.labelSecondary)
                        }
                        Text(finance.totalBalance.formatted())
                            .titleFont(.largeTitle)
                            .foregroundStyle(finance.totalBalance.isNegative ? Palette.negativeText : Palette.label)
                            .contentTransition(.numericText())
                        Text(netWorthChangeText)
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.labelSecondary)
                        Text("Lo que tienes menos lo que debes. Toca para ver cómo evoluciona.")
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.labelSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .card()
                }
                .buttonStyle(.plain)

                PendingChargesCard()

                SpendTodayCard()

                VStack(alignment: .leading, spacing: Spacing.s8) {
                    Eyebrow("Gastado este mes")
                    Text(MonthSummary.spent(movements: finance.recent, categories: finance.categories,
                                            monthStartDay: finance.household.monthStartDay).formatted())
                        .titleFont(.title1)
                        .foregroundStyle(Palette.label)
                        .contentTransition(.numericText())
                    Text("Sin contar traspasos entre tus cuentas.")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                .accessibilityElement(children: .combine)

                NextPaymentsCard()

                FavoriteExtraBudgetCard()

                WeeklySummaryCard()

                AdaptiveColumns {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        HStack {
                            Text("Cuentas")
                                .titleFont(.title2)
                                .foregroundStyle(Palette.label)
                            Spacer()
                            Button("Añadir", systemImage: "plus") { addingAccount = true }
                                .labelStyle(.titleAndIcon)
                                .font(Typography.subheadlineEmphasis)
                        }
                        if finance.activeAccounts.isEmpty {
                            EmptyHint(text: finance.isLoading ? "Cargando…" : "Añade tu primera cuenta para empezar a apuntar movimientos o importar un CSV del banco.")
                        }
                        ForEach(finance.activeAccounts) { account in
                            NavigationLink(value: account) {
                                AccountRow(account: account, balance: finance.balance(of: account))
                            }
                            .buttonStyle(.plain)
                        }
                        if !finance.archivedAccounts.isEmpty {
                            DisclosureGroup("Archivadas (\(finance.archivedAccounts.count))") {
                                ForEach(finance.archivedAccounts) { account in
                                    NavigationLink(value: account) {
                                        AccountRow(account: account, balance: finance.balance(of: account))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, Spacing.s8)
                                }
                            }
                            .font(Typography.subheadlineEmphasis)
                            .foregroundStyle(Palette.labelSecondary)
                        }
                    }
                    .card()
                } trailing: {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        HStack {
                            Text("Últimos movimientos")
                                .titleFont(.title2)
                                .foregroundStyle(Palette.label)
                            Spacer()
                            NavigationLink("Ver todos") { MovementsView() }
                                .font(Typography.subheadlineEmphasis)
                        }
                        if finance.recent.isEmpty {
                            EmptyHint(text: finance.isLoading ? "Cargando…" : "Todavía no hay movimientos.")
                        }
                        ForEach(finance.recent.prefix(8)) { movement in
                            MovementRow(movement: movement, showsAccount: true)
                        }
                    }
                    .card()
                }

                ErrorText(message: finance.error)
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Resumen")
        .navigationDestination(for: Account.self) { AccountDetailView(account: $0) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nuevo movimiento", systemImage: "plus") { addingMovement = true }
                    .disabled(finance.activeAccounts.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) { IncognitoButton() }
        }
        .refreshable { await finance.load() }
        .sheet(isPresented: $addingAccount) { AccountFormView(account: nil) }
        .sheet(isPresented: $addingMovement) { MovementFormView(movement: nil, accountId: nil) }
    }

    /// "+120 € este mes", como en Android.
    private var netWorthChangeText: String {
        let change = MonthSummary.netWorthChange(accounts: finance.accounts, movements: finance.recent,
                                                 monthStartDay: finance.household.monthStartDay)
        if change.minor == 0 { return "Igual que a final del mes pasado" }
        return (change.isNegative ? "−" : "+") + Money(minor: abs(change.minor)).formatted() + " este mes"
    }
}

struct AccountRow: View {
    let account: Account
    let balance: Money

    var body: some View {
        HStack(spacing: Spacing.s16) {
            Image(systemName: account.kind.systemImage)
                .frame(width: 32, height: 32)
                .foregroundStyle(Palette.label)
                .background(Palette.bgGrouped, in: RoundedRectangle(cornerRadius: Radius.input))
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(Typography.headline)
                    .foregroundStyle(Palette.label)
                Text(account.isShared ? "\(account.kind.title) · compartida" : account.kind.title)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer()
            Text(balance.formatted())
                .font(Typography.headline.monospacedDigit())
                .foregroundStyle(balance.isNegative ? Palette.negativeText : Palette.label)
                .lineLimit(1)
                .fixedSize()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct MovementRow: View {
    let movement: Movement
    var showsAccount = false
    /// En la lista agrupada por día la fecha ya está en la cabecera.
    var showsDate = true

    @Environment(FinanceModel.self) private var finance

    private var subtitle: String {
        var parts = showsDate ? [movement.bookedOn.shortText] : []
        if let category = finance.category(movement.categoryId) { parts.append(category.name) }
        if showsAccount, let account = finance.account(movement.accountId) { parts.append(account.name) }
        if let counterpart = transferCounterpart { parts.append(counterpart) }
        if let payee = movement.payee { parts.append(payee) }
        if !movement.tags.isEmpty { parts.append(movement.tags.map { "#" + $0 }.joined(separator: " ")) }
        return parts.joined(separator: " · ")
    }

    /// En una pata de transferencia, la cuenta de la otra pata: «Hacia Ahorro» o «Desde Nómina». La otra pata se
    /// busca en los recientes y en las páginas cargadas de la lista; si no está en ninguno, no se pone.
    private var transferCounterpart: String? {
        guard let transferId = movement.transferId,
              let other = finance.recent.first(where: { $0.transferId == transferId && $0.id != movement.id })
                ?? finance.list.rows.first(where: { $0.transferId == transferId && $0.id != movement.id }),
              let account = finance.account(other.accountId) else { return nil }
        return (movement.isExpense ? "Hacia " : "Desde ") + account.name
    }

    @AppStorage(DisplayPreferences.plusSignKey) private var showsPlusSign = false
    @AppStorage(DisplayPreferences.colorAmountsKey) private var colorsAmounts = true

    /// Ingresos en verde y gastos en tinta; con «Colorear importes» apagado, todo en tinta.
    private var amountColor: Color {
        guard colorsAmounts else { return Palette.label }
        return movement.isExpense ? Palette.label : Palette.positiveText
    }

    var body: some View {
        HStack(spacing: Spacing.s16) {
            MerchantBadge(description: movement.description, categoryIcon: finance.category(movement.categoryId)?.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(MovementText.display(movement.description))
                    .font(Typography.body)
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(showsPlusSign ? movement.amount.signedText() : movement.amount.formatted())
                    .font(Typography.headline)
                    .foregroundStyle(movement.excluded ? Palette.labelSecondary : amountColor)
                    .strikethrough(movement.excluded)
                if movement.excluded || movement.isReviewed {
                    HStack(spacing: Spacing.s4) {
                        if movement.excluded {
                            Image(systemName: "eye.slash")
                                .accessibilityLabel("Excluido del presupuesto")
                        }
                        if movement.isReviewed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Palette.positiveText)
                                .accessibilityLabel("Revisado")
                        }
                    }
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Texto gris para listas vacías.
struct EmptyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.subheadline)
            .foregroundStyle(Palette.labelSecondary)
    }
}

/// Lista de movimientos agrupada por día (con lo que suma cada día), búsqueda por concepto o importe
/// y filtros de cuenta, tipo, categoría y fechas. Sin cuenta: todos los del hogar.
struct MovementsView: View {
    var account: Account?

    @Environment(FinanceModel.self) private var finance
    @State private var filter = MovementFilter()
    @State private var customFrom = CalendarDay.gregorian.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customThrough = Date()
    @State private var editing: Movement?
    /// Pata de transferencia que se va a borrar: antes se avisa de que se borran las dos.
    @State private var deletingTransfer: Movement?
    @State private var adding = false
    @State private var transferring = false
    /// Modo «Seleccionar»: tocar marca en vez de abrir, y abajo salen las acciones para todos.
    @State private var selecting = false
    @State private var selection = Set<UUID>()
    @State private var bulkEditing = false
    @State private var confirmingBulkDelete = false

    private var selectedMovements: [Movement] { filtered.filter { selection.contains($0.id) } }

    /// Las filas cargadas de esta lista (ORC-85). Si el modelo tiene abierta otra (la de otra cuenta), ninguna.
    private var source: [Movement] { isThisList ? finance.list.rows : [] }

    private var isThisList: Bool { finance.list.accountId == account?.id }

    /// La búsqueda la hace el servidor; lo demás se filtra aquí, sobre lo cargado.
    private var effectiveFilter: MovementFilter {
        var current = filter
        current.search = ""
        if let account { current.accountId = account.id }
        if current.dates == .custom {
            current.customFrom = CalendarDay(customFrom)
            current.customThrough = CalendarDay(customThrough)
        }
        return current
    }

    private var filtered: [Movement] {
        effectiveFilter.apply(to: source, categories: finance.categories, monthStartDay: finance.household.monthStartDay)
    }

    private var isFiltering: Bool {
        filter.activeCount > 0 || !filter.search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        let days = MovementDay.group(filtered, categories: finance.categories)
        List {
            if filter.dates == .custom {
                Section {
                    DatePicker("Desde", selection: $customFrom, displayedComponents: .date)
                    DatePicker("Hasta", selection: $customThrough, displayedComponents: .date)
                }
                .environment(\.locale, Locale(identifier: "es_ES"))
            }
            if source.isEmpty {
                if finance.listError == nil {
                    EmptyHint(text: finance.isLoading || finance.isLoadingList || !isThisList ? "Cargando…" : emptyText)
                }
            } else if isFiltering {
                Section {
                    filterSummary
                }
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.movements) { movement in
                        Button {
                            if selecting { toggleSelection(movement) } else { editing = movement }
                        } label: {
                            HStack(spacing: Spacing.s12) {
                                if selecting {
                                    Image(systemName: selection.contains(movement.id) ? "checkmark.circle.fill" : "circle")
                                        .font(Typography.headline)
                                        .foregroundStyle(selection.contains(movement.id) ? Palette.accent : Palette.labelSecondary)
                                        .accessibilityHidden(true)
                                }
                                MovementRow(movement: movement, showsAccount: account == nil, showsDate: false)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selecting && selection.contains(movement.id) ? .isSelected : [])
                        .swipeActions(edge: .leading) {
                            Button(movement.isReviewed ? "Sin revisar" : "Revisado",
                                   systemImage: movement.isReviewed ? "circle" : "checkmark.circle") {
                                Task { await finance.update(MovementBulkEdit(reviewed: !movement.isReviewed).changes(for: [movement])) }
                            }
                            .tint(Palette.positive)
                        }
                        .swipeActions {
                            Button("Borrar", systemImage: "trash", role: .destructive) {
                                Task { await delete(movement) }
                            }
                            // Duplicar una pata apuntaría solo un lado de la transferencia.
                            if movement.transferId == nil {
                                Button("Duplicar", systemImage: "plus.square.on.square") {
                                    Task { await duplicate(movement) }
                                }
                            }
                        }
                        .contextMenu {
                            Button("Editar", systemImage: "pencil") { editing = movement }
                            Button(movement.isReviewed ? "Marcar sin revisar" : "Marcar revisado",
                                   systemImage: movement.isReviewed ? "circle" : "checkmark.circle") {
                                Task { await finance.update(MovementBulkEdit(reviewed: !movement.isReviewed).changes(for: [movement])) }
                            }
                            Button(movement.excluded ? "Volver a contar en el presupuesto" : "Excluir del presupuesto",
                                   systemImage: movement.excluded ? "eye" : "eye.slash") {
                                Task { await finance.update(MovementBulkEdit(excluded: !movement.excluded).changes(for: [movement])) }
                            }
                            // Duplicar una pata apuntaría solo un lado de la transferencia.
                            if movement.transferId == nil {
                                Button("Duplicar", systemImage: "plus.square.on.square") {
                                    Task { await duplicate(movement) }
                                }
                            }
                            Divider()
                            Button("Borrar", systemImage: "trash", role: .destructive) {
                                Task { await delete(movement) }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(day.day.dayHeader)
                        Spacer()
                        if day.total.minor != 0 {
                            Text(day.total.signedText())
                                .monospacedDigit()
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if isThisList { listFooter }
        }
        .searchable(text: $filter.search, prompt: "Buscar concepto, beneficiario, #etiqueta o importe")
        .brandBackground()
        .navigationTitle(account?.name ?? "Movimientos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nuevo movimiento", systemImage: "plus") { adding = true }
                    .disabled(finance.activeAccounts.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Transferencia", systemImage: "arrow.left.arrow.right") { transferring = true }
                    .disabled(finance.activeAccounts.count < 2)
            }
            ToolbarItem(placement: .secondaryAction) { filterMenu }
            ToolbarItem(placement: .secondaryAction) {
                Button(selecting ? "Terminar selección" : "Seleccionar",
                       systemImage: selecting ? "checkmark.circle.badge.xmark" : "checkmark.circle") {
                    selecting.toggle()
                    selection = []
                }
                .disabled(source.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) { selecting ? AnyView(selectionBar) : AnyView(undoBar) }
        .sheet(isPresented: $bulkEditing) {
            BulkEditView(movements: selectedMovements) { selection = []; selecting = false }
        }
        .confirmationDialog(selection.count == 1 ? "¿Borrar 1 movimiento?" : "¿Borrar \(selection.count) movimientos?",
                            isPresented: $confirmingBulkDelete, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                Task {
                    if await finance.delete(selectedMovements) {
                        selection = []
                        selecting = false
                    }
                }
            }
        } message: {
            Text(selectedMovements.contains { $0.transferId != nil }
                 ? "Las transferencias se borran con sus dos movimientos, el de cada cuenta. No se puede deshacer."
                 : "No se puede deshacer.")
        }
        .confirmationDialog("¿Borrar la transferencia?",
                            isPresented: Binding(get: { deletingTransfer != nil }, set: { if !$0 { deletingTransfer = nil } }),
                            titleVisibility: .visible, presenting: deletingTransfer) { movement in
            Button("Borrar los dos movimientos", role: .destructive) {
                Task { await finance.delete(movement) }
            }
        } message: { _ in
            Text(TransferDraft.deleteWarning)
        }
        .task(id: ListKey(accountId: account?.id, search: filter.search)) {
            // Al escribir, espera a que se pare un momento antes de preguntar al servidor.
            if finance.list.search != filter.search { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await finance.showList(accountId: account?.id, search: filter.search)
        }
        .refreshable { await finance.load() }
        .sheet(item: $editing) { MovementFormView(movement: $0, accountId: nil) }
        .sheet(isPresented: $adding) { MovementFormView(movement: nil, accountId: account?.id) }
        .sheet(isPresented: $transferring) { TransferFormView(fromId: account?.id) }
    }

    /// "12 movimientos · −340,20 € gastos · +1.200,00 € ingresos" de lo filtrado.
    private var filterSummary: some View {
        let report = filtered
        let transfers = Set(finance.categories(for: .transfer).map(\.id))
        let counted = report.filter { !($0.categoryId.map(transfers.contains) ?? false) }
        let spent = Money(minor: counted.filter(\.amount.isNegative).reduce(0) { $0 + $1.amount.minor })
        let earned = Money(minor: counted.filter { !$0.amount.isNegative }.reduce(0) { $0 + $1.amount.minor })
        return VStack(alignment: .leading, spacing: Spacing.s4) {
            Text(report.count == 1 ? "1 movimiento" : "\(report.count) movimientos")
                .font(Typography.subheadlineEmphasis)
                .foregroundStyle(Palette.label)
            HStack(spacing: Spacing.s16) {
                Text("Gastos " + spent.signedText())
                Text("Ingresos " + earned.signedText())
            }
            .font(Typography.footnote)
            .foregroundStyle(Palette.labelSecondary)
            Button("Quitar filtros") {
                filter = MovementFilter()
            }
            .font(Typography.footnote)
        }
        .accessibilityElement(children: .contain)
    }

    private var filterMenu: some View {
        Menu {
            if account == nil {
                Picker("Cuenta", selection: $filter.accountId) {
                    Text("Todas las cuentas").tag(UUID?.none)
                    ForEach(finance.accounts) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            Picker("Tipo", selection: $filter.kind) {
                ForEach(MovementKindFilter.allCases) { Text($0.title).tag($0) }
            }
            Picker("Categoría", selection: $filter.categoryId) {
                Text("Todas las categorías").tag(UUID?.none)
                ForEach(finance.categories) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Fechas", selection: $filter.dates) {
                ForEach(MovementDateFilter.allCases) { Text($0.title).tag($0) }
            }
            Picker("Estado", selection: $filter.status) {
                ForEach(MovementStatusFilter.allCases) { Text($0.title).tag($0) }
            }
            let tags = MovementTags.all(in: source)
            if !tags.isEmpty || filter.tag != nil {
                Picker("Etiqueta", selection: $filter.tag) {
                    Text("Todas las etiquetas").tag(String?.none)
                    ForEach(tags, id: \.self) { Text("#" + $0).tag(Optional($0)) }
                }
            }
            if filter.activeCount > 0 {
                Divider()
                Button("Quitar filtros", systemImage: "xmark.circle") {
                    let search = filter.search
                    filter = MovementFilter(search: search)
                }
            }
        } label: {
            Label(filter.activeCount == 0 ? "Filtrar" : "Filtros (\(filter.activeCount))",
                  systemImage: filter.activeCount == 0 ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    /// «Movimiento eliminado · Deshacer», como el aviso de Android.
    @ViewBuilder
    private var undoBar: some View {
        if finance.lastDeleted != nil {
            HStack {
                Text("Movimiento eliminado")
                    .font(Typography.subheadline)
                    .foregroundStyle(Palette.label)
                Spacer()
                Button("Deshacer") { Task { await finance.undoDelete() } }
                    .font(Typography.subheadlineEmphasis)
                Button("Cerrar", systemImage: "xmark") { finance.lastDeleted = nil }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Palette.labelSecondary)
            }
            .padding(Spacing.s16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
            .padding(Spacing.s16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: finance.lastDeleted?.id) {
                try? await Task.sleep(for: .seconds(6))
                if !Task.isCancelled { finance.lastDeleted = nil }
            }
        }
    }

    private func toggleSelection(_ movement: Movement) {
        if selection.contains(movement.id) { selection.remove(movement.id) } else { selection.insert(movement.id) }
    }

    /// Abajo, en modo «Seleccionar»: cuántos hay y qué hacer con todos.
    private var selectionBar: some View {
        let chosen = selectedMovements
        return VStack(spacing: Spacing.s8) {
            HStack {
                Text(chosen.count == 1 ? "1 seleccionado" : "\(chosen.count) seleccionados")
                    .font(Typography.subheadlineEmphasis)
                    .foregroundStyle(Palette.label)
                Spacer()
                Button(chosen.count == filtered.count && !filtered.isEmpty ? "Ninguno" : "Todos") {
                    selection = chosen.count == filtered.count ? [] : Set(filtered.map(\.id))
                }
                .font(Typography.subheadline)
            }
            HStack(spacing: Spacing.s16) {
                Button("Revisado", systemImage: "checkmark.circle") {
                    Task { await finance.update(MovementBulkEdit(reviewed: true).changes(for: chosen)) }
                }
                Button("Editar", systemImage: "slider.horizontal.3") { bulkEditing = true }
                Spacer()
                Button("Borrar", systemImage: "trash", role: .destructive) { confirmingBulkDelete = true }
            }
            .font(Typography.subheadline)
            .disabled(chosen.isEmpty)
        }
        .padding(Spacing.s16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
        .padding(Spacing.s16)
    }

    private struct ListKey: Hashable {
        var accountId: UUID?
        var search: String
    }

    private var emptyText: String {
        filter.search.trimmingCharacters(in: .whitespaces).isEmpty
            ? "No hay movimientos. Apunta uno con + o importa un CSV desde Más opciones."
            : "Nada coincide con la búsqueda."
    }

    /// Al final de la lista: la página siguiente se pide al llegar aquí (y con el botón, si no se ha pedido sola).
    /// Si falla, el aviso y «Reintentar»: nunca parece que la lista se ha acabado.
    @ViewBuilder
    private var listFooter: some View {
        if let listError = finance.listError {
            Section {
                ErrorText(message: listError)
                Button("Reintentar") { Task { await finance.retryList() } }
                    .disabled(finance.isLoadingList)
            }
        } else if finance.list.hasMore {
            Button(finance.isLoadingList ? "Cargando…" : "Cargar más movimientos") {
                Task { await finance.loadMoreList() }
            }
            .disabled(finance.isLoadingList)
            .onAppear { Task { await finance.loadMoreList() } }
        }
    }

    private func delete(_ movement: Movement) async {
        if movement.transferId != nil {
            deletingTransfer = movement
        } else {
            await finance.delete(movement)
        }
    }

    /// Copia el movimiento tal cual (sin la huella del CSV, para que no cuente como importado), como en Android.
    private func duplicate(_ movement: Movement) async {
        let draft = MovementDraft(accountId: movement.accountId, categoryId: movement.categoryId,
                                  bookedOn: movement.bookedOn, amount: movement.amount,
                                  description: movement.description, notes: movement.notes,
                                  excluded: movement.excluded, payee: movement.payee, tags: movement.tags)
        await finance.add(draft)
    }
}

/// Detalle de una cuenta: saldo, sus movimientos y editarla.
struct AccountDetailView: View {
    let account: Account

    @Environment(FinanceModel.self) private var finance
    @State private var editing = false
    @State private var adjusting = false
    @State private var movements: [Movement] = []
    @State private var chartError: String?

    private var current: Account { finance.account(account.id) ?? account }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saldo")
                        .font(Typography.subheadlineEmphasis)
                        .foregroundStyle(Palette.labelSecondary)
                    Text(finance.balance(of: current).formatted())
                        .titleFont(.title1)
                        .foregroundStyle(finance.balance(of: current).isNegative ? Palette.negativeText : Palette.label)
                }
                Spacer()
            }
            .padding(Spacing.s16)
            .background(Palette.bgGrouped2)
            AccountBalanceChart(account: current, movements: movements)
                .padding(.horizontal, Spacing.s16)
                .padding(.bottom, Spacing.s12)
                .background(Palette.bgGrouped2)
            if let chartError {
                ErrorText(message: chartError)
                    .padding(.horizontal, Spacing.s16)
                    .padding(.bottom, Spacing.s12)
                    .background(Palette.bgGrouped2)
            }
            if current.kind == .creditCard {
                NavigationLink {
                    CreditCardDetailView(account: current)
                } label: {
                    Label("Próximo cargo, límite y aplazados", systemImage: "creditcard")
                        .font(Typography.subheadlineEmphasis)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.s16)
                        .padding(.vertical, Spacing.s12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accentText)
                .background(Palette.bgGrouped2)
            }
            MovementsView(account: current)
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button("Actualizar saldo", systemImage: "equal.circle") { adjusting = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Editar cuenta", systemImage: "pencil") { editing = true }
            }
        }
        .sheet(isPresented: $editing) { AccountFormView(account: current) }
        .sheet(isPresented: $adjusting) { BalanceAdjustmentView(account: current) }
        .task(id: finance.recent) {
            do {
                movements = try await finance.movements(of: current)
                chartError = nil
            } catch is CancellationError {
                return
            } catch {
                chartError = "No se han podido cargar los movimientos del gráfico. " + ((error as? AppError)?.errorDescription ?? "")
            }
        }
    }
}

extension CalendarDay {
    /// "Hoy", "Ayer" o "lunes, 3 de noviembre" para las cabeceras de la lista por días.
    var dayHeader: String {
        let today = CalendarDay()
        if self == today { return "Hoy" }
        if self == today.adding(days: -1) { return "Ayer" }
        let style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_ES"))
        let text = date().formatted(year == today.year ? style : style.year())
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "3 oct" para las filas.
    var shortText: String {
        date().formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_ES")))
    }
}

// MARK: Formularios

/// Crear o editar una cuenta.
struct AccountFormView: View {
    let account: Account?
    /// Tipo con el que empieza una cuenta nueva (p. ej. tarjeta, desde la pantalla de tarjetas).
    var initialKind: AccountKind = .checking

    @Environment(FinanceModel.self) private var finance
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: AccountKind = .checking
    @State private var openingBalance = ""
    @State private var isShared = true
    @State private var isDefault = false
    @State private var includeInNetWorth = true
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
            updated.isDefault = isDefault
            updated.includeInNetWorth = includeInNetWorth
            ok = await finance.updateAccount(updated)
        } else {
            ok = await finance.createAccount(draft)
            // Las dos opciones nuevas se guardan después de crearla (el alta sólo lleva lo básico).
            if ok, isDefault || !includeInNetWorth,
               var created = finance.accounts.last(where: { $0.name == draft.trimmedName && $0.kind == kind }) {
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
        if await finance.deleteAccount(account) { dismiss() } else { error = finance.error }
    }
}

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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }.disabled(isWorking)
                }
            }
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
                    let rate = cards.terms[card.id]?.installmentRate ?? 14
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

extension Money {
    /// "1250,5" -> "1250,50" sin símbolo, para rellenar un campo editable.
    var plainText: String {
        let sign = minor < 0 ? "-" : ""
        let value = abs(minor)
        return "\(sign)\(value / 100),\(String(format: "%02d", value % 100))"
    }
}

extension View {
    /// Concepto de un movimiento: se escribe en mayúsculas, como se enseña.
    func conceptInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.characters)
        #else
        self
        #endif
    }

    /// Teclado numérico con coma en iPhone.
    func decimalInput() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    /// Teclado de números enteros en iPhone.
    func numberInput() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad)
        #else
        self
        #endif
    }
}

/// Transferencia entre dos cuentas propias, como en Android.
struct TransferFormView: View {
    /// Cuenta de origen preseleccionada.
    let fromId: UUID?

    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var from: UUID?
    @State private var to: UUID?
    @State private var amount = ""
    @State private var concept = ""
    @State private var date = Date()
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Desde", selection: $from) {
                        ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Hacia", selection: $to) {
                        ForEach(finance.activeAccounts.filter { $0.id != from }) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section {
                    AmountField("Importe, p. ej. 200", text: $amount)
                    TextField("Concepto (opcional)", text: $concept)
                    DatePicker("Fecha", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "es_ES"))
                } footer: {
                    Text("Se apuntan dos movimientos con la categoría de transferencia. No cuentan como gasto ni como ingreso.")
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle("Transferencia")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }.disabled(isWorking)
                }
            }
            .onAppear {
                if from == nil { from = fromId ?? finance.defaultAccount?.id }
                if to == nil { to = finance.activeAccounts.first { $0.id != from }?.id }
            }
        }
    }

    private func save() async {
        error = nil
        guard let source = from.flatMap(finance.account), let target = to.flatMap(finance.account), source.id != target.id else {
            error = "Elige dos cuentas distintas."
            return
        }
        guard let money = Money(entered: amount), money.minor > 0 else {
            error = "Escribe un importe mayor que cero."
            return
        }
        isWorking = true
        defer { isWorking = false }
        if await finance.transfer(from: source, to: target, amount: money, on: CalendarDay(date), description: concept) {
            dismiss()
        } else {
            error = finance.error
        }
    }
}

/// Saldo de una cuenta al final de cada uno de los últimos 6 meses, como en Android.
struct AccountBalanceChart: View {
    let account: Account
    let movements: [Movement]

    private struct Point: Identifiable {
        var month: MonthKey
        var balance: Money
        var id: MonthKey { month }
    }

    var body: some View {
        let points = NetWorth.history(accounts: [account], movements: movements, months: 6, through: MonthKey(CalendarDay()))
            .map { Point(month: $0.month, balance: $0.net) }
        Chart(points) { point in
            LineMark(x: .value("Mes", point.month.firstDay.date(), unit: .month),
                     y: .value("Saldo", point.balance.decimal))
                .foregroundStyle(Palette.accent)
                .lineStyle(StrokeStyle(lineWidth: 2))
            PointMark(x: .value("Mes", point.month.firstDay.date(), unit: .month),
                      y: .value("Saldo", point.balance.decimal))
                .foregroundStyle(Palette.accent)
                .symbolSize(24)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .frame(height: 120)
        .accessibilityLabel("Saldo de la cuenta en los últimos 6 meses")
    }
}

/// «Actualizar saldo»: escribes lo que marca el banco y se apunta un ajuste por la diferencia.
struct BalanceAdjustmentView: View {
    let account: Account

    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var actual = ""
    @State private var error: String?
    @State private var isWorking = false

    private var current: Money { finance.balance(of: account) }

    private var difference: Money? {
        Money(entered: actual).map { Money(minor: $0.minor - current.minor) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Saldo en la app", value: current.formatted())
                    AmountField("Saldo real, p. ej. 1.250,00", text: $actual)
                    if let difference, difference.minor != 0 {
                        LabeledContent("Ajuste", value: difference.signedText())
                    }
                } footer: {
                    Text("Se apunta un movimiento «Ajuste de saldo» por la diferencia, hoy. No cuenta como gasto ni como ingreso.")
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle("Actualizar saldo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }.disabled(isWorking)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 300)
    }

    private func save() async {
        guard let money = Money(entered: actual) else {
            error = "Escribe el saldo, por ejemplo 1.250,00."
            return
        }
        isWorking = true
        defer { isWorking = false }
        if await finance.adjustBalance(of: account, to: money) { dismiss() } else { error = finance.error }
    }
}
