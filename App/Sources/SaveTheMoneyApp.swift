import SwiftUI
import STMCore
import STMUI

@main
struct SaveTheMoneyApp: App {
    @State private var session: SessionModel

    init() {
        // Antes de pintar nada, para que todo salga con las fuentes del manual de marca.
        BrandFonts.register()
        let config = AppConfig.fromBundle()
        _session = State(initialValue: SessionModel(services: .make(config: config)))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(session)
                .tint(Palette.ember)
                .task { await session.start() }
                .onOpenURL { session.handle(url: $0) }
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        #endif
    }
}

/// Elige la pantalla según el estado de la sesión.
struct AppRootView: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.linen)
            case .signedOut:
                AuthFlowView()
            case .needsHousehold(let profile):
                HouseholdOnboardingView(profile: profile)
            case .ready(let profile, let household):
                RootView(profile: profile, household: household,
                         finance: FinanceModel(household: household, service: session.services.finance),
                         budgets: BudgetModel(household: household, service: session.services.budgets,
                                              alerts: session.isDemo ? NoBudgetAlerts() : LocalBudgetAlerts()),
                         planning: PlanningModel(household: household, recurring: session.services.recurring,
                                                 goals: session.services.goals,
                                                 reminders: session.isDemo ? NoReminders() : LocalReminders()),
                         tracking: TrackingModel(household: household, finance: session.services.finance,
                                                 budgets: session.services.budgets, scores: session.services.creditScores))
                    .id(household.id)
            }
        }
        .animation(.default, value: session.state)
        .preferredColorScheme(session.theme.colorScheme)
    }
}

extension AppTheme {
    /// nil = lo que diga el sistema.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
