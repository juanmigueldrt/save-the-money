import XCTest
@testable import STMCore

final class IdentityTests: XCTestCase {
    func testUsernameNormalizesAndBuildsAuthEmail() throws {
        let user = try Username("  Ana.Prueba ")
        XCTAssertEqual(user.value, "ana.prueba")
        XCTAssertEqual(user.authEmail, "ana.prueba@savethemoney.invalid")
    }

    func testUsernameValidation() {
        XCTAssertThrowsError(try Username("ab")) { XCTAssertEqual($0 as? Username.ValidationError, .tooShort) }
        XCTAssertThrowsError(try Username(String(repeating: "a", count: 31))) { XCTAssertEqual($0 as? Username.ValidationError, .tooLong) }
        XCTAssertThrowsError(try Username("ana prueba")) { XCTAssertEqual($0 as? Username.ValidationError, .invalidCharacters) }
        XCTAssertThrowsError(try Username("ana@correo")) { XCTAssertEqual($0 as? Username.ValidationError, .invalidCharacters) }
    }

    func testInviteCodeParsing() {
        XCTAssertEqual(InviteCode("4k9 q2x")?.value, "4K9Q2X")
        XCTAssertEqual(InviteCode("4K9-Q2X")?.value, "4K9Q2X")
        XCTAssertEqual(InviteCode("savethemoney://unirse/4K9Q2X")?.value, "4K9Q2X")
        XCTAssertNil(InviteCode("4K9Q2"))      // corto
        XCTAssertNil(InviteCode("4K9Q20"))     // el 0 no está en el alfabeto
        XCTAssertNil(InviteCode("4K9Q2XX"))    // largo
    }

    func testInviteCodeLinkAndDisplay() {
        let code = InviteCode("4K9Q2X")!
        XCTAssertEqual(code.link.absoluteString, "savethemoney://unirse/4K9Q2X")
        XCTAssertEqual(code.display, "4K9 Q2X")
        XCTAssertEqual(InviteCode(code.link.absoluteString), code)
    }
}
