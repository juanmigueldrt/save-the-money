import SwiftUI
import STMCore
import STMUI

/// Secciones de la app. En iPhone son pestañas; en Mac, la barra lateral.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case summary, movements, creditCards, budget, cashFlow, netWorth, reports, subscriptions, goals, investments, creditScore, household, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: String(localized: "Resumen")
        case .movements: String(localized: "Movimientos")
        case .creditCards: String(localized: "Tarjetas")
        case .budget: String(localized: "Presupuesto")
        case .cashFlow: String(localized: "Flujo")
        case .netWorth: String(localized: "Patrimonio")
        case .reports: String(localized: "Informes")
        case .creditScore: String(localized: "Score crediticio")
        case .subscriptions: String(localized: "Pagos fijos")
        case .goals: String(localized: "Metas")
        case .investments: String(localized: "Inversiones")
        case .household: String(localized: "Hogar")
        case .more: String(localized: "Más opciones")
        }
    }

    var systemImage: String {
        switch self {
        case .summary: "house"
        case .movements: "list.bullet.rectangle"
        case .creditCards: "creditcard"
        case .budget: "chart.pie"
        case .cashFlow: "arrow.left.arrow.right"
        case .netWorth: "chart.line.uptrend.xyaxis"
        case .reports: "chart.bar.doc.horizontal"
        case .creditScore: "gauge.with.dots.needle.67percent"
        case .subscriptions: "repeat"
        case .goals: "flag"
        case .investments: "chart.line.uptrend.xyaxis.circle"
        case .household: "person.2"
        case .more: "ellipsis.circle"
        }
    }

    /// Pestañas del iPhone: movimientos y patrimonio se abren desde el resumen; el resto, desde Más opciones.
    static let phoneTabs: [AppSection] = [.summary, .budget, .cashFlow, .goals, .more]

    /// Barra lateral de Mac, agrupada como en el diseño.
    static let sidebarGroups: [(title: String, sections: [AppSection])] = [
        (String(localized: "Dinero"), [.summary, .movements, .creditCards, .budget, .cashFlow]),
        (String(localized: "Seguimiento"), [.netWorth, .reports, .creditScore]),
        (String(localized: "Planificación"), [.subscriptions, .goals, .investments]),
        (String(localized: "Hogar"), [.household, .more])
    ]
}

struct RootView: View {
    let profile: Profile
    let household: Household

    @Environment(SessionModel.self) private var session
    @State private var selection: AppSection? = {
        #if DEBUG
        if let section = ScreenshotMode.section { return section }
        #endif
        return .summary
    }()
    @State private var finance: FinanceModel
    @State private var budgets: BudgetModel
    @State private var planning: PlanningModel
    @State private var tracking: TrackingModel
    @State private var investments: InvestmentModel
    @State private var cards: CreditCardModel
    @State private var addingMovement = false
    /// Cambia en cada «Nuevo gasto» de Atajos para que el formulario salga siempre vacío.
    @State private var newMovementForm = UUID()
    @State private var router = QuickActionRouter.shared
    @State private var addingAccount = false
    @State private var importingCSV = false

    init(profile: Profile, household: Household, finance: FinanceModel, budgets: BudgetModel, planning: PlanningModel,
         tracking: TrackingModel, investments: InvestmentModel, cards: CreditCardModel) {
        self.profile = profile
        self.household = household
        _finance = State(initialValue: finance)
        _budgets = State(initialValue: budgets)
        _planning = State(initialValue: planning)
        _tracking = State(initialValue: tracking)
        _investments = State(initialValue: investments)
        _cards = State(initialValue: cards)
    }

    var body: some View {
        VStack(spacing: 0) {
            if session.isDemo { DemoBanner() }
            // Modo incógnito y sin céntimos: al cambiar se vuelve a pintar el contenido (los modelos se conservan).
            content.modifier(MoneyDisplayModifier())
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
        // Las hojas de los menús van dentro de los .environment para recibir los modelos.
        .sheet(isPresented: $addingMovement) { MovementFormView(movement: nil, accountId: nil).id(newMovementForm) }
        .sheet(isPresented: $addingAccount) { AccountFormView(account: nil) }
        .sheet(isPresented: $importingCSV) {
            NavigationStack {
                CSVImportView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { importingCSV = false } }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 560, minHeight: 520)
            #endif
        }
        // Atajos, Siri o un enlace savethemoney://nuevo-gasto: también si llegó antes de que
        // esta pantalla estuviera lista (app cerrada o cargando la sesión).
        .onChange(of: router.request, initial: true) { _, _ in handleQuickAction() }
        .focusedSceneValue(\.appActions, actions)
        .environment(finance)
        .environment(budgets)
        .environment(planning)
        .environment(tracking)
        .environment(investments)
        .environment(cards)
        .task { await finance.load() }
        // También reprograma los avisos de pagos cada vez que se abre la app.
        .task { await planning.load() }
        // Reprograma también los avisos de las aportaciones automáticas.
        .task { await investments.load() }
        // El presupuesto y el flujo se recalculan cuando cambian los movimientos, las cuentas o sus saldos
        // (la tarjeta guarda su copia de las cuentas) y avisa si algún límite del mes llega al 80 % o se pasa.
        // Hasta que termina la primera carga de las cuentas no se pide nada: así, al arrancar, cada lista se pide una vez.
        .task(id: CreditCardModel.Inputs(finance: finance)) {
            guard finance.hasLoaded else { return }
            await budgets.load()
            await budgets.checkAlerts(categories: finance.categories)
            // Las tarjetas: próximo cargo, avisos antes del cargo y del límite.
            await cards.load(accounts: finance.accounts, balances: finance.balances, categories: finance.categories)
            // Pagos fijos: apunta los cargos que han llegado y empareja los que ya entraron por CSV.
            await planning.syncCharges(movements: finance.recent)
        }
    }

