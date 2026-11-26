import XCTest
@testable import STMCore

/// ORC-85: la lista de movimientos va por páginas (día y luego id, de mayor a menor) y busca en el servidor.
/// Con el servicio en memoria, que sigue las mismas reglas. Datos inventados.
final class ListaPaginadaTests: XCTestCase {
    private struct Home {
        let backend: InMemoryBackend
        let id: UUID
        let account: Account
        let other: Account
    }

    private func home() async throws -> Home {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        let home = try await backend.createHousehold(name: "Casa de prueba")
        let account = try await backend.createAccount(AccountDraft(name: "Corriente"), in: home.id)
        let other = try await backend.createAccount(AccountDraft(name: "Ahorro"), in: home.id)
        return Home(backend: backend, id: home.id, account: account, other: other)
    }

    private func uuid(_ last: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", last))!
    }

    // MARK: MovementSearch

    func testBusquedaQuitaEspaciosYControlesYSeRecortaA100() throws {
        XCTAssertNil(MovementSearch("   \n\t ", categories: []))
        XCTAssertNil(MovementSearch("\u{0}\u{7}", categories: []))
        XCTAssertEqual(MovementSearch("  \u{0}café\n ", categories: [])?.text, "café")
        let larga = String(repeating: "a", count: 150)
        XCTAssertEqual(MovementSearch(larga, categories: [])?.text, String(repeating: "a", count: 100))
        // Se cuentan caracteres Unicode, no bytes: 100 «ñ» se quedan enteras.
        XCTAssertEqual(MovementSearch(String(repeating: "ñ", count: 120), categories: [])?.text.unicodeScalars.count, 100)
    }

    func testBusquedaReconoceEtiquetaImporteYCategoria() throws {
        let household = UUID()
        let comida = BudgetCategory(householdId: household, name: "Comida")
        let ocio = BudgetCategory(householdId: household, name: "Ocio")

        let etiqueta = try XCTUnwrap(MovementSearch("#Viaje", categories: [comida, ocio]))
        XCTAssertEqual(etiqueta.tag, "viaje")
        XCTAssertNil(etiqueta.amount)
        XCTAssertEqual(etiqueta.categoryIds, [])

        let categoria = try XCTUnwrap(MovementSearch("comi", categories: [comida, ocio]))
        XCTAssertEqual(categoria.categoryIds, [comida.id])

        let importe = try XCTUnwrap(MovementSearch("12,50", categories: []))
        XCTAssertEqual(importe.amount?.minor, 1_250)
        XCTAssertFalse(importe.signedAmount)
        XCTAssertNil(importe.tag, "«12,50» no es una etiqueta: lleva una coma")

        let gasto = try XCTUnwrap(MovementSearch("-12,50", categories: []))
        XCTAssertEqual(gasto.amount?.minor, -1_250)
        XCTAssertTrue(gasto.signedAmount)

        // Los caracteres con sentido en LIKE o en PostgREST no hacen etiqueta ni importe: se buscan como texto.
        let raro = try XCTUnwrap(MovementSearch(#"50%_a\b"c,(d).e*f:g"#, categories: []))
        XCTAssertEqual(raro.text, #"50%_a\b"c,(d).e*f:g"#)
        XCTAssertNil(raro.tag)
        XCTAssertNil(raro.amount)
    }

    func testBusquedaEncuentraPorTextoEtiquetaCategoriaEImporte() throws {
        let household = UUID(), account = UUID()
        let comida = BudgetCategory(householdId: household, name: "Comida")
        func movement(_ description: String, minor: Int = -100, payee: String? = nil, notes: String? = nil,
                      tags: [String] = [], categoryId: UUID? = nil) -> Movement {
            Movement(householdId: household, accountId: account, categoryId: categoryId, bookedOn: CalendarDay(),
                     amount: Money(minor: minor), description: description, notes: notes, payee: payee, tags: tags)
        }
        let buscar = { (text: String) in try XCTUnwrap(MovementSearch(text, categories: [comida])) }

        XCTAssertTrue(try buscar("50%").matches(movement("Descuento 50% hoy")))
        XCTAssertFalse(try buscar("50%").matches(movement("Descuento 500 hoy")), "el % es un carácter, no un comodín")
        XCTAssertTrue(try buscar("mercado").matches(movement("x", payee: "Mercado central")))
        XCTAssertTrue(try buscar("regalo").matches(movement("x", notes: "Regalo de cumple")))
        XCTAssertTrue(try buscar("#viaje").matches(movement("x", tags: ["viaje"])))
        XCTAssertFalse(try buscar("#via").matches(movement("x", tags: ["viaje"])), "la etiqueta tiene que ser esa entera")
        XCTAssertTrue(try buscar("comida").matches(movement("x", categoryId: comida.id)))
        XCTAssertTrue(try buscar("12,50").matches(movement("x", minor: 1_250)))
        XCTAssertTrue(try buscar("12,50").matches(movement("x", minor: -1_250)))
        XCTAssertFalse(try buscar("-12,50").matches(movement("x", minor: 1_250)), "con signo, sólo gastos")
    }

    // MARK: Páginas en memoria

    func testLasPaginasSiguenElOrdenYNoRepitenNiSaltan() async throws {
        let home = try await home()
        let day1 = CalendarDay(year: 2020, month: 1, day: 1)!
        let day2 = CalendarDay(year: 2020, month: 1, day: 2)!
        // Cinco el mismo día (desempata el id) y dos el día siguiente.
        for (index, day) in [(1, day1), (2, day1), (3, day1), (4, day1), (5, day1), (6, day2), (7, day2)] {
            _ = try await home.backend.addMovement(MovementDraft(id: uuid(index), accountId: home.account.id, bookedOn: day,
                                                                 amount: Money(minor: -100), description: "Gasto \(index)"),
                                                   in: home.id)
        }
        var seen: [UUID] = []
        var after: Movement?
        while true {
            let page = try await home.backend.movements(in: home.id, accountId: nil, search: nil, after: after, limit: 3)
            seen += page.map(\.id)
            guard page.count == 3 else { break }
            after = page.last
        }
        XCTAssertEqual(seen, [7, 6, 5, 4, 3, 2, 1].map(uuid))
    }

    func testFiltraPorCuentaYBusqueda() async throws {
        let home = try await home()
        let day = CalendarDay(year: 2020, month: 1, day: 1)!
        _ = try await home.backend.addMovement(MovementDraft(accountId: home.account.id, bookedOn: day, amount: Money(minor: -100),
                                                             description: "Panadería"), in: home.id)
        _ = try await home.backend.addMovement(MovementDraft(accountId: home.other.id, bookedOn: day, amount: Money(minor: -100),
                                                             description: "Panadería"), in: home.id)
        _ = try await home.backend.addMovement(MovementDraft(accountId: home.account.id, bookedOn: day, amount: Money(minor: -100),
                                                             description: "Gasolina"), in: home.id)
        let search = MovementSearch("pan", categories: [])
        let all = try await home.backend.movements(in: home.id, accountId: nil, search: search, after: nil, limit: 10)
        XCTAssertEqual(all.count, 2)
        let mine = try await home.backend.movements(in: home.id, accountId: home.account.id, search: search, after: nil, limit: 10)
        XCTAssertEqual(mine.map(\.accountId), [home.account.id])
    }
}
