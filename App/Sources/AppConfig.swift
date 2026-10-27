import Foundation

/// Ajustes leídos del Info.plist, que a su vez salen de Config/*.xcconfig.
struct AppConfig: Equatable, Sendable {
    var supabaseURL: URL
    var supabaseAnonKey: String

    /// true cuando no hay clave real: la app arranca en modo demo.
    var isMissingSupabaseKey: Bool {
        supabaseAnonKey.isEmpty || supabaseAnonKey.hasPrefix("pega-aqui")
    }

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfig {
        let rawURL = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? ""
        let key = bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
        return AppConfig(
            supabaseURL: URL(string: rawURL) ?? URL(string: "http://127.0.0.1:54321")!,
            supabaseAnonKey: key
        )
    }
}
