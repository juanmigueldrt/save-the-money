import SwiftUI
import STMCore
import STMUI

/// Suscripciones, gastos esenciales e ingresos fijos del hogar, con los próximos cargos.
struct RecurringView: View {
    @Environment(PlanningModel.self) private var planning
    @State private var editing: RecurringSeries?
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                totals.card()
                upcomingCard.card()
                ForEach(RecurringKind.allCases, id: \.self) { kind in
                    kindCard(kind).card()
                }
                if !planning.archivedSeries.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text("Archivados")
                            .font(Typography.title20)
                            .foregroundStyle(Palette.ink)
                        ForEach(planning.archivedSeries) { item in
                            Button { editing = item } label: { RecurringRow(series: item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .card()
                }
                ErrorText(message: planning.error)
            }
            .padding(Spacing.s16)
        }
        .background(Palette.linen)
        .navigationTitle("Pagos fijos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nuevo pago fijo", systemImage: "plus.circle.fill") { adding = true }
            }
        }
        .refreshable { await planning.load() }
        .sheet(isPresented: $adding) { RecurringFormView(series: nil) }
        .sheet(item: $editing) { RecurringFormView(series: $0) }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text("Al mes")
                .font(Typography.body14Medium)
                .foregroundStyle(Palette.graphite)
            let fixed = planning.monthlyTotal(of: .subscription) + planning.monthlyTotal(of: .essential)
            Text(fixed.formatted())
                .font(Typography.title36)
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            HStack(spacing: Spacing.s16) {
                ForEach(RecurringKind.allCases, id: \.self) { kind in
                    VStack(alignment: .leading, spacing: Spacing.s8) {
                        Text(kind.pluralTitle)
                            .font(Typography.small12)
                            .foregroundStyle(Palette.graphite)
                        Text(planning.monthlyTotal(of: kind).formatted())
                            .font(Typography.body14Medium)
                            .foregroundStyle(Palette.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var upcomingCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text("Próximos 30 días")
                .font(Typography.title20)
                .foregroundStyle(Palette.ink)
            if planning.upcoming.isEmpty {
                EmptyHint(text: "No hay cargos en los próximos 30 días.")
            }
            ForEach(planning.upcoming.prefix(12)) { charge in
                HStack {
                    Label(charge.series.trimmedName, systemImage: charge.series.kind.systemImage)
                        .font(Typography.body14Medium)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.s8) {
                        Text(charge.series.signedAmount.formatted())
                            .font(Typography.body14Medium)
                            .foregroundStyle(Palette.ink)
                        Text(charge.due.shortText)
                            .font(Typography.small12)
                            .foregroundStyle(Palette.graphite)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func kindCard(_ kind: RecurringKind) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text(kind.pluralTitle)
                .font(Typography.title20)
                .foregroundStyle(Palette.ink)
            let items = planning.series(of: kind)
            if items.isEmpty {
                EmptyHint(text: hint(for: kind))
            }
            ForEach(items) { item in
                Button { editing = item } label: { RecurringRow(series: item) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func hint(for kind: RecurringKind) -> String {
        switch kind {
        case .subscription: "Apunta tus suscripciones (música, vídeo, gimnasio...) para ver cuánto suman y recibir un aviso antes de cada cobro."
        case .essential: "Alquiler, luz, agua, internet o la compra del mes: lo que se paga sí o sí."
        case .income: "La nómina u otros ingresos que llegan cada mes."
        }
    }
}

struct RecurringRow: View {
    let series: RecurringSeries

    var body: some View {
        HStack(spacing: Spacing.s16) {
            Image(systemName: series.kind.systemImage)
                .foregroundStyle(Palette.ember)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: Spacing.s8) {
                Text(series.trimmedName)
                    .font(Typography.body16Medium)
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(Typography.small12)
                    .foregroundStyle(Palette.graphite)
            }
            Spacer()
            Text(series.amount.formatted())
                .font(Typography.body14Medium)
                .foregroundStyle(Palette.ink)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [series.recurrence.title]
        if !series.isArchived, let next = series.nextDue(onOrAfter: CalendarDay()) {
            parts.append("próximo: \(next.shortText)")
        }
        if series.remindDaysBefore != nil { parts.append("con aviso") }
        return parts.joined(separator: " · ")
    }
}

/// Crear o editar un pago fijo.
struct RecurringFormView: View {
    let series: RecurringSeries?

    @Environment(PlanningModel.self) private var planning
    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: RecurringKind = .subscription
    @State private var amount = ""
    @State private var recurrence: Recurrence = .monthly
    @State private var startsOn = Date()
    @State private var hasEnd = false
    @State private var endsOn = Date()
    @State private var accountId: UUID?
    @State private var categoryId: UUID?
    @State private var reminds = true
    @State private var remindDays = 1
    @State private var error: String?
    @State private var isWorking = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre, p. ej. Plataforma de música", text: $name)
                    Picker("Tipo", selection: $kind) {
                        ForEach(RecurringKind.allCases, id: \.self) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    TextField("Importe, p. ej. 9,99", text: $amount)
                        .decimalInput()
                    Picker("Frecuencia", selection: $recurrence) {
                        ForEach(recurrenceOptions, id: \.self) { Text($0.title).tag($0) }
                    }
                    DatePicker(series == nil ? "Primer cargo" : "Desde", selection: $startsOn, displayedComponents: .date)
                    Toggle("Tiene fecha de fin", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Último cargo", selection: $endsOn, in: startsOn..., displayedComponents: .date)
                    }
                }
                Section {
                    Picker("Cuenta", selection: $accountId) {
                        Text("Sin cuenta").tag(UUID?.none)
                        ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Categoría", selection: $categoryId) {
                        Text("Sin categoría").tag(UUID?.none)
                        ForEach(finance.categories(for: kind == .income ? .income : .expense)) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                } footer: {
                    Text("Se comparte con todo el hogar.")
                }
                Section {
                    Toggle("Avisarme antes del cargo", isOn: $reminds)
                    if reminds {
                        Stepper(remindText, value: $remindDays, in: 0...14)
                    }
                } footer: {
                    Text("El aviso lo lanza este dispositivo a las 9:00. Puedes apagar todos los avisos en Más opciones.")
                }
                if let series {
                    Section {
                        Button(series.isArchived ? "Reactivar" : "Archivar (ya no se paga)") { Task { await toggleArchive() } }
                        Button("Borrar", role: .destructive) { confirmingDelete = true }
                    }
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(series == nil ? "Nuevo pago fijo" : "Editar pago fijo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }.disabled(isWorking)
                }
            }
            .confirmationDialog("¿Borrar este pago fijo?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) { Task { await delete() } }
            } message: {
                Text("Se borra para todo el hogar. Los movimientos ya apuntados no se tocan.")
            }
        }
        .frame(minWidth: 360, minHeight: 480)
        .onAppear(perform: fill)
        .onChange(of: kind) { _, newKind in
            // Una categoría de gasto no vale para un ingreso, y al revés.
            let wanted: CategoryKind = newKind == .income ? .income : .expense
            if let categoryId, finance.category(categoryId)?.kind != wanted { self.categoryId = nil }
        }
    }

    private var recurrenceOptions: [Recurrence] {
        Recurrence.common.contains(recurrence) ? Recurrence.common : Recurrence.common + [recurrence]
    }

    private var remindText: String {
        switch remindDays {
        case 0: "El mismo día"
        case 1: "1 día antes"
        default: "\(remindDays) días antes"
        }
    }

    private func fill() {
        guard let series else { return }
        name = series.name
        kind = series.kind
        amount = series.amount.plainText
        recurrence = series.recurrence
        startsOn = series.startsOn.date()
        hasEnd = series.endsOn != nil
        endsOn = series.endsOn?.date() ?? Date()
        accountId = series.accountId
        reminds = series.remindDaysBefore != nil
        remindDays = series.remindDaysBefore ?? 1
        categoryId = series.categoryId
    }

    private func build() -> RecurringSeries? {
        guard let money = Money(parsing: amount), money.minor > 0 else {
            error = "El importe no es válido."
            return nil
        }
        var item = series ?? RecurringSeries(householdId: planning.household.id, name: name, amount: money,
                                              startsOn: CalendarDay(startsOn))
        item.name = name
        item.kind = kind
        item.amount = money
        item.recurrence = recurrence
        item.startsOn = CalendarDay(startsOn)
        item.endsOn = hasEnd ? CalendarDay(endsOn) : nil
        item.accountId = accountId
        item.categoryId = categoryId
        item.remindDaysBefore = reminds ? remindDays : nil
        return item
    }

    private func save() async {
        guard let item = build() else { return }
        if let issue = item.issue { error = issue; return }
        isWorking = true
        defer { isWorking = false }
        if await planning.save(item) { dismiss() } else { error = planning.error }
    }

    private func toggleArchive() async {
        guard var item = series else { return }
        item.archivedAt = item.isArchived ? nil : Date()
        if await planning.save(item) { dismiss() } else { error = planning.error }
    }

    private func delete() async {
        guard let series else { return }
        if await planning.delete(series) { dismiss() } else { error = planning.error }
    }
}
