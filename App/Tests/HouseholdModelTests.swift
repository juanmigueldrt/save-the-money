import XCTest
import STMCore
@testable import SaveTheMoney

private let clave = "contrasena-de-prueba"

/// Ana crea un hogar en un backend en memoria. Devuelve su sesión y el backend.
@MainActor
private func hogarDeAna() async throws -> (SessionModel, InMemoryBackend) {
    let services = AppServices.demo()
    let backend = try XCTUnwrap(services.auth as? InMemoryBackend)
    let session = SessionModel(services: services)
    try await session.signUp(SignUpForm(username: "ana", password: clave, passwordConfirmation: clave))
    try await session.createHousehold(name: "Casa de prueba")
    return (session, backend)
}

/// Bea crea su cuenta en el mismo backend y entra en el hogar de Ana con una invitación de Ana.
/// Al terminar, la sesión del backend vuelve a ser la de Ana.
@MainActor
private func beaEntra(en ana: SessionModel) async throws -> SessionModel {
    let created = await ana.models?.household.invite()
    let invite = try XCTUnwrap(created?.inviteCode)
    let bea = SessionModel(services: ana.services)
    try await bea.signUp(SignUpForm(username: "bea", password: clave, passwordConfirmation: clave))
    try await bea.join(invite)
    try await ana.signIn(username: "ana", password: clave)
    return bea
}

@MainActor
private func perfil(_ session: SessionModel) throws -> Profile {
    guard case .ready(let profile, _) = session.state else { return try XCTUnwrap(nil, "sin hogar: \(session.state)") }
    return profile
}

@MainActor
final class HouseholdModelTests: XCTestCase {
    func testInvitarCreaUnaInvitacionPendiente() async throws {
        let (session, _) = try await hogarDeAna()
        let model = try XCTUnwrap(session.models?.household)

        let invite = await model.invite()

        XCTAssertNotNil(invite)
        XCTAssertFalse(model.isInviting)
        XCTAssertNil(model.error)
        await model.load()
        XCTAssertEqual(model.invites.map(\.id), [try XCTUnwrap(invite).id])
    }

    func testInvitarSinRedAvisaYNoDevuelveInvitacion() async throws {
        let (session, backend) = try await hogarDeAna()
        let model = try XCTUnwrap(session.models?.household)
        await backend.failCalls("createInvite(for:)")

        let invite = await model.invite()

        XCTAssertNil(invite)
        XCTAssertFalse(model.isInviting)
        XCTAssertEqual(model.error, AppError.network.errorDescription)
    }

    func testAnularQuitaLaInvitacionPendiente() async throws {
        let (session, _) = try await hogarDeAna()
        let model = try XCTUnwrap(session.models?.household)
        let created = await model.invite()
        let invite = try XCTUnwrap(created)
        await model.load()

        await model.revoke(invite)

        XCTAssertTrue(model.invites.isEmpty)
        XCTAssertNil(model.error)
    }

    func testSiAnularFallaSeAvisaAunqueLaRecargaVayaBien() async throws {
        let (session, backend) = try await hogarDeAna()
        let model = try XCTUnwrap(session.models?.household)
        let created = await model.invite()
        let invite = try XCTUnwrap(created)
        await backend.failCalls("revokeInvite(_:)")

        await model.revoke(invite)

        XCTAssertEqual(model.invites.map(\.id), [invite.id])
        XCTAssertEqual(model.error, "No se ha podido anular la invitación. " + (AppError.network.errorDescription ?? ""))
    }

    func testLaDuenaQuitaAUnMiembro() async throws {
        let (ana, backend) = try await hogarDeAna()
        let bea = try await beaEntra(en: ana)
        let model = try XCTUnwrap(ana.models?.household)
        await model.load()
        XCTAssertEqual(model.members.count, 2)
        let anaId = try perfil(ana).id
        let miembro = try XCTUnwrap(model.members.first { $0.profile.id != anaId })

        await model.remove(miembro)

        XCTAssertNil(model.error)
        XCTAssertEqual(model.members.map(\.profile.id), [anaId])
        // Bea ya no ve el hogar.
        try await bea.signIn(username: "bea", password: clave)
        let suyos = try await backend.households()
        XCTAssertTrue(suyos.isEmpty)
        XCTAssertNil(bea.models)
    }

