import SwiftUI
import STMCore
import STMUI

/// Secciones de la app. En iPhone son pestañas; en Mac, la barra lateral.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case summary, movements, budget, cashFlow, subscriptions, goals, household, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: "Resumen"
        case .movements: "Movimientos"
        case .budget: "Presupuesto"
        case .cashFlow: "Flujo"
        case .subscriptions: "Pagos fijos"
        case .goals: "Metas"
        case .household: "Hogar"
        case .more: "Más opciones"
        }
    }

    var systemImage: String {
        switch self {
        case .summary: "house"
        case .movements: "list.bullet.rectangle"
        case .budget: "chart.pie"
        case .cashFlow: "arrow.left.arrow.right"
        case .subscriptions: "repeat"
        case .goals: "flag"
        case .household: "person.2"
        case .more: "ellipsis.circle"
        }
    }

    /// Pestañas del iPhone: movimientos se abren desde el resumen; suscripciones y hogar, desde Más opciones.
    static let phoneTabs: [AppSection] = [.summary, .budget, .cashFlow, .goals, .more]
}

struct RootView: View {
    let profile: Profile
    let household: Household

    @Environment(SessionModel.self) private var session
    @State private var selection: AppSection? = .summary
    @State private var finance: FinanceModel
    @State private var budgets: BudgetModel
    @State private var planning: PlanningModel

    init(profile: Profile, household: Household, finance: FinanceModel, budgets: BudgetModel, planning: PlanningModel) {
        self.profile = profile
        self.household = household
        _finance = State(initialValue: finance)
        _budgets = State(initialValue: budgets)
        _planning = State(initialValue: planning)
    }

    var body: some View {
        VStack(spacing: 0) {
            if session.isDemo { DemoBanner() }
            content
        }
        .environment(finance)
        .environment(budgets)
        .environment(planning)
        .task { await finance.load() }
        // También reprograma los avisos de pagos cada vez que se abre la app.
        .task { await planning.load() }
        // El presupuesto y el flujo se recalculan cuando cambian los movimientos.
        .task(id: finance.recent) { await budgets.load() }
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        TabView(selection: $selection) {
            ForEach(AppSection.phoneTabs) { section in
                NavigationStack {
                    screen(for: section)
                }
                .tabItem { Label(section == .more ? "Más" : section.title, systemImage: section.systemImage) }
                .tag(Optional(section))
            }
        }
        #else
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
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

    @ViewBuilder
    private func screen(for section: AppSection) -> some View {
        switch section {
        case .summary:
            SummaryView()
        case .movements:
            MovementsView()
        case .budget:
            BudgetView()
        case .cashFlow:
            CashFlowView()
        case .subscriptions:
            RecurringView()
        case .goals:
            GoalsView()
        case .household:
            HouseholdView(profile: profile, household: household)
        case .more:
            MoreView(profile: profile, household: household)
        }
    }
}

#Preview {
    let services = AppServices.demo()
    let household = Household(name: "Casa de prueba")
    return RootView(profile: Profile(username: "ana"), household: household,
                    finance: FinanceModel(household: household, service: services.finance),
                    budgets: BudgetModel(household: household, service: services.budgets),
                    planning: PlanningModel(household: household, recurring: services.recurring, goals: services.goals))
        .environment(SessionModel(services: services))
}
