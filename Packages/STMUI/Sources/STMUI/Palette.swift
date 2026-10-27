import SwiftUI
import STMCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Colores del diseño, con su versión clara y oscura (colección "Save the Money · Color").
public enum Palette {
    public static let ember = Color(light: 0xFF692D, dark: 0xFF7A45)
    public static let ink = Color(light: 0x22201D, dark: 0xF2EFEC)
    public static let graphite = Color(light: 0x777573, dark: 0xA3A09C)
    public static let smoke = Color(light: 0xCCCCCC, dark: 0x5C5955)
    public static let stone = Color(light: 0xDCD9D6, dark: 0x3A3734)
    public static let linen = Color(light: 0xEFECEA, dark: 0x141312)
    public static let paper = Color(light: 0xFFFFFF, dark: 0x1F1D1B)
    public static let red = Color(light: 0xE5484D, dark: 0xF2555A)
}

public extension BudgetGroup {
    /// Color de cada grupo de la plantilla 50/30/20, igual que en el Sankey del diseño.
    var color: Color {
        switch self {
        case .needs: Palette.ink
        case .wants: Palette.ember
        case .savings: Palette.graphite
        }
    }
}

extension Color {
    /// Color que cambia con el modo claro u oscuro del sistema.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
        #endif
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
#elseif canImport(AppKit)
extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
#endif
