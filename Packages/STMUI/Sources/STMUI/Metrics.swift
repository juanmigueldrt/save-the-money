import SwiftUI

/// Espaciados y radios del diseño (colección "Save the Money · Espaciado").
public enum Spacing {
    public static let s8: CGFloat = 8
    public static let s16: CGFloat = 16
    public static let s24: CGFloat = 24
    public static let s32: CGFloat = 32
    public static let s40: CGFloat = 40
    public static let s48: CGFloat = 48
    public static let s64: CGFloat = 64
}

public enum Radius {
    public static let input: CGFloat = 8
    public static let card: CGFloat = 12
    public static let pill: CGFloat = 9999
}

/// Estilos de texto del diseño. Títulos en Source Serif 4 y cuerpo en Inter;
/// si las fuentes no están instaladas en la app se usa la del sistema equivalente.
public enum Typography {
    public static let title36 = Font.custom("Source Serif 4", size: 36, relativeTo: .largeTitle)
    public static let title32 = Font.custom("Source Serif 4", size: 32, relativeTo: .largeTitle)
    public static let title20 = Font.custom("Source Serif 4", size: 20, relativeTo: .title3)
    public static let body16 = Font.custom("Inter", size: 16, relativeTo: .body)
    public static let body16Medium = Font.custom("Inter", size: 16, relativeTo: .body).weight(.medium)
    public static let body14 = Font.custom("Inter", size: 14, relativeTo: .subheadline)
    public static let body14Medium = Font.custom("Inter", size: 14, relativeTo: .subheadline).weight(.medium)
    public static let small12 = Font.custom("Inter", size: 12, relativeTo: .caption)
}

/// Tarjeta blanca (paper) con el radio del diseño.
public struct CardModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .padding(Spacing.s24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

public extension View {
    func card() -> some View { modifier(CardModifier()) }
}
