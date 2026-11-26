import Foundation

/// Ajustes leídos del Info.plist, que a su vez salen de Config/*.xcconfig.
struct AppConfig: Equatable, Sendable {
    var supabaseURL: URL
    var supabaseAnonKey: String
    /// Clave publicable de logo.dev (pk_…). Vacía: logos del favicon de Google.
    var logoDevToken: String = ""

    /// true cuando no hay clave real: la app arranca en modo demo.
    var isMissingSupabaseKey: Bool {
        supabaseAnonKey.isEmpty || supabaseAnonKey.hasPrefix("pega-aqui")
    }

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfig {
        let rawURL = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? ""
        let key = bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
        #if !DEBUG
        // Release no arranca con una configuración incompleta: ni demo silenciosa ni http.
        if let problem = releaseProblem(rawURL: rawURL, key: key) {
            fatalError("Configuración de Release incorrecta: \(problem). Revisa Config/Secrets.xcconfig.")
        }
        #endif
        return AppConfig(
            supabaseURL: URL(string: rawURL) ?? localURL,
            supabaseAnonKey: key,
            logoDevToken: bundle.object(forInfoDictionaryKey: "LogoDevToken") as? String ?? ""
        )
    }

    /// Sólo Debug: el Supabase local de `supabase start`.
    static let localURL = URL(string: "http://127.0.0.1:54321")!

    /// Qué impide arrancar una compilación Release, o nil si la configuración es válida.
    static func releaseProblem(rawURL: String, key: String) -> String? {
        if key.isEmpty || key.hasPrefix("pega-aqui") {
            return "falta SupabaseAnonKey"
        }
        guard let url = URL(string: rawURL), url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
            return "SupabaseURL debe ser una URL https (valor actual: \"\(rawURL)\")"
        }
        return nil
    }
}
