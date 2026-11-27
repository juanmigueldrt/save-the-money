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
    @State private var deletingAccount = false

    var body: some View {
        VStack(spacing: 0) {
            if session.isDemo { DemoBanner() }
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s32) {
                    VStack(alignment: .leading, spacing: Spacing.s8) {
                        Text("Hola, \(profile.name)")
                            .titleFont(.title1)
                            .foregroundStyle(Palette.label)
                        Text("Crea tu hogar o únete al de tu pareja con su código.")
                            .font(Typography.body)
                            .foregroundStyle(Palette.labelSecondary)
                    }
                    .padding(.top, Spacing.s40)

                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text("Crear un hogar")
                            .titleFont(.title2)
                            .foregroundStyle(Palette.label)
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
                            .titleFont(.title2)
                            .foregroundStyle(Palette.label)
                        LabeledField(label: "Código de 6 caracteres") {
                            TextField("4K9 Q2X", text: $code)
                                .plainIdentifierInput()
                                .onSubmit(join)
                        }
                        Button("Unirme", action: join)
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(isWorking || code.isEmpty)
                        ScanInviteButton { invite in
                            code = invite.display
                            join()
                        }
                        .disabled(isWorking)
                    }
                    .card()

                    if !session.removedHouseholds.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.s16) { RemovedHouseholdRows() }
                            .card()
                    }

                    ErrorText(message: error)

                    Button("Cerrar sesión") { Task { await session.signOut() } }
                        .font(Typography.subheadlineEmphasis)
                        .foregroundStyle(Palette.labelSecondary)
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)

                    // Quien aún no tiene hogar también tiene que poder borrar su cuenta.
                    Button("Borrar mi cuenta") { deletingAccount = true }
                        .font(Typography.subheadlineEmphasis)
                        .foregroundStyle(Palette.negativeText)
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .sheet(isPresented: $deletingAccount) { DeleteAccountView() }
                }
                .padding(Spacing.s24)
                .formWidth()
                .frame(maxWidth: .infinity)
            }
        }
        .background(Palette.bgGrouped)
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
                error = appError.text
            } catch {
                self.error = AppError.unknown("").errorDescription
            }
        }
    }
}

/// Sección Hogar: elegir hogar, ajustes del hogar y del perfil, miembros, invitaciones y salir.
struct HouseholdView: View {
    let profile: Profile
    let household: Household

    @Environment(SessionModel.self) private var session
    @Environment(HouseholdModel.self) private var model
    @State private var shownInvite: HouseholdInvite?
    @State private var confirmingLeave = false
    @State private var removing: HouseholdMember?
    @State private var promoting: HouseholdMember?
    @State private var renaming = false
    @State private var newName = ""
    @State private var startDay = 1
    @State private var displayName = ""
    @State private var isSaving = false

