import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

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

/// Estilos de texto del manual. Titulares en Source Serif 4 a peso 350 (nunca en
/// negrita) con espaciado negativo; texto en Inter a 400 (el manual pide 350 y,
/// si no se puede, 400: así se conserva el tamaño dinámico del sistema).
public enum Typography {
    public static let title36 = serif(36, relativeTo: .largeTitle)
    public static let title32 = serif(32, relativeTo: .largeTitle)
    public static let title20 = serif(20, relativeTo: .title3)
    public static let body16 = Font.custom(BrandFonts.sansFamily, size: 16, relativeTo: .body)
    public static let body16Medium = Font.custom(BrandFonts.sansFamily, size: 16, relativeTo: .body).weight(.medium)
    public static let body14 = Font.custom(BrandFonts.sansFamily, size: 14, relativeTo: .subheadline)
    public static let body14Medium = Font.custom(BrandFonts.sansFamily, size: 14, relativeTo: .subheadline).weight(.medium)
    public static let small12 = Font.custom(BrandFonts.sansFamily, size: 12, relativeTo: .caption)
    /// Etiqueta "eyebrow": 14/500 en MAYÚSCULAS y ember, sobre un titular.
    public static let eyebrow = Font.custom(BrandFonts.sansFamily, size: 14, relativeTo: .footnote).weight(.medium)

    /// Serif a 350, escalada con el tamaño de texto del sistema.
    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        Font(BrandFonts.variable(BrandFonts.serifFamily, size: scaled(size, style), weight: 350))
    }

    private static func scaled(_ size: CGFloat, _ style: Font.TextStyle) -> CGFloat {
        #if canImport(UIKit)
        let uiStyle: UIFont.TextStyle = switch style {
        case .largeTitle: .largeTitle
        case .title3: .title3
        default: .body
        }
        return UIFontMetrics(forTextStyle: uiStyle).scaledValue(for: size)
        #else
        return size
        #endif
    }
}

/// Tamaños de titular, con el espaciado entre letras del manual (más cerrado cuanto más grande).
public enum TitleSize {
    case title36, title32, title20

    var font: Font {
        switch self {
        case .title36: Typography.title36
        case .title32: Typography.title32
        case .title20: Typography.title20
        }
    }

    var tracking: CGFloat {
        switch self {
        case .title36: -2.0
        case .title32: -1.6
        case .title20: -0.4
        }
    }
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

    /// Titular del manual: serif 350 con espaciado negativo.
    func titleFont(_ size: TitleSize) -> some View {
        font(size.font).tracking(size.tracking)
    }

    /// Formularios y listas sobre el lienzo lino del manual, no sobre el gris de iOS.
    func brandBackground() -> some View {
        scrollContentBackground(.hidden).background(Palette.linen)
    }
}

/// Etiqueta corta en mayúsculas y ember sobre un titular `ink`.
public struct Eyebrow: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text.uppercased())
            .font(Typography.eyebrow)
            .tracking(0.56)
            .foregroundStyle(Palette.ember)
    }
}
