import XCTest
@testable import STMCore

final class HouseholdFlowTests: XCTestCase {
    func testSignUpFormValidation() {
        XCTAssertEqual(SignUpForm(username: "ab", password: "x").firstIssue, .username(.tooShort))
        XCTAssertEqual(SignUpForm(username: "ana", password: "corta").firstIssue, .passwordTooShort)
        XCTAssertEqual(SignUpForm(username: "ana", password: "contrasena-1", passwordConfirmation: "otra-cosa-1").firstIssue, .passwordsDoNotMatch)
        XCTAssertNil(SignUpForm(username: "ana", password: "contrasena-1", passwordConfirmation: "contrasena-1").firstIssue)
        XCTAssertNil(SignUpForm(displayName: "   ").trimmedDisplayName)
    }

    func testHouseholdName() {
        XCTAssertEqual(HouseholdName.validated("  Casa  "), "Casa")
        XCTAssertNil(HouseholdName.validated("   "))
        XCTAssertNil(HouseholdName.validated(String(repeating: "a", count: 81)))
    }

    func testInviteFlowBetweenTwoPeople() async throws {
        let backend = InMemoryBackend()
        let password = "contrasena-de-prueba"

        _ = try await backend.signUp(username: Username("ana"), password: password, displayName: "Ana")
        let home = try await backend.createHousehold(name: "Casa de prueba")
        let invite = try await backend.createInvite(for: home.id)
        XCTAssertNotNil(invite.inviteCode)
        try await backend.signOut()

        _ = try await backend.signUp(username: Username("bruno"), password: password, displayName: nil)
        let empty = try await backend.households()
        XCTAssertTrue(empty.isEmpty)
        let joined = try await backend.acceptInvite(XCTUnwrap(invite.inviteCode))
        XCTAssertEqual(joined.id, home.id)

        let members = try await backend.members(of: home.id)
        XCTAssertEqual(Set(members.map(\.profile.username)), ["ana", "bruno"])
        XCTAssertEqual(members.first { $0.profile.username == "bruno" }?.role, .member)
        let profile = try await backend.myProfile()
        XCTAssertEqual(profile.defaultHouseholdId, home.id)

        do {
            _ = try await backend.acceptInvite(XCTUnwrap(invite.inviteCode))
            XCTFail("un código usado no debe valer otra vez")
        } catch {
            XCTAssertEqual(error as? AppError, .invalidOrExpiredInvite)
        }
    }

    func testExpiredInviteAndWrongPassword() async throws {
        let clock = Clock()
        let backend = InMemoryBackend(now: { clock.now })
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-1", displayName: nil)
        let home = try await backend.createHousehold(name: "Casa")
        let invite = try await backend.createInvite(for: home.id)
        clock.now = clock.now.addingTimeInterval(49 * 3600)
        try await backend.signOut()

        _ = try await backend.signUp(username: Username("bruno"), password: "contrasena-2", displayName: nil)
        do {
            _ = try await backend.acceptInvite(XCTUnwrap(invite.inviteCode))
            XCTFail("un código caducado no debe valer")
        } catch {
            XCTAssertEqual(error as? AppError, .invalidOrExpiredInvite)
        }

        try await backend.signOut()
        do {
            _ = try await backend.signIn(username: Username("ana"), password: "mal")
            XCTFail("contraseña incorrecta")
        } catch {
            XCTAssertEqual(error as? AppError, .invalidCredentials)
        }
    }

    func testDecodesServerRows() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-00000000000a","username":"ana","display_name":null,
         "theme":"dark","default_household_id":null,"created_at":"2026-10-27T10:00:00+00:00"}
        """
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.theme, .dark)
        XCTAssertEqual(profile.name, "ana")
    }
}

/// Reloj que la prueba puede adelantar.
private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}
