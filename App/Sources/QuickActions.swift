import AppIntents
import SwiftUI
import STMCore

/// Recoge las acciones rápidas que llegan de fuera (Atajos, Siri, enlaces savethemoney://) hasta
/// que la pantalla principal está lista para atenderlas. Si la app estaba cerrada o aún cargando
/// la sesión, la acción espera aquí.
@MainActor
@Observable
final class QuickActionRouter {
    static let shared = QuickActionRouter()

    /// La acción por atender y un número que cambia en cada petición (para abrir el formulario
    /// de nuevo aunque ya estuviera abierto).
    private(set) var pending: QuickAction?
    private(set) var request = 0

    func open(_ action: QuickAction) {
        pending = action
        request += 1
    }

    /// La pantalla principal la recoge y la marca como atendida.
    func take() -> QuickAction? {
        defer { pending = nil }
        return pending
    }
}

// MARK: - Atajos

/// «Nuevo gasto»: abre la app en la pantalla de nuevo movimiento, vacía. Aparece sola en la app
/// Atajos (también en automatizaciones) y en Siri y Spotlight, sin configurar nada.
struct NewExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Nuevo gasto"
    static let description = IntentDescription("Abre Save the Money en la pantalla de nuevo gasto, vacía.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionRouter.shared.open(.newExpense)
        return .result()
    }
}

struct SaveTheMoneyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NewExpenseIntent(),
                    phrases: ["Nuevo gasto en \(.applicationName)",
                              "Apuntar un gasto en \(.applicationName)",
                              "Añadir gasto en \(.applicationName)"],
                    shortTitle: "Nuevo gasto",
                    systemImageName: "plus.circle")
    }
}
