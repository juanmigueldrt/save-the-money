import XCTest
@testable import STMCore

final class MoneyTests: XCTestCase {
    func testParsesSpanishAndEnglishFormats() {
        XCTAssertEqual(Money(parsing: "1.234,56")?.minor, 123_456)
        XCTAssertEqual(Money(parsing: "1,234.56")?.minor, 123_456)
        XCTAssertEqual(Money(parsing: "-12,5")?.minor, -1_250)
        XCTAssertEqual(Money(parsing: "12.50 €")?.minor, 1_250)
        XCTAssertEqual(Money(parsing: "(45,00)")?.minor, -4_500)
        XCTAssertEqual(Money(parsing: "1.000")?.minor, 100_000)
        XCTAssertEqual(Money(parsing: "7")?.minor, 700)
        XCTAssertEqual(Money(parsing: "0,05")?.minor, 5)
    }

    func testRejectsInvalidText() {
        XCTAssertNil(Money(parsing: ""))
        XCTAssertNil(Money(parsing: "abc"))
        XCTAssertNil(Money(parsing: "12,345,6x"))
        XCTAssertNil(Money(parsing: "99999999999999999999"))
    }

    func testArithmetic() {
        let a = Money(minor: 1_000), b = Money(minor: 250)
        XCTAssertEqual((a + b).minor, 1_250)
        XCTAssertEqual((a - b).minor, 750)
        XCTAssertEqual((-a).minor, -1_000)
        XCTAssertTrue(b < a)
    }

    func testSplitKeepsEveryCent() {
        let parts = Money(minor: 1_001).split(percentages: [50, 30, 20])
        XCTAssertEqual(parts.map(\.minor).reduce(0, +), 1_001)
        XCTAssertEqual(parts.map(\.minor), [501, 300, 200])

        let negative = Money(minor: -1_001).split(percentages: [50, 30, 20])
        XCTAssertEqual(negative.map(\.minor).reduce(0, +), -1_001)
    }

    func testFormatsInSpanish() {
        let text = Money(minor: 123_456).formatted()
        XCTAssertTrue(text.contains("1234,56") || text.contains("1.234,56"), text)
        XCTAssertTrue(text.contains("€"), text)
    }
}
