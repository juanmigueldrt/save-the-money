import SwiftUI
import STMCore
import STMUI

@main
struct SaveTheMoneyApp: App {
    @State private var session: SessionModel

    init() {
        // Antes de pintar nada, para que todo salga con las fuentes del manual de marca.
        BrandFonts.register()
        // Lo exportado en una sesión anterior no debe seguir en la carpeta temporal.
        ExportFiles.clear()
        let config = AppConfig.fromBundle()
        var services = AppServices.make(config: config)
        #if DEBUG
        if ScreenshotMode.isActive { services = .demo() }
        #endif
        _session = State(initialValue: SessionModel(services: services, clearLocalData: { await LocalAccountData.clear() }))
    }

    /// Fase de toda la app (no la de cada ventana), para el bloqueo.
    @Environment(\.scenePhase) private var scenePhase

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
                // Con la app bloqueada, el enlace espera a que se desbloquee.
                .onOpenURL { url in AppLockModel.shared.whenUnlocked { session.handle(url: url) } }
                .modifier(AppLockModifier(appPhase: scenePhase))
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
            case .offline(let message):
                OfflineView(message: message)
            case .needsHousehold(let profile):
                HouseholdOnboardingView(profile: profile)
            case .ready(let profile, let household):
                // `models` existe siempre en `.ready` (lo crea la sesión al entrar en el hogar).
                if let models = session.models {
                    RootView(profile: profile, household: household,
                             finance: models.finance, budgets: models.budgets, planning: models.planning,
                             tracking: models.tracking, investments: models.investments, cards: models.cards)
                        .environment(models.household)
                        .id(household.id)
                }
            }
        }
        .animation(.default, value: session.state)
        .preferredColorScheme(session.theme.colorScheme)
    }
}

/// Los modelos de un hogar abierto. Los crea `SessionModel` una sola vez al entrar en el hogar.
@MainActor
struct HouseholdModels {
    let householdId: UUID
    let finance: FinanceModel
    let budgets: BudgetModel
    let planning: PlanningModel
    let tracking: TrackingModel
    let investments: InvestmentModel
    let cards: CreditCardModel
    let household: HouseholdModel

    init(household: Household, services: AppServices) {
        householdId = household.id
        finance = FinanceModel(household: household, service: services.finance)
        budgets = BudgetModel(household: household, service: services.budgets,
                              alerts: services.isDemo ? NoBudgetAlerts() : LocalBudgetAlerts())
        planning = PlanningModel(household: household, recurring: services.recurring, goals: services.goals,
                                 reminders: services.isDemo ? NoReminders() : LocalReminders())
        tracking = TrackingModel(household: household, finance: services.finance,
                                 budgets: services.budgets, scores: services.creditScores)
        investments = InvestmentModel(household: household, service: services.investments,
                                      households: services.households,
                                      reminders: services.isDemo ? NoReminders() : LocalReminders())
        cards = CreditCardModel(household: household, service: services.creditCards, finance: services.finance,
                                reminders: services.isDemo ? NoReminders() : LocalReminders(),
                                alerts: services.isDemo ? NoBudgetAlerts() : LocalBudgetAlerts())
        self.household = HouseholdModel(householdId: household.id, service: services.households)
    }
}

/// Hay sesión guardada pero no se ha podido cargar: aviso y «Reintentar», sin pedir entrar otra vez.
struct OfflineView: View {
    let message: String
    @Environment(SessionModel.self) private var session
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: Spacing.s16) {
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Palette.label)
                .multilineTextAlignment(.center)
            Button("Reintentar") {
                isWorking = true
                Task {
                    await session.start()
                    isWorking = false
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isWorking)
            // Salida por si el fallo no se arregla reintentando.
            Button("Cerrar sesión") { Task { await session.signOut() } }
                .font(Typography.subheadlineEmphasis)
                .foregroundStyle(Palette.labelSecondary)
                .buttonStyle(.plain)
        }
        .padding(Spacing.s24)
        .formWidth()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bgGrouped)
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
