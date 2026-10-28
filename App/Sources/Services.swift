import Foundation
import STMCore
import STMData

/// Servicios que usa la app. Sin clave de Supabase arranca en modo demo,
/// con datos en memoria que se pierden al cerrar la app.
struct AppServices: Sendable {
    let auth: any AuthService
    let households: any HouseholdService
    let finance: any FinanceService
    let isDemo: Bool

    static func make(config: AppConfig) -> AppServices {
        if config.isMissingSupabaseKey {
            let backend = InMemoryBackend()
            return AppServices(auth: backend, households: backend, finance: backend, isDemo: true)
        }
        let backend = SupabaseBackend(url: config.supabaseURL, anonKey: config.supabaseAnonKey)
        return AppServices(auth: backend, households: backend, finance: backend, isDemo: false)
    }

    static func demo() -> AppServices {
        let backend = InMemoryBackend()
        return AppServices(auth: backend, households: backend, finance: backend, isDemo: true)
    }
}
