import XCTest
@testable import STMCore

/// Archivos inventados con la forma de los que exportan los bancos españoles.
final class CSVImportTests: XCTestCase {
    let account = UUID()

    func testSHA256KnownVectors() {
        XCTAssertEqual(SHA256.hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hex(String(repeating: "a", count: 1000)).count, 64)
    }

    func testParsesQuotesSemicolonsAndCRLF() {
        let text = "\u{FEFF}Fecha;Concepto;Importe\r\n01/10/2026;\"Pago; con punto y coma\";-12,50\r\n02/10/2026;\"Dice \"\"hola\"\"\";1.000,00\r\n\r\n"
        let table = CSVTable.parse(text)
        XCTAssertEqual(table.delimiter, ";")
        XCTAssertEqual(table.rows.count, 3)
        XCTAssertEqual(table.rows[1], ["01/10/2026", "Pago; con punto y coma", "-12,50"])
        XCTAssertEqual(table.rows[2][1], "Dice \"hola\"")
    }

    func testDecodesWindows1252() {
        let bytes: [UInt8] = Array("Concepto: N".utf8) + [0xF3] + Array("mina".utf8) // "Nómina" en Windows-1252
        XCTAssertEqual(CSVTable.decode(Data(bytes)), "Concepto: Nómina")
        XCTAssertEqual(CSVTable.decode(Data([0xEF, 0xBB, 0xBF] + Array("hola".utf8))), "hola")
    }

    func testDetectsHeaderAfterBankPreamble() throws {
        let text = """
        Titular:;PERSONA DE PRUEBA
        Cuenta:;ES00 0000 0000 0000 0000 0000
        Periodo:;01/10/2026 - 31/10/2026

        F. Operación;F. Valor;Concepto;Importe;Saldo
        03/10/2026;03/10/2026;SUPERMERCADO EJEMPLO;-45,20;1.954,80
        01/10/2026;01/10/2026;NOMINA EMPRESA FICTICIA;2.000,00;2.000,00
        """
        let table = CSVTable.parse(text)
        let mapping = try XCTUnwrap(CSVMapping.detect(in: table))
        XCTAssertEqual(mapping.headerRow, 3)
        XCTAssertEqual(mapping.date, 0, "usa la fecha de operación, no la de valor")
        XCTAssertEqual(mapping.description, 2)
        XCTAssertEqual(mapping.amount, .signed(3), "el saldo no es el importe")

        let rows = CSVImporter.rows(in: table, mapping: mapping, accountId: account)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].draft?.amount.minor, -4520)
        XCTAssertEqual(rows[0].draft?.bookedOn.iso, "2026-10-03")
        XCTAssertEqual(rows[0].line, 5)
        XCTAssertEqual(rows[1].draft?.amount.minor, 200_000)
    }

    func testDebitAndCreditColumns() throws {
        let text = """
        Fecha,Descripción,Cargo,Abono
        2026-10-05,Gasolinera,30.00,
        2026-10-06,Bizum recibido,,15.5
        """
        let table = CSVTable.parse(text)
        XCTAssertEqual(table.delimiter, ",")
        let mapping = try XCTUnwrap(CSVMapping.detect(in: table))
        XCTAssertEqual(mapping.amount, .split(debit: 2, credit: 3))
        let rows = CSVImporter.rows(in: table, mapping: mapping, accountId: account)
        XCTAssertEqual(rows.map { $0.draft?.amount.minor }, [-3000, 1550])
        XCTAssertEqual(rows[0].draft?.bookedOn.iso, "2026-10-05")
    }

    func testFileWithoutHeader() throws {
        let text = """
        28/10/26\tCafetería de prueba\t-2,10
        27/10/26\tLibrería\t-15,00
        """
        let table = CSVTable.parse(text)
        XCTAssertEqual(table.delimiter, "\t")
        let mapping = try XCTUnwrap(CSVMapping.detect(in: table))
        XCTAssertNil(mapping.headerRow)
        let rows = CSVImporter.rows(in: table, mapping: mapping, accountId: account)
        XCTAssertEqual(rows.compactMap { $0.draft?.description }, ["Cafetería de prueba", "Librería"])
        XCTAssertEqual(rows.first?.draft?.bookedOn.iso, "2026-10-28")
    }

    func testBadRowsAreReportedAndBlankRowsSkipped() throws {
        let text = """
        Fecha;Concepto;Importe
        01/10/2026;Bien;-1,00
        32/10/2026;Fecha imposible;-1,00
        02/10/2026;Sin importe;
        ;;
        ;Total;-2,00
        """
        let table = CSVTable.parse(text)
        let mapping = try XCTUnwrap(CSVMapping.detect(in: table))
        let rows = CSVImporter.rows(in: table, mapping: mapping, accountId: account)
        XCTAssertEqual(rows.count, 3)
        XCTAssertNotNil(rows[0].draft)
        XCTAssertNotNil(rows[1].issue)
        XCTAssertEqual(rows[2].issue, "Importe vacío o no válido")
    }

    func testIdenticalRowsGetDifferentHashesButReimportMatches() throws {
        let text = """
        Fecha;Concepto;Importe
        01/10/2026;Café;-1,50
        01/10/2026;Café;-1,50
        """
        let table = CSVTable.parse(text)
        let mapping = try XCTUnwrap(CSVMapping.detect(in: table))
        let first = CSVImporter.rows(in: table, mapping: mapping, accountId: account).compactMap(\.draft?.importHash)
        let again = CSVImporter.rows(in: table, mapping: mapping, accountId: account).compactMap(\.draft?.importHash)
        XCTAssertEqual(first.count, 2)
        XCTAssertNotEqual(first[0], first[1], "dos cafés el mismo día son dos movimientos")
        XCTAssertEqual(first, again, "el mismo archivo da las mismas huellas")
        XCTAssertTrue(first.allSatisfy { $0.count == 64 })
    }

    func testDateOrders() {
        XCTAssertEqual(DateOrder.dayMonthYear.parse("28.10.2026")?.iso, "2026-10-28")
        XCTAssertEqual(DateOrder.dayMonthYear.parse("2026-10-28 13:45")?.iso, "2026-10-28")
        XCTAssertEqual(DateOrder.monthDayYear.parse("10/28/2026")?.iso, "2026-10-28")
        XCTAssertNil(DateOrder.dayMonthYear.parse("29/02/2026"))
        XCTAssertEqual(DateOrder.dayMonthYear.parse("29/02/2028")?.iso, "2028-02-29")
        XCTAssertNil(DateOrder.dayMonthYear.parse("hoy"))
    }

    func testImportSkipsDuplicatesInMemory() async throws {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        let home = try await backend.createHousehold(name: "Casa")
        let account = try await backend.createAccount(AccountDraft(name: "Corriente"), in: home.id)

        let table = CSVTable.parse("Fecha;Concepto;Importe\n01/10/2026;Café;-1,50\n02/10/2026;Nómina;100,00")
        let mapping = try XCTUnwrap(CSVMapping.detect(in: table))
        let drafts = CSVImporter.rows(in: table, mapping: mapping, accountId: account.id).compactMap(\.draft)

        let first = try await backend.importMovements(drafts, in: home.id)
        XCTAssertEqual(first, ImportResult(inserted: 2, duplicates: 0))
        let second = try await backend.importMovements(drafts, in: home.id)
        XCTAssertEqual(second, ImportResult(inserted: 0, duplicates: 2))

        let balances = try await backend.balances(in: home.id)
        XCTAssertEqual(balances[account.id]?.minor, 9850)
    }
}
