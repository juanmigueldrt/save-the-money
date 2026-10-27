import XCTest
@testable import SaveTheMoney

final class AppConfigTests: XCTestCase {
    func testEveryPhoneTabIsASection() {
        XCTAssertEqual(AppSection.phoneTabs.count, 5)
        XCTAssertTrue(AppSection.phoneTabs.allSatisfy(AppSection.allCases.contains))
    }

    func testMissingKeyIsDetected() {
        let config = AppConfig(supabaseURL: URL(string: "http://127.0.0.1:54321")!, supabaseAnonKey: "")
        XCTAssertTrue(config.isMissingSupabaseKey)
    }
}
