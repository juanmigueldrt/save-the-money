import Foundation

/// El único punto que decide la región y la moneda por defecto (ORC-110). Para llevar la app a otra región
/// se cambia aquí; cada hogar y cada cuenta guardan además su propia moneda.
public enum AppRegion {
    /// Formato de números, fechas e importes, y reglas de mayúsculas y acentos al comparar textos.
    public static let locale = Locale(identifier: "es_ES")
    /// Moneda de lo que aún no tiene una propia.
    public static let currency = "EUR"
}
