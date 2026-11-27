import Foundation

#if canImport(Darwin)
/// El texto del catálogo del paquete (ORC-110). El literal en español es la clave y el texto de origen.
func localized(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: .module)
}
#else
/// Fuera de Apple no hay catálogos de textos: vale el literal en español.
func localized(_ value: String) -> String { value }
#endif
