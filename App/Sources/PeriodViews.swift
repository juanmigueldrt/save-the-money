import SwiftUI
import STMCore
import STMUI

// MARK: «Puedes gastar hoy»

/// Cuánto puedes gastar hoy y cuántos días faltan para cobrar, del periodo en curso.
/// Sale en Resumen y arriba del presupuesto.
struct SpendTodayCard: View {
    @Environment(BudgetModel.self) private var budgets
    @Environment(FinanceModel.self) private var finance

    var body: some View {
        let insights = budgets.insights(categories: finance.categories)
        VStack(alignment: .leading, spacing: Spacing.s8) {
            Eyebrow("Puedes gastar hoy")
            Text(insights.perDay.formatted())
                .titleFont(.title1)
                .foregroundStyle(insights.left.isNegative ? Palette.negativeText : Palette.label)
                .contentTransition(.numericText())
            Text(detail(insights))
                .font(Typography.subheadline)
                .foregroundStyle(Palette.labelSecondary)
            Text(budgets.hasOwnSchedule ? budgets.schedule.summary : "Dinos cuándo cobras en Presupuesto › Día de cobro.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    private func detail(_ insights: PeriodInsights) -> String {
        let days = insights.daysToPayday == 1 ? "1 día" : "\(insights.daysToPayday) días"
        if insights.left.isNegative {
            return "Te has pasado \(Money(minor: -insights.left.minor).formatted()) · faltan \(days) para cobrar"
        }
        return "Te quedan \(insights.left.formatted()) · faltan \(days) para cobrar"
    }
}

/// ‹ 25 oct – 24 nov › compartido por presupuesto y flujo.
struct PeriodSwitcher: View {
    @Environment(BudgetModel.self) private var budgets

    var body: some View {
        HStack {
            Button("Periodo anterior", systemImage: "chevron.left") {
                Task { await budgets.showPrevious() }
            }
            .labelStyle(.iconOnly)
            Spacer()
            VStack(spacing: 2) {
                Text(budgets.period.title)
                    .titleFont(.title2)
                    .foregroundStyle(Palette.label)
                Text(subtitle)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
            }
            .onTapGesture { Task { await budgets.showCurrent() } }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Vuelve al periodo de hoy")
            Spacer()
            Button("Periodo siguiente", systemImage: "chevron.right") {
                Task { await budgets.showNext() }
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.label)
        .card()
    }

    private var subtitle: String {
        let range = "\(budgets.period.start.shortText) – \(budgets.period.end.shortText)"
        return budgets.isCurrentPeriod ? range + " · en curso" : range
    }
}

// MARK: Día de cobro

/// Cuándo cobras: de ahí salen los periodos del presupuesto. Sólo lo ves tú.
struct PayScheduleView: View {
    @Environment(BudgetModel.self) private var budgets
    @Environment(\.dismiss) private var dismiss
    @State private var frequency: PayFrequency = .monthly
    @State private var day1 = 1
    @State private var day2 = 15
    @State private var anchor = Date()
    @State private var error: String?
    @State private var isWorking = false

    private var schedule: PaySchedule {
        PaySchedule(frequency: frequency, day1: day1, day2: frequency == .twiceMonthly ? day2 : nil,
                    anchor: frequency.usesAnchor ? CalendarDay(anchor) : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Cobro", selection: $frequency) {
                        ForEach(PayFrequency.allCases) { Text($0.title).tag($0) }
                    }
                    switch frequency {
                    case .monthly:
                        Stepper("El día \(day1)", value: $day1, in: 1...31)
                    case .twiceMonthly:
                        Stepper("Primer día: \(day1)", value: $day1, in: 1...30)
                        Stepper("Segundo día: \(day2)", value: $day2, in: 2...31)
                    case .weekly, .biweekly, .yearly:
                        DatePicker("Un día que cobraste", selection: $anchor, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "es_ES"))
                    }
                } footer: {
                    Text("El presupuesto va de un cobro al día antes del siguiente. Si cobras un día 31 y el mes es más corto, cuenta el último día. Sólo lo ves tú.")
                }
                if schedule.issue == nil {
                    Section("Periodo de hoy") {
                        let period = schedule.period(containing: CalendarDay())
                        LabeledContent("Del", value: period.start.shortText)
                        LabeledContent("Al", value: period.end.shortText)
                    }
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle("Día de cobro")
            .formToolbar(isWorking: isWorking, cancel: { dismiss() }, save: { await save() })
        }
        .frame(minWidth: 360, minHeight: 360)
        .onAppear(perform: fill)
    }

    private func fill() {
        let current = budgets.schedule
        frequency = current.frequency
        day1 = current.day1
        day2 = current.day2 ?? max(15, current.day1 + 1)
        anchor = (current.anchor ?? CalendarDay()).date()
    }

    private func save() async {
        if let issue = schedule.issue { error = issue; return }
        isWorking = true
        defer { isWorking = false }
        if await budgets.save(schedule) { dismiss() } else { error = budgets.error }
    }
}

// MARK: Presupuestos extra

/// Presupuestos aparte del del periodo (p. ej. «Vacaciones»), con lo gastado en cada uno.
struct ExtraBudgetsSection: View {
    @Environment(BudgetModel.self) private var budgets
    @Environment(FinanceModel.self) private var finance
    @State private var editing: ExtraBudget?
    @State private var spentById: [UUID: Money] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            HStack {
                Text("Presupuestos extra")
                    .titleFont(.title2)
                    .foregroundStyle(Palette.label)
                Spacer()
                Button("Añadir", systemImage: "plus") {
                    editing = ExtraBudget(householdId: budgets.household.id, startsOn: budgets.period.start)
                }
                .labelStyle(.titleAndIcon)
                .font(Typography.subheadlineEmphasis)
            }
            if budgets.extraBudgets.isEmpty {
                EmptyHint(text: "Para controlar un gasto concreto aparte del presupuesto: unas vacaciones, una reforma o los regalos de Navidad.")
            }
            ForEach(budgets.extraBudgets) { extra in
                Button { editing = extra } label: {
                    ExtraBudgetRow(extra: extra, spent: spentById[extra.id] ?? .zero)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
        .task(id: budgets.extraBudgets) { await refreshSpent() }
        .task(id: finance.recent) { await refreshSpent() }
        .sheet(item: $editing) { ExtraBudgetFormView(extra: $0) }
    }

    private func refreshSpent() async {
        var result: [UUID: Money] = [:]
        for extra in budgets.extraBudgets {
            let list = await budgets.movements(for: extra)
            result[extra.id] = extra.spent(movements: list, categories: finance.categories)
        }
        spentById = result
    }
}

struct ExtraBudgetRow: View {
    let extra: ExtraBudget
    let spent: Money