    func testUnMiembroNoPuedeQuitarALaDuena() async throws {
        let (ana, _) = try await hogarDeAna()
        let bea = try await beaEntra(en: ana)
        try await bea.signIn(username: "bea", password: clave)
        let model = try XCTUnwrap(bea.models?.household)
        await model.load()
        let duena = try XCTUnwrap(model.members.first { $0.role == .owner })

        await model.remove(duena)

        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.members.count, 2)
    }

    func testSalirLlevaACrearOUnirseYQuitaLosModelos() async throws {
        let (ana, _) = try await hogarDeAna()
        let bea = try await beaEntra(en: ana)
        try await bea.signIn(username: "bea", password: clave)
        let model = try XCTUnwrap(bea.models?.household)

        let salio = await model.leave(then: bea.refresh)

        XCTAssertTrue(salio)
        XCTAssertNil(model.error)
        guard case .needsHousehold = bea.state else { return XCTFail("debería pedir hogar, no \(bea.state)") }
        XCTAssertNil(bea.models)
        // Ana se queda sola en su hogar.
        try await ana.signIn(username: "ana", password: clave)
        let deAna = try XCTUnwrap(ana.models?.household)
        await deAna.load()
        XCTAssertEqual(deAna.members.map(\.profile.id), [try perfil(ana).id])
    }

    func testSiSalirFallaSeAvisaYSeQuedaEnElHogar() async throws {
        let (ana, backend) = try await hogarDeAna()
        let bea = try await beaEntra(en: ana)
        try await bea.signIn(username: "bea", password: clave)
        let model = try XCTUnwrap(bea.models?.household)
        await backend.failCalls("leave(householdId:)")

        let salio = await model.leave(then: bea.refresh)

        XCTAssertFalse(salio)
        XCTAssertEqual(model.error, AppError.network.errorDescription)
        guard case .ready = bea.state else { return XCTFail("debería seguir en el hogar, no \(bea.state)") }
    }
}

/// Los modelos del hogar se crean una vez al entrar en él, no en cada pintado de la vista raíz.
@MainActor
final class ModelosDelHogarTests: XCTestCase {
    func testLosModelosSeConservanMientrasElHogarSigueAbierto() async throws {
        let (session, backend) = try await hogarDeAna()
        let models = try XCTUnwrap(session.models)
        guard case .ready(_, let household) = session.state else { return XCTFail("sin hogar") }

        try await session.refresh()
        try await session.setTheme(.dark)
        try await session.renameHousehold(household, to: "Casa nueva")
        // Sin red con el hogar abierto se queda donde estaba (y con los mismos modelos).
        await backend.failCalls()
        await session.start()
        await backend.clearFailures()

        let after = try XCTUnwrap(session.models)
        XCTAssertTrue(after.finance === models.finance)
        XCTAssertTrue(after.budgets === models.budgets)
        XCTAssertTrue(after.planning === models.planning)
        XCTAssertTrue(after.tracking === models.tracking)
        XCTAssertTrue(after.investments === models.investments)
        XCTAssertTrue(after.cards === models.cards)
        XCTAssertTrue(after.household === models.household)
    }

    func testAlCerrarSesionNoQuedanModelosYAlVolverSonNuevos() async throws {
        let (session, _) = try await hogarDeAna()
        let antes = try XCTUnwrap(session.models)

        await session.signOut()
        XCTAssertNil(session.models)

        try await session.signIn(username: "ana", password: clave)
        let despues = try XCTUnwrap(session.models)
        XCTAssertFalse(despues.finance === antes.finance)
        XCTAssertEqual(despues.householdId, antes.householdId)
    }

    func testSinHogarNoHayModelos() async throws {
        let session = SessionModel(services: .demo())
        try await session.signUp(SignUpForm(username: "ana", password: clave, passwordConfirmation: clave))

        XCTAssertNil(session.models)
    }
}
