import SwiftUI
import STMCore
import STMUI

/// Un enlace de invitación con un hogar ya abierto: nunca se une solo, pregunta antes.
struct JoinFromLinkModifier: ViewModifier {
    let household: Household

    @Environment(SessionModel.self) private var session
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("¿Unirte a otro hogar?",
                                isPresented: Binding(get: { session.pendingInvite != nil },
                                                     set: { if !$0 { session.pendingInvite = nil } }),
                                titleVisibility: .visible, presenting: session.pendingInvite) { code in
                Button("Unirme con el código \(code.display)") { join(code) }
                Button("Ahora no", role: .cancel) {}
            } message: { _ in
                Text("Seguirás en \(household.name): pertenecerás a los dos hogares y podrás cambiar de uno a otro en Hogar.")
            }
            .alert("No te has podido unir", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
    }

    private func join(_ code: InviteCode) {
        Task {
            do {
                try await session.join(code)
            } catch {
                self.error = (error as? AppError)?.text ?? AppError.unknown("").errorDescription
            }
        }
    }
}

/// QR y código para que la pareja se una.
struct InviteSheet: View {
    let invite: HouseholdInvite
    let householdName: String

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: Spacing.s24) {
            Text("Invita a tu pareja")
                .titleFont(.title1)
                .foregroundStyle(Palette.label)
            Text("Que escanee el QR con su móvil o escriba el código al unirse.")
                .font(Typography.body)
                .foregroundStyle(Palette.labelSecondary)
                .multilineTextAlignment(.center)

            if let code = invite.inviteCode {
                QRCodeView(text: code.link.absoluteString)
                    .frame(width: 200, height: 200)
                    .padding(Spacing.s16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.card))

                Text(code.display)
                    .font(Typography.largeTitle.monospaced())
                    .foregroundStyle(Palette.label)
                    .textSelection(.enabled)

                Text("Caduca \(invite.expiresAt.formatted(.relative(presentation: .named))) y sirve una sola vez.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)

                Button(copied ? "Código copiado" : "Copiar código",
                       systemImage: copied ? "checkmark" : "doc.on.doc") {
                    copyToClipboard(code.value)
                    copied = true
                }
                .buttonStyle(SecondaryButtonStyle())

                ShareLink(item: code.link,
                          message: Text("Únete a \(householdName) en Save the Money con el código \(code.display)")) {
                    Label("Compartir enlace", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Button("Listo") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Spacing.s24)
        .formWidth()
        .background(Palette.bgGrouped)
    }
}

/// Copiar al portapapeles en iPhone y en Mac.
func copyToClipboard(_ text: String) {
    #if os(iOS)
    UIPasteboard.general.string = text
    #else
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #endif
}

#Preview("Bienvenida") {
    HouseholdOnboardingView(profile: Profile(username: "ana", displayName: "Ana"))
        .environment(SessionModel(services: .demo()))
}
