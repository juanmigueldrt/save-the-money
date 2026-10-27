import SwiftUI
import STMCore
import STMUI

/// Iniciar sesión o crear cuenta.
struct AuthFlowView: View {
    @State private var showingSignUp = false
    @Environment(SessionModel.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            if session.isDemo { DemoBanner() }
            ScrollView {
                VStack(spacing: Spacing.s32) {
                    VStack(spacing: Spacing.s8) {
                        Text("Save the Money")
                            .font(Typography.title36)
                            .foregroundStyle(Palette.ink)
                        Text(showingSignUp ? "Crea tu cuenta para empezar." : "Tu presupuesto, compartido en casa.")
                            .font(Typography.body16)
                            .foregroundStyle(Palette.graphite)
                    }
                    .padding(.top, Spacing.s64)

                    if showingSignUp {
                        SignUpView(onShowLogin: { showingSignUp = false })
                    } else {
                        LoginView(onShowSignUp: { showingSignUp = true })
                    }
                }
                .padding(Spacing.s24)
                .formWidth()
                .frame(maxWidth: .infinity)
            }
        }
        .background(Palette.linen)
    }
}

struct LoginView: View {
    var onShowSignUp: () -> Void

    @Environment(SessionModel.self) private var session
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: Spacing.s24) {
            LabeledField(label: "Usuario") {
                TextField("tu-usuario", text: $username)
                    .textContentType(.username)
                    .plainIdentifierInput()
            }
            LabeledField(label: "Contraseña") {
                SecureField("Contraseña", text: $password)
                    .textContentType(.password)
                    .onSubmit(submit)
            }
            ErrorText(message: error)
            Button(action: submit) {
                if isWorking { ProgressView().tint(.white) } else { Text("Iniciar sesión") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(username.isEmpty || password.isEmpty || isWorking)

            Button("¿No tienes cuenta? Crear una", action: onShowSignUp)
                .font(Typography.body14Medium)
                .foregroundStyle(Palette.ember)
                .buttonStyle(.plain)
        }
    }

    private func submit() {
        guard !isWorking else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                try await session.signIn(username: username, password: password)
            } catch let appError as AppError {
                error = appError.errorDescription
            } catch {
                // Un nombre de usuario mal escrito no debe revelar más que una contraseña mala.
                self.error = AppError.invalidCredentials.errorDescription
            }
        }
    }
}

struct SignUpView: View {
    var onShowLogin: () -> Void

    @Environment(SessionModel.self) private var session
    @State private var form = SignUpForm()
    @State private var error: String?
    @State private var isWorking = false
    @State private var triedToSubmit = false

    var body: some View {
        VStack(spacing: Spacing.s24) {
            LabeledField(label: "Usuario") {
                TextField("tu-usuario", text: $form.username)
                    .textContentType(.username)
                    .plainIdentifierInput()
            }
            LabeledField(label: "Tu nombre (opcional)") {
                TextField("Cómo te verá tu pareja", text: $form.displayName)
                    .nameContentType()
            }
            LabeledField(label: "Contraseña") {
                SecureField("Al menos \(SignUpForm.minimumPasswordLength) caracteres", text: $form.password)
                    .newPasswordContentType()
            }
            LabeledField(label: "Repite la contraseña") {
                SecureField("Contraseña", text: $form.passwordConfirmation)
                    .newPasswordContentType()
                    .onSubmit(submit)
            }
            ErrorText(message: error ?? (triedToSubmit ? form.firstIssue?.message : nil))
            Button(action: submit) {
                if isWorking { ProgressView().tint(.white) } else { Text("Crear cuenta") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isWorking)

            Button("Ya tengo cuenta", action: onShowLogin)
                .font(Typography.body14Medium)
                .foregroundStyle(Palette.ember)
                .buttonStyle(.plain)
        }
    }

    private func submit() {
        triedToSubmit = true
        error = nil
        guard form.firstIssue == nil, !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await session.signUp(form)
            } catch let appError as AppError {
                error = appError.errorDescription
            } catch {
                self.error = AppError.unknown("").errorDescription
            }
        }
    }
}

private extension View {
    func nameContentType() -> some View {
        #if os(iOS)
        self.textContentType(.name)
        #else
        self
        #endif
    }

    func newPasswordContentType() -> some View {
        #if os(iOS)
        self.textContentType(.newPassword)
        #else
        self.textContentType(.password)
        #endif
    }
}

#Preview("Iniciar sesión") {
    AuthFlowView()
        .environment(SessionModel(services: .demo()))
}