    private func handleQuickAction() {
        guard let action = router.take() else { return }
        switch action {
        case .newExpense:
            // Cierra las otras hojas de esta pantalla y abre el formulario vacío, como gasto.
            addingAccount = false
            importingCSV = false
            newMovementForm = UUID()
            addingMovement = true
        }
    }

    private var householdReload: HouseholdReload {
        HouseholdReload(finance: finance, budgets: budgets, planning: planning, investments: investments,
                        cards: cards, tracking: tracking)
    }

    private var actions: AppActions {
        AppActions(
            newMovement: { addingMovement = true },
            newAccount: { addingAccount = true },
            importCSV: { importingCSV = true },
            refresh: {
                Task { await householdReload.reload() }
            },
            show: { section in
                #if os(iOS)
                // En iPhone solo se puede saltar a las pestañas; lo demás está dentro de Más.
                if AppSection.phoneTabs.contains(section) { selection = section }
                #else
                selection = section
                #endif
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        #if DEBUG
        // Capturas de una pantalla que no es pestaña (p. ej. inversiones): se abre sola.
        if let section = ScreenshotMode.section, !AppSection.phoneTabs.contains(section) {
            NavigationStack { screen(for: section) }
        } else {
            tabs
        }
        #else
        tabs
        #endif
        #else
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(AppSection.sidebarGroups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.sections) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(section)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            NavigationStack {
                screen(for: selection ?? .summary)
            }
            .id(selection)
        }
        #endif
    }

    #if os(iOS)
    private var tabs: some View {
        TabView(selection: $selection) {
            ForEach(AppSection.phoneTabs) { section in
                NavigationStack {
                    screen(for: section)
                }
                .tabItem { Label(section == .more ? String(localized: "Más") : section.title, systemImage: section.systemImage) }
                .tag(Optional(section))
            }
        }
    }
    #endif

    @ViewBuilder
    private func screen(for section: AppSection) -> some View {
        switch section {
        case .summary:
            SummaryView()
        case .movements:
            MovementsView()
        case .creditCards:
            CreditCardsView()
        case .budget:
            BudgetView()
        case .cashFlow:
            CashFlowView()
        case .netWorth:
            NetWorthView()
        case .reports:
            ReportsView()
        case .creditScore:
            CreditScoreView()
        case .subscriptions:
            RecurringView()
        case .goals:
            GoalsView()
        case .investments:
            InvestmentsView()
        case .household:
            HouseholdView(profile: profile, household: household)
        case .more:
            MoreView(profile: profile, household: household)
        }
    }
}

/// Los modelos del hogar abierto que se recargan juntos.
struct HouseholdReload {
    let finance: FinanceModel
    let budgets: BudgetModel
    let planning: PlanningModel
    let investments: InvestmentModel
    let cards: CreditCardModel
    let tracking: TrackingModel

    /// Recarga todo lo del hogar: lo que usan ⌘R («Actualizar») y «Empezar de cero». Sigue el orden de la carga
    /// de arranque: primero las cuentas y los movimientos, y después lo que depende de ellos.
    /// No se puede confiar en el cambio de `CreditCardModel.Inputs`: si la recarga no cambia nada, no se dispara.
    @MainActor
    func reload() async {
        await finance.load()
        await budgets.load()
        await budgets.checkAlerts(categories: finance.categories)
        await cards.load(accounts: finance.accounts, balances: finance.balances, categories: finance.categories)
        await planning.load()
        await planning.syncCharges(movements: finance.recent)
        await investments.load()
        // El seguimiento (patrimonio, informes e historial de crédito) lo cargan las vistas al cambiar sus datos.
        await tracking.loadHistory()
        await tracking.loadSixMonths()
        await tracking.loadScores()
        await tracking.loadReport()
    }

    /// Borra la cuenta y recarga lo que la usaba (ver `reloadReferences`).
    @MainActor
    func deleteAccount(_ account: Account) async -> Bool {
        guard await finance.deleteAccount(account) else { return false }
        await reloadReferences()
        return true
    }

    /// Borra la categoría y recarga lo que la usaba (ver `reloadReferences`).
    @MainActor
    func delete(_ category: BudgetCategory) async -> Bool {
        guard await finance.delete(category) else { return false }
        await reloadReferences()
        return true
    }

    /// Tras borrar una cuenta o una categoría. El servidor deja sin ella (`on delete set null`, con versión nueva) los
    /// pagos fijos, las metas, las inversiones, sus aportaciones y las tarjetas que la usaban, y el presupuesto pierde
    /// su límite. Se recargan para que la siguiente edición no dé un falso «ha cambiado en otro dispositivo».
    @MainActor
    private func reloadReferences() async {
        await budgets.load()
        await cards.load(accounts: finance.accounts, balances: finance.balances, categories: finance.categories)
        await planning.load()
        await investments.load()
    }
}

#Preview {
    let services = AppServices.demo()
    let household = Household(name: "Casa de prueba")
    return RootView(profile: Profile(username: "ana"), household: household,
                    finance: FinanceModel(household: household, service: services.finance),
                    budgets: BudgetModel(household: household, service: services.budgets),
                    planning: PlanningModel(household: household, recurring: services.recurring, goals: services.goals),
                    tracking: TrackingModel(household: household, finance: services.finance, budgets: services.budgets,
                                            scores: services.creditScores),
                    investments: InvestmentModel(household: household, service: services.investments,
                                                 households: services.households),
                    cards: CreditCardModel(household: household, service: services.creditCards, finance: services.finance))
        .environment(SessionModel(services: services))
}
