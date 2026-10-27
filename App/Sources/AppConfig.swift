import Foundation
import SwiftUI

/// Ajustes leídos del Info.plist, que a su vez salen de Config/*.xcconfig.
struct AppConfig: Equatable, Sendable {
    var supabaseURL: URL
    var supabaseAnonKey: String

    /// true cuando no hay clave: la app arranca pero no puede conectarse.
    var isMissingSupabaseKey: Bool { supabaseAnonKey.isEmpty }

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfig {
        let rawURL = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? ""
        let key = bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
        return AppConfig(
            supabaseURL: URL(string: rawURL) ?? URL(string: "http://127.0.0.1:54321")!,
            supabaseAnonKey: key
        )
    }
}

private struct AppConfigKey: EnvironmentKey {
    static let defaultValue = AppConfig(supabaseURL: URL(string: "http://127.0.0.1:54321")!, supabaseAnonKey: "")
}

extension EnvironmentValues {
    var appConfig: AppConfig {
        get { self[AppConfigKey.self] }
        set { self[AppConfigKey.self] = newValue }
    }
}
