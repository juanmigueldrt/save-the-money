import XCTest
import STMCore
@testable import SaveTheMoney

@MainActor
final class CargaYLecturaCSVTests: XCTestCase {
    func testCargasSolapadasDejanCargandoHastaLaUltima() {
        let model = FinanceModel(household: Household(name: "Casa de prueba"), service: AppServices.demo().finance)
        XCTAssertFalse(model.isLoading)

        model.beginLoad()
        model.beginLoad()
        model.endLoad()
        // La primera carga que termina no apaga la pantalla: la otra sigue en curso.
        XCTAssertTrue(model.isLoading)

        model.endLoad()
        XCTAssertFalse(model.isLoading)
    }

    func testLeerCSVDelDiscoDaLoMismoQueElAnalisisSincrono() throws {
        let text = "Fecha;Concepto;Importe\n02/10/2026;Café;-1,50"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stm-orc95-\(UUID().uuidString).csv")
        try Data(text.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try CSVFileReader.read(url, savedFormats: [])

        XCTAssertEqual(file.fileName, url.lastPathComponent)
        XCTAssertEqual(file.text, text)
        XCTAssertEqual(file.table, CSVTable.parse(text))
        XCTAssertEqual(file.mapping, CSVMapping.detect(in: CSVTable.parse(text)))
        // Columnas a mano: Fecha es la 0, Concepto la 1 e Importe la 2.
        XCTAssertEqual(file.mapping?.date, 0)
        XCTAssertEqual(file.mapping?.description, 1)
        XCTAssertEqual(file.mapping?.amount, .signed(2))
        XCTAssertFalse(file.usedSavedFormat)
        XCTAssertNil(file.savedAccount)
    }

    func testUnArchivoDeMasDeDiezMegabytesSeRechaza() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stm-orc95-grande-\(UUID().uuidString).csv")
        try Data(count: CSVFileReader.maxBytes + 1).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try CSVFileReader.read(url, savedFormats: [])) { error in
            XCTAssertEqual(error as? CSVOpenFailure, .tooLarge)
        }
    }

    func testUnArchivoQueNoExisteNoSePuedeAbrir() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stm-orc95-no-existe-\(UUID().uuidString).csv")

        XCTAssertThrowsError(try CSVFileReader.read(url, savedFormats: [])) { error in
            XCTAssertEqual(error as? CSVOpenFailure, .cannotOpen)
        }
    }
}
