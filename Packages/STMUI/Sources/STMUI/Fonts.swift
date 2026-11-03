import CoreText
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Fuentes del manual "Estilo Monarch" v2: Source Serif 4 (sustituto de
/// Copernicus) para los títulos, dentro de la app para que se vea igual en todos
/// los dispositivos. El texto usa la fuente del sistema (SF Pro), como pide el manual.
public enum BrandFonts {
    public static let serifFamily = "Source Serif 4"
    /// Peso de los títulos serif: 400 (la v1 usaba 350).
    public static let serifWeight: CGFloat = 400

    @MainActor private static var registered = false

    /// Registra las fuentes del paquete. Llamarlo una vez al arrancar la app,
    /// antes de pintar nada.
    @MainActor
    public static func register() {
        guard !registered else { return }
        registered = true
        for name in ["SourceSerif4"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        #if canImport(UIKit)
        styleNavigationBars()
        #endif
    }

    /// Una fuente variable a un peso exacto.
    static func variable(_ family: String, size: CGFloat, weight: CGFloat) -> CTFont {
        let wght = 0x7767_6874 // 'wght'
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: family,
            kCTFontVariationAttribute: [wght: weight],
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    #if canImport(UIKit)
    /// Large Title en serif 34/41 a 400; el título pequeño sigue en headline del
    /// sistema (17/600), como en las HIG. Las barras son de vidrio del sistema.
    @MainActor
    private static func styleNavigationBars() {
        let label = UIColor(Palette.label)
        let large = variable(serifFamily, size: 34, weight: serifWeight) as UIFont
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large),
                                               .foregroundColor: label, .kern: -0.6]
        appearance.titleTextAttributes = [.foregroundColor: label]
    }
    #endif
}
