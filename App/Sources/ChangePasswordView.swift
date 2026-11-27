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
                    LabeledField(label: String(localized: "Contraseña actual")) {
                        SecureField("Contraseña actual", text: $form.currentPassword)
                            .textContentType(.password)
                    }
                    LabeledField(label: String(localized: "Nueva contraseña")) {
                        SecureField("Al menos \(SignUpForm.minimumPasswordLength) caracteres", text: $form.newPassword)
                            .newPasswordContentType()
                    }
                    LabeledField(label: String(localized: "Repite la nueva contraseña")) {
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
                error = appError.text
            } catch {
                self.error = AppError.unknown("").errorDescription
            }
        }
    }
}

// MARK: Borrar la cuenta (ORC-74)

/// Fila de Ajustes que abre el borrado de la cuenta.
struct DeleteAccountSection: View {
    @State private var isDeleting = false

    var body: some View {
        Section {
            Button(role: .destructive) { isDeleting = true } label: {
                Label("Borrar mi cuenta", systemImage: "person.crop.circle.badge.xmark")
            }
        } footer: {
            Text("Borra tu usuario y todo lo que has apuntado. Pide la contraseña y no se puede deshacer.")
        }
        .sheet(isPresented: $isDeleting) { DeleteAccountView() }
    }
}

/// Aviso de lo que se borra, la contraseña actual y un botón que dice lo que hace.
struct DeleteAccountView: View {
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s24) {
                    Text(DeletingAccount.warning)
                        .font(Typography.body)
                        .foregroundStyle(Palette.label)
                    LabeledField(label: String(localized: "Contraseña actual")) {
                        SecureField("Contraseña actual", text: $password)
                            .textContentType(.password)
                    }
                    ErrorText(message: error)
                    Button(role: .destructive, action: submit) {
                        if isWorking { ProgressView() } else { Text("Borrar mi cuenta para siempre") }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isWorking || password.isEmpty)
                }
                .padding(Spacing.s16)
            }
            .background(Palette.bgGrouped)
            .navigationTitle("Borrar mi cuenta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }

    private func submit() {
        error = nil
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                // Al terminar la sesión pasa a «sin sesión» y esta hoja desaparece con la pantalla.
                try await session.deleteAccount(currentPassword: password)
            } catch let appError as AppError {
                error = appError.text
            } catch {
                self.error = AppError.unknown("").errorDescription
            }
        }
    }
}
