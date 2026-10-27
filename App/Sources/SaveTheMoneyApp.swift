import SwiftUI

@main
struct SaveTheMoneyApp: App {
    private let config = AppConfig.fromBundle()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appConfig, config)
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        #endif
    }
}
