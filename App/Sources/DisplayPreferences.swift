import SwiftUI
import STMCore
import STMUI

/// Opciones de vista que se guardan en este dispositivo (Más opciones > Vista).
enum DisplayPreferences {
    static let incognitoKey = "stm.display.incognito"
    static let roundKey = "stm.display.roundUnits"
    static let plusSignKey = "stm.display.plusSign"
    static let colorAmountsKey = "stm.display.colorAmounts"

    /// Pasa las opciones guardadas a `Money.display`, que usan todos los importes.
    static func apply(incognito: Bool, round: Bool) {
        Money.display = MoneyDisplayOptions(hidesAmounts: incognito, roundsToUnits: round)
    }
}

/// Aplica el modo incógnito y el redondeo, y vuelve a pintar todo cuando cambian.
struct MoneyDisplayModifier: ViewModifier {
    @AppStorage(DisplayPreferences.incognitoKey) private var incognito = false
    @AppStorage(DisplayPreferences.roundKey) private var round = false

    func body(content: Content) -> some View {
        // Se aplica antes de pintar el contenido de esta pasada.
        DisplayPreferences.apply(incognito: incognito, round: round)
        return content
            .id("\(incognito)-\(round)")
    }
}

/// Botón del ojo para el modo incógnito: en la barra del Resumen.
struct IncognitoButton: View {
    @AppStorage(DisplayPreferences.incognitoKey) private var incognito = false

    var body: some View {
        Button {
            incognito.toggle()
        } label: {
            Label(incognito ? "Mostrar importes" : "Ocultar importes",
                  systemImage: incognito ? "eye.slash" : "eye")
        }
        .help(incognito ? "Mostrar importes" : "Ocultar importes")
    }
}

/// Sección «Vista» de Más opciones.
struct DisplayOptionsSection: View {
    @AppStorage(DisplayPreferences.incognitoKey) private var incognito = false
    @AppStorage(DisplayPreferences.roundKey) private var round = false
    @AppStorage(DisplayPreferences.plusSignKey) private var plusSign = false
    @AppStorage(DisplayPreferences.colorAmountsKey) private var colorAmounts = true

    var body: some View {
        Section {
            Toggle("Modo incógnito (ocultar importes)", isOn: $incognito)
            Toggle("Sin céntimos", isOn: $round)
            Toggle("Mostrar + en los ingresos", isOn: $plusSign)
            Toggle("Ingresos en verde", isOn: $colorAmounts)
        } header: {
            Text("Vista")
        } footer: {
            Text("Sólo en este dispositivo. El modo incógnito también se activa con el ojo del Resumen; los PDF y CSV llevan siempre los importes completos.")
        }
    }
}
