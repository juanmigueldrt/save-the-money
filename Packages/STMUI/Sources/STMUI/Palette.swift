import SwiftUI
import STMCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Colores del manual "Estilo Monarch" v2. La interfaz usa solo los tokens
/// semánticos, que cambian con los cuatro temas del manual: claro, oscuro y sus
/// versiones de alto contraste (Ajustes > Accesibilidad > Aumentar contraste).
/// La paleta de marca (ember, ink, linen…) queda dentro de estos valores.
public enum Palette {
    // MARK: Fondos

    /// Lienzo de página y de listas agrupadas (linen).
    public static let bgGrouped = Color(light: 0xEFECEA, dark: 0x141210, hcLight: 0xEFECEA, hcDark: 0x0B0A09)
    /// Tarjetas, filas y campos (paper).
    public static let bgGrouped2 = Color(light: 0xFFFFFF, dark: 0x201D1A, hcLight: 0xFFFFFF, hcDark: 0x1A1816)
    /// Bloques dentro de una tarjeta (gráficos, filas anidadas).
    public static let bgGrouped3 = Color(light: 0xF7F5F3, dark: 0x2B2825, hcLight: 0xF2EFEC, hcDark: 0x2A2724)
    /// Relleno de controles neutros: botón gris, segmento no elegido, pista vacía.
    public static let fill = Color(light: 0x76706A, dark: 0xD2C8BE, hcLight: 0x5A5550, hcDark: 0xE6DED6,
                                   opacity: (0.14, 0.16, 0.24, 0.26))

    // MARK: Texto

    /// Texto principal (ink).
    public static let label = Color(light: 0x22201D, dark: 0xF4F1ED, hcLight: 0x12100E, hcDark: 0xFFFFFF)
    /// Subtítulos y metadatos. Sustituye a graphite, que no llegaba a 4,5:1.
    public static let labelSecondary = Color(light: 0x66635F, dark: 0xA8A39D, hcLight: 0x4A4744, hcDark: 0xD4CFC9)
    /// Placeholder, texto desactivado y series neutras de gráficos.
    public static let labelTertiary = Color(light: 0x9B9893, dark: 0x6F6A64, hcLight: 0x6A6662, hcDark: 0xA39E98)
    /// Líneas de 1 px entre filas. Nunca como color de texto.
    public static let separator = Color(light: 0xDCD9D6, dark: 0x3A3631, hcLight: 0x85807B, hcDark: 0x77716B)

    // MARK: Acento

    /// Tint de la app (ember): botón prominente, toggle activo, selección. Solo para lo interactivo.
    public static let accent = Color(light: 0xFF692D, dark: 0xFF7A3F, hcLight: 0xB83F0A, hcDark: 0xFFA577)
    /// Texto y símbolos sobre `accent` (ink, no blanco: el blanco no llega a AA).
    public static let onAccent = Color(light: 0x22201D, dark: 0x1A1714, hcLight: 0xFFFFFF, hcDark: 0x12100E)
    /// Acento como texto: enlaces, botón plano, cifras destacadas.
    public static let accentText = Color(light: 0xB5410E, dark: 0xFF8A55, hcLight: 0x8A3208, hcDark: 0xFFA577)

    // MARK: Estado (siempre con signo o símbolo, nunca solo color)

    public static let positive = Color(light: 0x34C759, dark: 0x30D158, hcLight: 0x008932, hcDark: 0x4AD968)
    public static let positiveText = Color(light: 0x007A2C, dark: 0x30D158, hcLight: 0x005A20, hcDark: 0x4AD968)
    public static let negative = Color(light: 0xFF383C, dark: 0xFF4245, hcLight: 0xE9152D, hcDark: 0xFF6165)
    public static let negativeText = Color(light: 0xCC0E26, dark: 0xFF5C5F, hcLight: 0x9C0B1D, hcDark: 0xFF9496)
}

public extension BudgetGroup {
    /// Color de cada grupo de la plantilla 50/30/20, igual que en el Sankey del diseño.
    var color: Color {
        switch self {
        case .needs: Palette.label
        case .wants: Palette.accent
        case .savings: Palette.labelSecondary
        }
    }
}

extension Color {
    /// Color que cambia con el modo claro u oscuro y con "Aumentar contraste".
    init(light: UInt32, dark: UInt32, hcLight: UInt32, hcDark: UInt32,
         opacity: (Double, Double, Double, Double) = (1, 1, 1, 1)) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let isHigh = traits.accessibilityContrast == .high
            return switch (isDark, isHigh) {
            case (false, false): UIColor(rgb: light, alpha: opacity.0)
            case (true, false): UIColor(rgb: dark, alpha: opacity.1)
            case (false, true): UIColor(rgb: hcLight, alpha: opacity.2)
            case (true, true): UIColor(rgb: hcDark, alpha: opacity.3)
            }
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua,
                                                    .accessibilityHighContrastAqua,
                                                    .accessibilityHighContrastDarkAqua])
            return switch match {
            case .darkAqua: NSColor(rgb: dark, alpha: opacity.1)
            case .accessibilityHighContrastAqua: NSColor(rgb: hcLight, alpha: opacity.2)
            case .accessibilityHighContrastDarkAqua: NSColor(rgb: hcDark, alpha: opacity.3)
            default: NSColor(rgb: light, alpha: opacity.0)
            }
        })
        #endif
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(rgb: UInt32, alpha: Double = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: alpha)
    }
}
#elseif canImport(AppKit)
extension NSColor {
    convenience init(rgb: UInt32, alpha: Double = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: alpha)
    }
}
#endif
