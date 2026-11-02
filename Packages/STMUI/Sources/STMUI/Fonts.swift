import CoreText
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Fuentes del manual de marca "Estilo Monarch": Source Serif 4 (sustituto de
/// Copernicus) para titulares e Inter (sustituto de ABC Oracle) para el texto.
/// Van dentro de la app, así que se ven igual en todos los dispositivos.
public enum BrandFonts {
    public static let serifFamily = "Source Serif 4"
    public static let sansFamily = "Inter"

    @MainActor private static var registered = false

    /// Registra las fuentes del paquete. Llamarlo una vez al arrancar la app,
    /// antes de pintar nada.
    @MainActor
    public static func register() {
        guard !registered else { return }
        registered = true
        for name in ["SourceSerif4", "Inter"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        #if canImport(UIKit)
        styleNavigationBars()
        #endif
    }

    /// Una fuente variable a un peso exacto (el manual pide 350 para los titulares).
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
    /// Títulos de navegación en serif 350, como los titulares del manual.
    @MainActor
    private static func styleNavigationBars() {
        let ink = UIColor(Palette.ink)
        let large = variable(serifFamily, size: 34, weight: 350) as UIFont
        let inline = variable(serifFamily, size: 18, weight: 400) as UIFont
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large),
                                               .foregroundColor: ink, .kern: -1.2]
        appearance.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline),
                                          .foregroundColor: ink]
    }
    #endif
}
