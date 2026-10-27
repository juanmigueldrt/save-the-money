import SwiftUI
import STMUI

/// Botón principal: fondo ember, texto blanco, ocupa todo el ancho.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.body16Medium)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Palette.ember.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
    }
}

/// Botón secundario: borde y texto en ink.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.body16Medium)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                    .stroke(Palette.smoke, lineWidth: 1)
            )
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
