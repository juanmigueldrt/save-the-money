import XCTest
@testable import SaveTheMoney

@MainActor
final class CSVImportTitleTests: XCTestCase {
    func testBotonDeImportarUsaSingularYPlural() {
        XCTAssertEqual(CSVImportView.buttonTitle(validCount: 0), "Importar")
        XCTAssertEqual(CSVImportView.buttonTitle(validCount: 1), "Importar 1 movimiento")
        XCTAssertEqual(CSVImportView.buttonTitle(validCount: 2), "Importar 2 movimientos")
    }
}
