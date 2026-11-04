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
        var services = AppServices.make(config: config)
        #if DEBUG
        if ScreenshotMode.isActive { services = .demo() }
        #endif
        _session = State(initialValue: SessionModel(services: services))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(session)
                .tint(Palette.accent)
                // La app está en español: fechas, meses de los gráficos y selectores, aunque el dispositivo no lo esté.
                .environment(\.locale, Locale(identifier: "es_ES"))
                .task {
                    #if DEBUG
                    if ScreenshotMode.isActive { await ScreenshotMode.prepare(session); return }
                    #endif
                    await session.start()
                }
                .onOpenURL { session.handle(url: $0) }
        }
        .commands { AppCommands() }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
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
                    .background(Palette.bgGrouped)
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
                                                 budgets: session.services.budgets, scores: session.services.creditScores),
                         investments: InvestmentModel(household: household, service: session.services.investments,
                                                      households: session.services.households,
                                                      reminders: session.isDemo ? NoReminders() : LocalReminders()),
                         cards: CreditCardModel(household: household, service: session.services.creditCards,
                                                finance: session.services.finance,
                                                reminders: session.isDemo ? NoReminders() : LocalReminders(),
                                                alerts: session.isDemo ? NoBudgetAlerts() : LocalBudgetAlerts()))
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
