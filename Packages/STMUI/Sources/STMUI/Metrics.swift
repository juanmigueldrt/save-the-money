import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Espaciados del manual v2 (unidad base de 8 con medios pasos de 4).
public enum Spacing {
    public static let s4: CGFloat = 4
    public static let s8: CGFloat = 8
    public static let s12: CGFloat = 12
    public static let s16: CGFloat = 16
    public static let s20: CGFloat = 20
    public static let s24: CGFloat = 24
    public static let s32: CGFloat = 32
    public static let s40: CGFloat = 40
    public static let s48: CGFloat = 48
    public static let s64: CGFloat = 64
}

/// Radios concéntricos: el input (8) vive dentro de una tarjeta (16) con 8 de padding.
public enum Radius {
    public static let input: CGFloat = 8
    public static let card: CGFloat = 16
    public static let sheet: CGFloat = 28
    public static let pill: CGFloat = 9999
}

/// Alturas de control de las HIG: el área táctil nunca baja de 44 pt.
public enum ControlSize {
    public static let hitTarget: CGFloat = 44
    public static let regular: CGFloat = 44
    public static let large: CGFloat = 50
    public static let small: CGFloat = 32
}

/// Estilos de texto del manual v2, todos con Dynamic Type.
/// Títulos en Source Serif 4 a peso 400 (las HIG desaconsejan pesos ligeros);
/// el resto en la fuente del sistema (SF Pro), que el manual pone primero.
public enum Typography {
    public static let largeTitle = serif(34, relativeTo: .largeTitle)
    public static let title1 = serif(28, relativeTo: .title)
    public static let title2 = serif(22, relativeTo: .title2)
    public static let title3 = Font.title3
    public static let headline = Font.headline
    public static let body = Font.body
    public static let callout = Font.callout
    public static let subheadline = Font.subheadline
    /// Subheadline a 600: etiquetas de campo y títulos de fila compactos.
    public static let subheadlineEmphasis = Font.subheadline.weight(.semibold)
    public static let footnote = Font.footnote
    /// Etiqueta "eyebrow": 13/600 en MAYÚSCULAS sobre un titular.
    public static let eyebrow = Font.footnote.weight(.semibold)
    public static let caption1 = Font.caption
    public static let caption2 = Font.caption2
    /// Cifra destacada de una tarjeta de resumen: 22/28 a 600 con cifras tabulares.
    public static let stat = Font.title2.weight(.semibold).monospacedDigit()

    /// Serif a 400, escalada con el tamaño de texto del sistema.
    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        Font(BrandFonts.variable(BrandFonts.serifFamily, size: scaled(size, style), weight: BrandFonts.serifWeight))
    }

    private static func scaled(_ size: CGFloat, _ style: Font.TextStyle) -> CGFloat {
        #if canImport(UIKit)
        let uiStyle: UIFont.TextStyle = switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        default: .body
        }
        return UIFontMetrics(forTextStyle: uiStyle).scaledValue(for: size)
        #else
        return size
        #endif
    }
}

/// Títulos serif del manual, con su espaciado entre letras.
public enum TitleSize {
    case largeTitle, title1, title2

    var font: Font {
        switch self {
        case .largeTitle: Typography.largeTitle
        case .title1: Typography.title1
        case .title2: Typography.title2
        }
    }

    var tracking: CGFloat {
        switch self {
        case .largeTitle: -0.6
        case .title1: -0.4
        case .title2: -0.2
        }
    }
}

/// Tarjeta (bg-grouped-2) con el radio de 16 del manual v2. Nunca de vidrio:
/// el vidrio es solo para la capa funcional (barras, pestañas, sheets).
public struct CardModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .padding(Spacing.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.bgGrouped2, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

public extension View {
    func card() -> some View { modifier(CardModifier()) }

    /// Título serif del manual con su espaciado.
    func titleFont(_ size: TitleSize) -> some View {
        font(size.font).tracking(size.tracking)
    }

    /// Formularios y listas sobre el lienzo bg-grouped, no sobre el gris de iOS.
    func brandBackground() -> some View {
        scrollContentBackground(.hidden).background(Palette.bgGrouped)
    }
}

/// Etiqueta corta en mayúsculas sobre un título. Dentro de la app va en
/// label-secondary (el naranja queda para lo interactivo).
public struct Eyebrow: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text.uppercased())
            .font(Typography.eyebrow)
            .tracking(0.5)
            .foregroundStyle(Palette.labelSecondary)
    }
}
