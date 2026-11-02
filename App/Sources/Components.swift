import SwiftUI
import STMUI

/// Botón principal del manual: píldora ember con texto ink (blanco sobre ember no llega a AA)
/// y la sombra sutil.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.body16Medium)
            .foregroundStyle(Palette.onEmber)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Palette.ember.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4), in: Capsule())
            .shadow(color: Color(red: 34 / 255, green: 32 / 255, blue: 29 / 255).opacity(0.05), radius: 1, y: 1)
    }
}

/// Botón contorneado del manual: píldora con borde ember de 1,5 px y texto ink.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.body16Medium)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Capsule().strokeBorder(Palette.ember, lineWidth: 1.5))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Campo con etiqueta encima, como en el diseño.
struct LabeledField<Field: View>: View {
    let label: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            Text(label)
                .font(Typography.body14Medium)
                .foregroundStyle(Palette.ink)
            field
                .font(Typography.body16)
                .padding(.horizontal, Spacing.s16)
                .frame(minHeight: 48)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                        .stroke(Palette.stone, lineWidth: 1)
                )
        }
    }
}

/// Mensaje de error bajo un formulario.
struct ErrorText: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(Typography.body14)
                .foregroundStyle(Palette.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

/// Aviso de que la app funciona sin servidor.
struct DemoBanner: View {
    var body: some View {
        Text("Modo demo: los datos se borran al cerrar la app.")
            .font(Typography.small12)
            .foregroundStyle(Palette.graphite)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s8)
            .background(Palette.stone.opacity(0.5))
    }
}

extension View {
    /// Teclado y autocorrección apropiados para nombres de usuario y códigos.
    func plainIdentifierInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }

    /// Ancho cómodo para formularios en Mac y iPad.
    func formWidth() -> some View {
        frame(maxWidth: 420)
    }
}
