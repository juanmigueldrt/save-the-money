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
        case .subscriptions: "Suscripciones"
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

    init(profile: Profile, household: Household, finance: FinanceModel) {
        self.profile = profile
        self.household = household
        _finance = State(initialValue: finance)
    }

    var body: some View {
        VStack(spacing: 0) {
            if session.isDemo { DemoBanner() }
            content
        }
        .environment(finance)
        .task { await finance.load() }
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
        case .household:
            HouseholdView(profile: profile, household: household)
        case .more:
            MoreView(profile: profile, household: household)
        default:
            SectionPlaceholder(section: section)
        }
    }
}

/// Más opciones. En iPhone también da paso a lo que no cabe en la barra inferior.
struct MoreView: View {
    let profile: Profile
    let household: Household

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
                    SectionPlaceholder(section: .subscriptions)
                } label: {
                    Label(AppSection.subscriptions.title, systemImage: AppSection.subscriptions.systemImage)
                }
            }
            #endif
            Section("Datos") {
                NavigationLink {
                    CSVImportView()
                } label: {
                    Label("Importar CSV del banco", systemImage: "square.and.arrow.down")
                }
                Text("Exportar y borrar datos llegan en la fase 5.")
                    .font(Typography.body14)
                    .foregroundStyle(Palette.graphite)
            }
        }
        .navigationTitle("Más opciones")
    }
}

/// Pantalla provisional de cada sección hasta que llegue su fase.
struct SectionPlaceholder: View {
    let section: AppSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s16) {
                Text(section.title)
                    .font(Typography.title32)
                    .foregroundStyle(Palette.ink)
                if section == .budget {
                    HStack(spacing: Spacing.s16) {
                        ForEach(BudgetGroup.allCases, id: \.self) { group in
                            SemicircleGauge(progress: GroupProgress(group: group, allocated: Money(minor: 100_000), spent: .zero))
                        }
                    }
                    .card()
                }
                Text("Esta pantalla llega en una próxima fase.")
                    .font(Typography.body16)
                    .foregroundStyle(Palette.graphite)
            }
            .padding(Spacing.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.linen)
    }
}

#Preview {
    let services = AppServices.demo()
    let household = Household(name: "Casa de prueba")
    return RootView(profile: Profile(username: "ana"), household: household,
                    finance: FinanceModel(household: household, service: services.finance))
        .environment(SessionModel(services: services))
}
