import SwiftUI
import STMCore
import STMUI

/// Secciones de la app. En iPhone son pestañas; en Mac, la barra lateral.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case summary, movements, budget, cashFlow, netWorth, reports, subscriptions, goals, creditScore, household, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: "Resumen"
        case .movements: "Movimientos"
        case .budget: "Presupuesto"
        case .cashFlow: "Flujo"
        case .netWorth: "Patrimonio"
        case .reports: "Informes"
        case .creditScore: "Score crediticio"
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
        case .netWorth: "chart.line.uptrend.xyaxis"
        case .reports: "chart.bar.doc.horizontal"
        case .creditScore: "gauge.with.dots.needle.67percent"
        case .subscriptions: "repeat"
        case .goals: "flag"
        case .household: "person.2"
        case .more: "ellipsis.circle"
        }
    }

    /// Pestañas del iPhone: movimientos y patrimonio se abren desde el resumen; el resto, desde Más opciones.
    static let phoneTabs: [AppSection] = [.summary, .budget, .cashFlow, .goals, .more]
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
    @State private var addingMovement = false
    @State private var addingAccount = false
    @State private var importingCSV = false

    init(profile: Profile, household: Household, finance: FinanceModel, budgets: BudgetModel, planning: PlanningModel,
         tracking: TrackingModel) {
        self.profile = profile
        self.household = household
        _finance = State(initialValue: finance)
        _budgets = State(initialValue: budgets)
        _planning = State(initialValue: planning)
        _tracking = State(initialValue: tracking)
    }

    var body: some View {
        VStack(spacing: 0) {
            if session.isDemo { DemoBanner() }
            content
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
        // Las hojas de los menús van dentro de los .environment para recibir los modelos.
        .sheet(isPresented: $addingMovement) { MovementFormView(movement: nil, accountId: nil) }
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
        .focusedSceneValue(\.appActions, actions)
        .environment(finance)
        .environment(budgets)
        .environment(planning)
        .environment(tracking)
        .task { await finance.load() }
        // También reprograma los avisos de pagos cada vez que se abre la app.
        .task { await planning.load() }
        // El presupuesto y el flujo se recalculan cuando cambian los movimientos.
        // y avisa si algún límite del mes llega al 80 % o se pasa.
        .task(id: finance.recent) {
            await budgets.load()
            await budgets.checkAlerts(categories: finance.categories)
        }
    }

    private var actions: AppActions {
        AppActions(
            newMovement: { addingMovement = true },
            newAccount: { addingAccount = true },
            importCSV: { importingCSV = true },
            refresh: {
                Task {
                    await finance.load()
                    await planning.load()
                    await budgets.load()
                }
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
                    planning: PlanningModel(household: household, recurring: services.recurring, goals: services.goals),
                    tracking: TrackingModel(household: household, finance: services.finance, budgets: services.budgets,
                                            scores: services.creditScores))
        .environment(SessionModel(services: services))
}
