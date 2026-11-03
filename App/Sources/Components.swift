import SwiftUI
import STMUI

/// Botón prominente del manual v2: cápsula `accent` de 50 pt a ancho completo con
/// texto `on-accent` en headline (blanco sobre ember no llega a AA).
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.headline)
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: ControlSize.large)
            .background(Palette.accent.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4), in: Capsule())
            .shadow(color: Color.black.opacity(0.05), radius: 1, y: 1)
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

/// Botón gris del manual v2: cápsula con relleno `fill` y texto `label`.
/// Sustituye al botón contorneado de la v1.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.headline)
            .foregroundStyle(Palette.label.opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity, minHeight: ControlSize.large)
            .background(Palette.fill, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

/// Campo con etiqueta encima: cápsula `bg-grouped-2` de 44 pt con borde `separator`.
struct LabeledField<Field: View>: View {
    let label: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            Text(label)
                .font(Typography.subheadlineEmphasis)
                .foregroundStyle(Palette.label)
            field
                .font(Typography.body)
                .padding(.horizontal, Spacing.s16)
                .frame(minHeight: ControlSize.regular)
                .background(Palette.bgGrouped2, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.separator, lineWidth: 1))
        }
    }
}

/// Mensaje de error bajo un formulario.
struct ErrorText: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(Typography.subheadline)
                .foregroundStyle(Palette.negativeText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

/// Aviso de que la app funciona sin servidor.
struct DemoBanner: View {
    var body: some View {
        Text("Modo demo: los datos se borran al cerrar la app.")
            .font(Typography.footnote)
            .foregroundStyle(Palette.labelSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s8)
            .background(Palette.fill)
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

    /// Márgenes de página del manual (16 en iPhone, 20 en ventanas anchas) y un
    /// ancho máximo de 1200 para que en Mac las tarjetas no se estiren de lado a lado.
    func pageLayout() -> some View {
        #if os(macOS)
        padding(Spacing.s20)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        #else
        padding(Spacing.s16)
        #endif
    }

    /// Alto de un gráfico: el dado en iPhone y más alto en Mac, donde la página es
    /// mucho más ancha y un gráfico bajo se ve aplastado.
    func chartHeight(_ phone: CGFloat) -> some View {
        #if os(macOS)
        frame(height: max(phone * 1.6, 300))
        #else
        frame(height: phone)
        #endif
    }

    /// Ancho cómodo para formularios en Mac y iPad.
    func formWidth() -> some View {
        frame(maxWidth: 420)
    }
}

/// Dos columnas cuando caben (Mac, iPad en horizontal) y una sola en iPhone.
struct AdaptiveColumns<Leading: View, Trailing: View>: View {
    var spacing: CGFloat = Spacing.s24
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Spacing.s16) {
                leading.frame(minWidth: 380, maxWidth: .infinity, alignment: .topLeading)
                trailing.frame(minWidth: 380, maxWidth: .infinity, alignment: .topLeading)
            }
            VStack(alignment: .leading, spacing: spacing) {
                leading
                trailing
            }
        }
    }
}
