import SwiftUI
import STMCore
import STMUI

/// Tras crear la cuenta: crear un hogar o unirse al de la pareja.
struct HouseholdOnboardingView: View {
    let profile: Profile

    @Environment(SessionModel.self) private var session
    @State private var householdName = ""
    @State private var code = ""
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 0) {
            if session.isDemo { DemoBanner() }
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s32) {
                    VStack(alignment: .leading, spacing: Spacing.s8) {
                        Text("Hola, \(profile.name)")
                            .font(Typography.title32)
                            .foregroundStyle(Palette.ink)
                        Text("Crea tu hogar o únete al de tu pareja con su código.")
                            .font(Typography.body16)
                            .foregroundStyle(Palette.graphite)
                    }
                    .padding(.top, Spacing.s40)

                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text("Crear un hogar")
                            .font(Typography.title20)
                            .foregroundStyle(Palette.ink)
                        LabeledField(label: "Nombre del hogar") {
                            TextField("Casa de \(profile.name)", text: $householdName)
                        }
                        Button("Crear hogar", action: create)
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(isWorking)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text("Unirme con un código")
                            .font(Typography.title20)
                            .foregroundStyle(Palette.ink)
                        LabeledField(label: "Código de 6 caracteres") {
                            TextField("4K9 Q2X", text: $code)
                                .plainIdentifierInput()
                                .onSubmit(join)
                        }
                        Button("Unirme", action: join)
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(isWorking || code.isEmpty)
                    }
                    .card()

                    ErrorText(message: error)

                    Button("Cerrar sesión") { Task { await session.signOut() } }
                        .font(Typography.body14Medium)
                        .foregroundStyle(Palette.graphite)
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                }
                .padding(Spacing.s24)
                .formWidth()
                .frame(maxWidth: .infinity)
            }
        }
        .background(Palette.linen)
        .onAppear {
            if let pending = session.pendingInvite { code = pending.display }
        }
        .onChange(of: session.pendingInvite) { _, pending in
            if let pending { code = pending.display }
        }
    }

    private func create() {
        let name = HouseholdName.validated(householdName) ?? "Casa de \(profile.name)"
        run { try await session.createHousehold(name: name) }
    }

    private func join() {
        guard let invite = InviteCode(code) else {
            error = "El código tiene 6 letras o números, como 4K9 Q2X."
            return
        }
        run { try await session.join(invite) }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                try await action()
            } catch let appError as AppError {
                error = appError.errorDescription
            } catch {
                self.error = AppError.unknown("").errorDescription
            }
        }
    }
}

/// Sección Hogar: miembros, invitaciones y salir.
struct HouseholdView: View {
    let profile: Profile
    let household: Household

    @Environment(SessionModel.self) private var session
    @State private var members: [HouseholdMember] = []
    @State private var invites: [HouseholdInvite] = []
    @State private var shownInvite: HouseholdInvite?
    @State private var error: String?
    @State private var confirmingLeave = false

    private var myRole: MemberRole? {
        members.first { $0.profile.id == profile.id }?.role
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                Text(household.name)
                    .font(Typography.title32)
                    .foregroundStyle(Palette.ink)

                VStack(alignment: .leading, spacing: Spacing.s16) {
                    Text("Miembros")
                        .font(Typography.title20)
                        .foregroundStyle(Palette.ink)
                    ForEach(members) { member in
                        HStack {
                            Text(member.profile.name)
                                .font(Typography.body16Medium)
                                .foregroundStyle(Palette.ink)
                            if member.profile.id == profile.id {
                                Text("(tú)")
                                    .font(Typography.body14)
                                    .foregroundStyle(Palette.graphite)
                            }
                            Spacer()
                            Text(member.role.title)
                                .font(Typography.small12)
                                .foregroundStyle(Palette.graphite)
                        }
                    }
                    Button("Invitar a tu pareja", action: invite)
                        .buttonStyle(PrimaryButtonStyle())
                }
                .card()

                if !invites.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text("Invitaciones pendientes")
                            .font(Typography.title20)
                            .foregroundStyle(Palette.ink)
                        ForEach(invites) { pending in
                            HStack {
                                Text(pending.inviteCode?.display ?? pending.code)
                                    .font(Typography.body16Medium.monospaced())
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Text("Caduca \(pending.expiresAt.formatted(.relative(presentation: .named)))")
                                    .font(Typography.small12)
                                    .foregroundStyle(Palette.graphite)
                                Button("Anular") { revoke(pending) }
                                    .font(Typography.body14Medium)
                                    .foregroundStyle(Palette.red)
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .card()
                }

                ErrorText(message: error)

                VStack(spacing: Spacing.s16) {
                    if myRole == .member {
                        Button("Salir del hogar") { confirmingLeave = true }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Button("Cerrar sesión") { Task { await session.signOut() } }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(Spacing.s16)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.linen)
        .task(id: household.id) { await load() }
        .sheet(item: $shownInvite, onDismiss: { Task { await load() } }) { invite in
            InviteSheet(invite: invite, householdName: household.name)
        }
        .confirmationDialog("¿Salir de \(household.name)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Salir del hogar", role: .destructive) {
                Task {
                    do { try await session.leaveHousehold(household) }
                    catch { self.error = (error as? AppError)?.errorDescription }
                }
            }
        } message: {
            Text("Dejarás de ver las metas y gastos compartidos de este hogar.")
        }
    }

    private func load() async {
        do {
            members = try await session.services.households.members(of: household.id)
            invites = try await session.services.households.pendingInvites(for: household.id)
            error = nil
        } catch {
            self.error = (error as? AppError)?.errorDescription ?? AppError.unknown("").errorDescription
        }
    }

    private func invite() {
        Task {
            do {
                shownInvite = try await session.services.households.createInvite(for: household.id)
            } catch {
                self.error = (error as? AppError)?.errorDescription ?? AppError.unknown("").errorDescription
            }
        }
    }

    private func revoke(_ invite: HouseholdInvite) {
        Task {
            try? await session.services.households.revokeInvite(invite.id)
            await load()
        }
    }
}

/// QR y código para que la pareja se una.
struct InviteSheet: View {
    let invite: HouseholdInvite
    let householdName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.s24) {
            Text("Invita a tu pareja")
                .font(Typography.title32)
                .foregroundStyle(Palette.ink)
            Text("Que escanee el QR con la cámara del iPhone o escriba el código al unirse.")
                .font(Typography.body16)
                .foregroundStyle(Palette.graphite)
                .multilineTextAlignment(.center)

            if let code = invite.inviteCode {
                QRCodeView(text: code.link.absoluteString)
                    .frame(width: 200, height: 200)
                    .padding(Spacing.s16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.card))

                Text(code.display)
                    .font(Typography.title36.monospaced())
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)

                Text("Caduca \(invite.expiresAt.formatted(.relative(presentation: .named))) y sirve una sola vez.")
                    .font(Typography.small12)
                    .foregroundStyle(Palette.graphite)

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
        .background(Palette.linen)
    }
}

#Preview("Bienvenida") {
    HouseholdOnboardingView(profile: Profile(username: "ana", displayName: "Ana"))
        .environment(SessionModel(services: .demo()))
}
