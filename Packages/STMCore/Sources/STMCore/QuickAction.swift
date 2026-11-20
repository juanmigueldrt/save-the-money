import Foundation

/// Acciones rápidas con las que otra app (Atajos, Siri, un widget) abre Save the Money
/// directamente en una pantalla.
public enum QuickAction: String, Hashable, Sendable, CaseIterable {
    /// La pantalla de nuevo movimiento, vacía y como gasto.
    case newExpense = "nuevo-gasto"

    /// Enlace que abre la acción: `savethemoney://nuevo-gasto`.
    public var link: URL { URL(string: "\(InviteCode.linkScheme)://\(rawValue)")! }

    /// Reconoce `savethemoney://nuevo-gasto` (y `savethemoney://new-expense`). Los enlaces de
    /// invitación (`savethemoney://unirse/…`) no son acciones rápidas.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == InviteCode.linkScheme else { return nil }
        let target = (url.host ?? url.path).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch target {
        case Self.newExpense.rawValue, "new-expense": self = .newExpense
        default: return nil
        }
    }
}
