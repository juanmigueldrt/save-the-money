import XCTest
@testable import STMCore

final class BudgetTemplateTests: XCTestCase {
    func testFiftyThirtyTwenty() {
        let allocation = BudgetTemplate.fiftyThirtyTwenty.allocate(Money(minor: 400_000))
        XCTAssertEqual(allocation[.needs]?.minor, 200_000)
        XCTAssertEqual(allocation[.wants]?.minor, 120_000)
        XCTAssertEqual(allocation[.savings]?.minor, 80_000)
    }

    func testGroupProgress() {
        let half = GroupProgress(group: .wants, allocated: Money(minor: 1_000), spent: Money(minor: 500))
        XCTAssertEqual(half.fraction, 0.5)
        XCTAssertFalse(half.isOver)

        let over = GroupProgress(group: .wants, allocated: Money(minor: 1_000), spent: Money(minor: 1_500))
        XCTAssertEqual(over.fraction, 1)
        XCTAssertTrue(over.isOver)
        XCTAssertEqual(over.remaining.minor, -500)

        let empty = GroupProgress(group: .savings, allocated: .zero, spent: .zero)
        XCTAssertEqual(empty.fraction, 0)
    }
}
