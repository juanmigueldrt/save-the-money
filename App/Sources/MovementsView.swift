import SwiftUI
import Charts
import STMCore
import STMUI

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
                .environment(\.locale, AppRegion.locale)
            }
            if source.isEmpty {
                if finance.listError == nil {
                    EmptyHint(text: finance.isLoading || finance.isLoadingList || !isThisList ? String(localized: "Cargando…") : emptyText)
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
        .navigationTitle(account?.name ?? String(localized: "Movimientos"))
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
        .confirmationDialog("¿Borrar \(selection.count) movimientos?",
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
                Text(String(localized: "Gastos ") + spent.signedText())
                Text(String(localized: "Ingresos ") + earned.signedText())
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
                Text("\(chosen.count) seleccionados")
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
            ? String(localized: "No hay movimientos. Apunta uno con + o importa un CSV desde Más opciones.")
            : String(localized: "Nada coincide con la búsqueda.")
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
