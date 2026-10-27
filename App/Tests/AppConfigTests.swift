import XCTest
import STMCore
@testable import SaveTheMoney

final class AppConfigTests: XCTestCase {
    func testEveryPhoneTabIsASection() {
        XCTAssertEqual(AppSection.phoneTabs.count, 5)
        XCTAssertTrue(AppSection.phoneTabs.allSatisfy(AppSection.allCases.contains))
    }

    func testMissingOrPlaceholderKeyMeansDemo() {
        let url = URL(string: "http://127.0.0.1:54321")!
        XCTAssertTrue(AppConfig(supabaseURL: url, supabaseAnonKey: "").isMissingSupabaseKey)
        XCTAssertTrue(AppConfig(supabaseURL: url, supabaseAnonKey: "pega-aqui-la-clave-anon").isMissingSupabaseKey)
        XCTAssertFalse(AppConfig(supabaseURL: url, supabaseAnonKey: "clave-real").isMissingSupabaseKey)
    }
}

@MainActor
final class SessionModelTests: XCTestCase {
    func testSignUpCreateHouseholdAndSignOut() async throws {
        let session = SessionModel(services: .demo())
        await session.start()
        XCTAssertEqual(session.state, .signedOut)

        try await session.signUp(SignUpForm(username: "ana", displayName: "Ana",
                                            password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        guard case .needsHousehold(let profile) = session.state else {
            return XCTFail("tras crear la cuenta falta el hogar, no \(session.state)")
        }
        XCTAssertEqual(profile.name, "Ana")

        try await session.createHousehold(name: "Casa de prueba")
        guard case .ready(_, let home) = session.state else {
            return XCTFail("debería estar listo, no \(session.state)")
        }
        XCTAssertEqual(home.name, "Casa de prueba")

        await session.signOut()
        XCTAssertEqual(session.state, .signedOut)
    }

    func testInviteLinkIsRemembered() {
        let session = SessionModel(services: .demo())
        session.handle(url: URL(string: "savethemoney://unirse/4K9Q2X")!)
        XCTAssertEqual(session.pendingInvite?.value, "4K9Q2X")
        session.handle(url: URL(string: "https://example.com")!)
        XCTAssertEqual(session.pendingInvite?.value, "4K9Q2X")
    }
}
