import SwiftUI
import STMCore
import STMUI

// MARK: Cambiar la contraseña (ORC-57)

/// Fila de Ajustes que abre el cambio de contraseña, junto al bloqueo de la app.
struct ChangePasswordSection: View {
    @State private var isChanging = false
    @State private var changed = false

    var body: some View {
        Section {
            Button { isChanging = true } label: {
                Label("Cambiar la contraseña", systemImage: "key")
            }
        } footer: {
            Text(changed
                 ? "Contraseña cambiada. Esta sesión sigue abierta; en tus otros dispositivos tendrás que volver a entrar."
                 : "Pide la contraseña actual. Al cambiarla se cierra la sesión en tus otros dispositivos.")
        }
        .sheet(isPresented: $isChanging) {
            ChangePasswordView { changed = true }
        }
    }
}

/// Formulario: contraseña actual y la nueva dos veces, con la misma regla que al crear la cuenta.
struct ChangePasswordView: View {
    var onChanged: () -> Void

    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var form = ChangePasswordForm()
    @State private var error: String?
    @State private var isWorking = false
    @State private var triedToSubmit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.s24) {
                    LabeledField(label: "Contraseña actual") {
                        SecureField("Contraseña actual", text: $form.currentPassword)
                            .textContentType(.password)
                    }
                    LabeledField(label: "Nueva contraseña") {
                        SecureField("Al menos \(SignUpForm.minimumPasswordLength) caracteres", text: $form.newPassword)
                            .newPasswordContentType()
                    }
                    LabeledField(label: "Repite la nueva contraseña") {
                        SecureField("Nueva contraseña", text: $form.newPasswordConfirmation)
                            .newPasswordContentType()
                            .onSubmit(submit)
                    }
                    ErrorText(message: error ?? (triedToSubmit ? form.firstIssue?.message : nil))
                    Button(action: submit) {
                        if isWorking { ProgressView().tint(Palette.onAccent) } else { Text("Cambiar la contraseña") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isWorking)
                }
                .padding(Spacing.s16)
            }
            .background(Palette.bgGrouped)
            .navigationTitle("Contraseña")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }

    private func submit() {
        triedToSubmit = true
        error = nil
        guard form.firstIssue == nil, !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await session.changePassword(form)
                onChanged()
                dismiss()
            } catch let appError as AppError {
                error = appError.errorDescription
            } catch {
                self.error = AppError.unknown("").errorDescription
            }
        }
    }
}
