import SwiftUI
import STMCore

/// Lo que los menús y atajos de teclado pueden hacer en la ventana activa.
/// La publica `RootView` cuando hay un hogar abierto; antes de entrar, los
/// menús salen desactivados.
struct AppActions {
    var newMovement: () -> Void
    var newAccount: () -> Void
    var importCSV: () -> Void
    var refresh: () -> Void
    var show: (AppSection) -> Void
}

private struct AppActionsKey: FocusedValueKey {
    typealias Value = AppActions
}

extension FocusedValues {
    var appActions: AppActions? {
        get { self[AppActionsKey.self] }
        set { self[AppActionsKey.self] = newValue }
    }
}

/// Menús de la app: en Mac salen en la barra de menús y en iPad con teclado,
/// al mantener pulsada la tecla ⌘.
struct AppCommands: Commands {
    @FocusedValue(\.appActions) private var actions

    /// Atajos ⌘1…⌘9 en el orden de la barra lateral.
    static let shortcutSections: [AppSection] = [
        .summary, .movements, .budget, .cashFlow, .netWorth, .reports, .subscriptions, .goals, .creditScore,
    ]

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Group {
                Button("Nuevo movimiento") { actions?.newMovement() }
                    .keyboardShortcut("n")
                Button("Nueva cuenta") { actions?.newAccount() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("Importar CSV del banco…") { actions?.importCSV() }
                    .keyboardShortcut("i")
            }
            .disabled(actions == nil)
        }

        CommandMenu("Ir") {
            Group {
                ForEach(Array(Self.shortcutSections.enumerated()), id: \.element) { index, section in
                    Button(section.title) { actions?.show(section) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
                Button(AppSection.investments.title) { actions?.show(.investments) }
                    .keyboardShortcut("0")
                Divider()
                Button(AppSection.household.title) { actions?.show(.household) }
                Button(AppSection.more.title) { actions?.show(.more) }
                    .keyboardShortcut(",", modifiers: [.command, .option])
                Divider()
                Button("Actualizar") { actions?.refresh() }
                    .keyboardShortcut("r")
            }
            .disabled(actions == nil)
        }
    }
}
