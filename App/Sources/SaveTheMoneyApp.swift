import SwiftUI
import STMUI

@main
struct SaveTheMoneyApp: App {
    @State private var session: SessionModel

    init() {
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
                RootView(profile: profile, household: household)
            }
        }
        .animation(.default, value: session.state)
    }
}
