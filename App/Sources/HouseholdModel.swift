import Foundation
import Observation
import STMCore

/// Sección Hogar del hogar abierto: miembros, invitaciones pendientes, invitar, anular, quitar y salir.
@Observable
@MainActor
final class HouseholdModel: ServerModel {
    let householdId: UUID
    private let service: any HouseholdService

    private(set) var members: [HouseholdMember] = []
    private(set) var invites: [HouseholdInvite] = []
    /// Mientras se crea una invitación: «Invitar» queda desactivado para no crear dos.
    private(set) var isInviting = false
    var error: String?
    var isLoading = false
    @ObservationIgnored var turns = ReadTurns()

    init(householdId: UUID, service: any HouseholdService) {
        self.householdId = householdId
        self.service = service
    }

    /// El papel de `profileId` en el hogar, o nil si no es miembro o aún no se ha cargado.
    func role(of profileId: UUID) -> MemberRole? {
        members.first { $0.profile.id == profileId }?.role
    }

    func load() async {
        let turn = nextTurn()
        await perform(turn: turn) { try await fetch(turn: turn) }
    }

    private func fetch(turn: Int) async throws {
        let service = service, id = householdId
        async let members = service.members(of: id)
        async let invites = service.pendingInvites(for: id)
        let list = try await (members, invites)
        store(list.0, in: \.members, turn: turn)
        store(list.1, in: \.invites, turn: turn)
    }

    /// La invitación nueva, o nil si ha fallado (el aviso queda en `error`) o ya se estaba creando otra.
    func invite() async -> HouseholdInvite? {
        guard !isInviting else { return nil }
        isInviting = true
        defer { isInviting = false }
        var created: HouseholdInvite?
        await perform { created = try await service.createInvite(for: householdId) }
        return created
    }

    /// Anula y vuelve a cargar. Si la anulación falla se avisa, aunque la recarga vaya bien.
    func revoke(_ invite: HouseholdInvite) async {
        let revoked = await perform { try await service.revokeInvite(invite.id) }
        if !revoked, let message = error { error = "No se ha podido anular la invitación. " + message }
        await reloadAfterSave { try await fetch(turn: nextTurn()) }
    }

    /// Solo el dueño. Tras quitarle se vuelve a cargar la lista.
    func remove(_ member: HouseholdMember) async {
        let removed = await perform { try await service.removeMember(member.profile.id, from: householdId) }
        guard removed else { return }
        await reloadAfterSave { try await fetch(turn: nextTurn()) }
    }

    /// Solo el propietario: pasa el hogar a `member` y vuelve a cargar la lista, que es de donde sale quién manda.
    func makeOwner(_ member: HouseholdMember) async {
        let done = await perform { try await service.transferHousehold(householdId, to: member.profile.id) }
        guard done else { return }
        await reloadAfterSave { try await fetch(turn: nextTurn()) }
    }

    /// Sale del hogar y, si ha ido bien, `refresh` lleva a la sesión a su siguiente hogar o a crear uno.
    @discardableResult
    func leave(then refresh: () async throws -> Void) async -> Bool {
        await perform {
            try await service.leave(householdId: householdId)
            try await refresh()
        }
    }
}