    private var fraction: Double {
        guard extra.limit.minor > 0 else { return 0 }
        return min(1, max(0, Double(spent.minor) / Double(extra.limit.minor)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            HStack {
                Label(extra.name, systemImage: extra.isFavorite ? "star.fill" : "flag")
                    .font(Typography.subheadlineEmphasis)
                    .foregroundStyle(Palette.label)
                Spacer()
                Text("\(spent.formatted()) de \(extra.limit.formatted())")
                    .font(Typography.subheadline)
                    .foregroundStyle(spent.minor > extra.limit.minor ? Palette.negativeText : Palette.labelSecondary)
            }
            ProgressBar(fraction: fraction)
            Text(dates)
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var dates: String {
        if let end = extra.endsOn { return "Del \(extra.startsOn.shortText) al \(end.shortText)" }
        return "Desde el \(extra.startsOn.shortText), sin fecha de fin"
    }
}

/// Crear o editar un presupuesto extra.
struct ExtraBudgetFormView: View {
    let extra: ExtraBudget

    @Environment(BudgetModel.self) private var budgets
    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var limit = ""
    @State private var start = Date()
    @State private var hasEnd = false
    @State private var end = Date()
    @State private var categoryIds = Set<UUID>()
    @State private var accountIds = Set<UUID>()
    @State private var isFavorite = false
    @State private var error: String?
    @State private var isWorking = false
    @State private var confirmingDelete = false

    private var isNew: Bool { !budgets.extraBudgets.contains { $0.id == extra.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre, p. ej. Vacaciones", text: $name)
                    AmountField("Límite, p. ej. 800,00", text: $limit)
                    Toggle("Favorito (sale en Resumen)", isOn: $isFavorite)
                }
                Section {
                    DatePicker("Desde", selection: $start, displayedComponents: .date)
                    Toggle("Con fecha de fin", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Hasta", selection: $end, in: start..., displayedComponents: .date)
                    }
                }
                .environment(\.locale, Locale(identifier: "es_ES"))
                Section {
                    ForEach(finance.categories(for: .expense)) { category in
                        Toggle(category.name, isOn: binding(category.id, in: $categoryIds))
                    }
                } header: {
                    Text("Categorías")
                } footer: {
                    Text(categoryIds.isEmpty ? "Si no eliges ninguna, cuenta todo el gasto." : "\(categoryIds.count) elegidas.")
                }
                Section {
                    ForEach(finance.activeAccounts) { account in
                        Toggle(account.name, isOn: binding(account.id, in: $accountIds))
                    }
                } header: {
                    Text("Cuentas")
                } footer: {
                    Text(accountIds.isEmpty ? "Si no eliges ninguna, cuentan todas." : "\(accountIds.count) elegidas.")
                }
                if !isNew {
                    Section {
                        Button("Borrar presupuesto extra", role: .destructive) { confirmingDelete = true }
                    }
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle(isNew ? "Nuevo presupuesto extra" : extra.name)
            .formToolbar(isWorking: isWorking, cancel: { dismiss() }, save: { await save() })
            .confirmationDialog("¿Borrar «\(extra.name)»?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) {
                    Task { if await budgets.delete(extra) { dismiss() } else { error = budgets.error } }
                }
            } message: {
                Text("Los movimientos no se borran.")
            }
        }
        .frame(minWidth: 380, minHeight: 480)
        .onAppear(perform: fill)
    }

    private func binding(_ id: UUID, in set: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding { set.wrappedValue.contains(id) } set: { on in
            if on { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) }
        }
    }

    private func fill() {
        name = extra.name
        limit = extra.limit.minor == 0 ? "" : extra.limit.plainText
        start = extra.startsOn.date()
        hasEnd = extra.endsOn != nil
        end = (extra.endsOn ?? extra.startsOn.adding(days: 30)).date()
        categoryIds = Set(extra.categoryIds)
        accountIds = Set(extra.accountIds)
        isFavorite = extra.isFavorite
    }

    private func save() async {
        guard let amount = Money(entered: limit), amount.minor > 0 else {
            error = "Escribe un límite, por ejemplo 800,00."
            return
        }
        var updated = extra
        updated.name = name
        updated.limit = amount
        updated.startsOn = CalendarDay(start)
        updated.endsOn = hasEnd ? CalendarDay(end) : nil
        updated.categoryIds = categoryIds.sorted { $0.uuidString < $1.uuidString }
        updated.accountIds = accountIds.sorted { $0.uuidString < $1.uuidString }
        updated.isFavorite = isFavorite
        if let issue = updated.issue { error = issue; return }
        isWorking = true
        defer { isWorking = false }
        if await budgets.save(updated) { dismiss() } else { error = budgets.error }
    }
}

/// El presupuesto extra favorito, en Resumen.
struct FavoriteExtraBudgetCard: View {
    @Environment(BudgetModel.self) private var budgets
    @Environment(FinanceModel.self) private var finance
    @State private var spent: Money = .zero

    var body: some View {
        if let favorite = budgets.extraBudgets.first(where: \.isFavorite) {
            ExtraBudgetRow(extra: favorite, spent: spent)
                .card()
                .task(id: favorite) {
                    let list = await budgets.movements(for: favorite)
                    spent = favorite.spent(movements: list, categories: finance.categories)
                }
                .task(id: finance.recent) {
                    let list = await budgets.movements(for: favorite)
                    spent = favorite.spent(movements: list, categories: finance.categories)
                }
        }
    }
}
