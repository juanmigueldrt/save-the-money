import XCTest
@testable import STMCore

final class QuickActionTests: XCTestCase {
    func testNewExpenseLink() {
        XCTAssertEqual(QuickAction.newExpense.link.absoluteString, "savethemoney://nuevo-gasto")
        XCTAssertEqual(QuickAction(url: URL(string: "savethemoney://nuevo-gasto")!), .newExpense)
        XCTAssertEqual(QuickAction(url: URL(string: "SaveTheMoney://Nuevo-Gasto/")!), .newExpense)
        XCTAssertEqual(QuickAction(url: URL(string: "savethemoney://new-expense")!), .newExpense)
    }

    func testOtherLinksAreNotQuickActions() {
        XCTAssertNil(QuickAction(url: URL(string: "savethemoney://unirse/4K9Q2X")!))
        XCTAssertNil(QuickAction(url: URL(string: "https://nuevo-gasto")!))
        XCTAssertNil(QuickAction(url: URL(string: "savethemoney://otra-cosa")!))
        // Y el enlace de nuevo gasto no se confunde con una invitación.
        XCTAssertNil(InviteCode(QuickAction.newExpense.link.absoluteString))
    }
}