    private var myRole: MemberRole? { model.role(of: profile.id) }
    /// El propietario no puede salir con otros miembros dentro (ORC-59): el servidor también lo impide.
    private var ownerWithOthers: Bool { myRole == .owner && model.members.count > 1 }
    private var leaveMessage: String {
        if ownerWithOthers { return LeavingHousehold.ownerMustTransfer }
        return model.members.count == 1
            ? LeavingHousehold.leaveWarning + " " + LeavingHousehold.lastMemberWarning
            : LeavingHousehold.leaveWarning
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                HStack(alignment: .firstTextBaseline) {
                    Text(household.name)
                        .titleFont(.title1)
                        .foregroundStyle(Palette.label)
                    Spacer()
                    if myRole == .owner {
                        Button("Cambiar nombre", systemImage: "pencil") {
                            newName = household.name
                            renaming = true
                        }
                        .labelStyle(.iconOnly)
                        .font(Typography.headline)
                        .help("Cambiar el nombre del hogar")
                    }
                }

                if session.households.count > 1 { householdPicker }

                monthStartCard

                displayNameCard

                VStack(alignment: .leading, spacing: Spacing.s16) {
                    Text("Miembros")
                        .titleFont(.title2)
                        .foregroundStyle(Palette.label)
                    ForEach(model.members) { member in
                        HStack {
                            Text(member.profile.name)
                                .font(Typography.headline)
                                .foregroundStyle(Palette.label)
                            if member.profile.id == profile.id {
                                Text("(tú)")
                                    .font(Typography.subheadline)
                                    .foregroundStyle(Palette.labelSecondary)
                            }
                            Spacer()
                            Text(member.role.title)
                                .font(Typography.footnote)
                                .foregroundStyle(Palette.labelSecondary)
                            if myRole == .owner && member.profile.id != profile.id {
                                Button("Hacer propietario") { promoting = member }
                                    .font(Typography.subheadlineEmphasis)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Hacer propietario a \(member.profile.name)")
                                Button("Quitar") { removing = member }
                                    .font(Typography.subheadlineEmphasis)
                                    .foregroundStyle(Palette.negativeText)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Quitar a \(member.profile.name) del hogar")
                            }
                        }
                    }
                    Button("Invitar a tu pareja") { Task { shownInvite = await model.invite() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(model.isInviting)
                }
                .card()

                if !model.invites.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text("Invitaciones pendientes")
                            .titleFont(.title2)
                            .foregroundStyle(Palette.label)
                        ForEach(model.invites) { pending in
                            HStack {
                                Text(pending.inviteCode?.display ?? pending.code)
                                    .font(Typography.headline.monospaced())
                                    .foregroundStyle(Palette.label)
                                Spacer()
                                Text("Caduca \(pending.expiresAt.formatted(.relative(presentation: .named)))")
                                    .font(Typography.footnote)
                                    .foregroundStyle(Palette.labelSecondary)
                                Button("Anular") { Task { await model.revoke(pending) } }
                                    .font(Typography.subheadlineEmphasis)
                                    .foregroundStyle(Palette.negativeText)
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .card()
                }

                ErrorText(message: model.error)

                VStack(spacing: Spacing.s16) {
                    if myRole != nil {
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
        .background(Palette.bgGrouped)
        .task(id: household.id) { await model.load() }
        .onAppear {
            startDay = household.monthStartDay
            displayName = profile.displayName ?? ""
        }
        .sheet(item: $shownInvite, onDismiss: { Task { await model.load() } }, content: { invite in
            InviteSheet(invite: invite, householdName: household.name)
        })
        .alert("Nombre del hogar", isPresented: $renaming) {
            TextField("Nombre del hogar", text: $newName)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") {
                Task {
                    do { try await session.renameHousehold(household, to: newName) }
                    catch { model.error = (error as? AppError)?.text ?? "No se ha podido cambiar el nombre." }
                }
            }
        } message: {
            Text("Lo verán todos los miembros.")
        }
        .confirmationDialog("¿Salir de \(household.name)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            if !ownerWithOthers {
                Button("Salir del hogar", role: .destructive) {
                    Task { await model.leave(then: session.refresh) }
                }
            }
        } message: {
            Text(leaveMessage)
        }
        .confirmationDialog("¿Hacer propietario a \(promoting?.profile.name ?? "")?",
                            isPresented: Binding(get: { promoting != nil }, set: { if !$0 { promoting = nil } }),
                            titleVisibility: .visible, presenting: promoting) { member in
            Button("Hacer propietario") {
                Task { await model.makeOwner(member) }
            }
        } message: { _ in
            Text(LeavingHousehold.transferWarning)
        }
        .confirmationDialog("¿Quitar a \(removing?.profile.name ?? "") del hogar?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { member in
            Button("Quitar del hogar", role: .destructive) {
                Task { await model.remove(member) }
            }
        } message: { _ in
            Text(LeavingHousehold.removeWarning)
        }
    }
}

extension HouseholdView {
    /// Con más de un hogar: cuál está abierto. Al cambiar se cargan los datos del otro desde cero.
    private var householdPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text("Tus hogares")
                .titleFont(.title2)
                .foregroundStyle(Palette.label)
            Picker("Hogar abierto", selection: Binding(get: { household.id }, set: { id in
                if let other = session.households.first(where: { $0.id == id }) { session.open(other) }
            })) {
                ForEach(session.households) { Text($0.name).tag($0.id) }
            }
            Text("Cada hogar tiene sus propias cuentas y presupuestos. Este dispositivo recuerda cuál abriste.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
        }
        .card()
    }

    /// Día de inicio del mes: lo cambia solo el dueño; los demás lo ven.
    private var monthStartCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text("Inicio del mes")
                .titleFont(.title2)
                .foregroundStyle(Palette.label)
            if myRole == .owner {
                Picker("Día de inicio del mes", selection: $startDay) {
                    ForEach(Household.monthStartDays, id: \.self) { Text("Día \($0)").tag($0) }
                }
                Button("Guardar día de inicio") { saveStartDay() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isSaving || startDay == household.monthStartDay)
            } else {
                Text(myRole == .member
                     ? "El mes del hogar empieza el día \(household.monthStartDay). Solo quien creó el hogar puede cambiarlo."
                     : "El mes del hogar empieza el día \(household.monthStartDay).")
                    .font(Typography.body)
                    .foregroundStyle(Palette.label)
            }
            Text("Presupuestos, informes y «este mes» cuentan desde este día. No se cambia ni se borra ningún movimiento.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
        }
        .card()
    }

    /// Nombre visible de quien ha entrado, el que ven los demás miembros.
    private var displayNameCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Text("Tu nombre")
                .titleFont(.title2)
                .foregroundStyle(Palette.label)
            LabeledField(label: "Nombre visible") {
                TextField(profile.username, text: $displayName)
                    .accessibilityLabel("Nombre visible")
                    .onSubmit(saveDisplayName)
            }
            Button("Guardar nombre", action: saveDisplayName)
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isSaving || SignUpForm(displayName: displayName).trimmedDisplayName == profile.displayName)
            Text("Es como te ven los demás miembros. Vacío, se usa tu usuario (\(profile.username)); como mucho 60 caracteres.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
        }
        .card()
    }

    private func saveStartDay() {
        save { try await session.setMonthStartDay(startDay) }
    }

    private func saveDisplayName() {
        save {
            try await session.setDisplayName(displayName)
            // La lista de miembros lleva el nombre: se vuelve a pedir.
            await model.load()
        }
    }

    /// Si el servidor lo rechaza (p. ej. quien no es dueño), su aviso se ve en la pantalla.
    private func save(_ action: @escaping () async throws -> Void) {
        guard !isSaving else { return }
        isSaving = true
        model.error = nil
        Task {
            defer { isSaving = false }
            do {
                try await action()
            } catch {
                model.error = (error as? AppError)?.text ?? AppError.unknown("").errorDescription
            }
        }
    }
}
