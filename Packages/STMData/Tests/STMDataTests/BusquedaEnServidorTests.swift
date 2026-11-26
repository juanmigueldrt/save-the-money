import XCTest
import STMCore
@testable import STMData

/// ORC-85: la búsqueda de la lista va al servidor como filtro `or=(…)` de PostgREST. El texto del usuario va entre
/// comillas y con los comodines de LIKE escapados, para que nada de lo que escriba se lea como sintaxis.
/// Los resultados esperados están escritos a mano a partir de la gramática de PostgREST, no copiados de la salida.
final class BusquedaEnServidorTests: XCTestCase {
    private func filtro(_ text: String, categories: [BudgetCategory] = []) throws -> String {
        SupabaseBackend.searchFilter(try XCTUnwrap(MovementSearch(text, categories: categories)))
    }

    func testCaracteresDeLikeYDePostgrestVanEscapados() throws {
        // 50 % _ a \ b " c , ( d ) . e * f : g
        // LIKE:      50\%\_a\\b"c,(d).e_f:g      (el * pasa a _: PostgREST no deja escaparlo)
        // Comillas:  cada \ pasa a \\ y cada " a \"
        let valor = #""*50\\%\\_a\\\\b\"c,(d).e_f:g*""#
        XCTAssertEqual(try filtro(#"50%_a\b"c,(d).e*f:g"#),
                       "description.ilike.\(valor),notes.ilike.\(valor),payee.ilike.\(valor)")
    }

    func testSoloComillasYBarras() throws {
        // \"  →  LIKE \\"  →  entre comillas \\\\\"
        let valor = #""*\\\\\"*""#
        XCTAssertEqual(try filtro(#"\""#), "description.ilike.\(valor),notes.ilike.\(valor),payee.ilike.\(valor)")
    }

    func testParentesisYComasNoCierranElFiltro() throws {
        let valor = #""*a),or(id.neq.0*""#
        XCTAssertEqual(try filtro("a),or(id.neq.0"), "description.ilike.\(valor),notes.ilike.\(valor),payee.ilike.\(valor)")
    }

    func testEspaciosAlosLadosNoSeBuscan() throws {
        let valor = #""*pan*""#
        XCTAssertEqual(try filtro("   pan \n"), "description.ilike.\(valor),notes.ilike.\(valor),payee.ilike.\(valor),tags.cs.{pan}")
    }

    func testEtiquetaCategoriaEImporte() throws {
        let household = UUID()
        let comida = BudgetCategory(id: UUID(uuidString: "0000000A-0000-0000-0000-0000000000C1")!, householdId: household, name: "Comida")
        let etiqueta = #""*#Viaje*""#
        XCTAssertEqual(try filtro("#Viaje", categories: [comida]),
                       "description.ilike.\(etiqueta),notes.ilike.\(etiqueta),payee.ilike.\(etiqueta),tags.cs.{viaje}")
        let categoria = #""*comi*""#
        XCTAssertEqual(try filtro("comi", categories: [comida]),
                       "description.ilike.\(categoria),notes.ilike.\(categoria),payee.ilike.\(categoria),tags.cs.{comi},"
                       + "category_id.in.(0000000a-0000-0000-0000-0000000000c1)")
        let importe = #""*12,50*""#
        XCTAssertEqual(try filtro("12,50"),
                       "description.ilike.\(importe),notes.ilike.\(importe),payee.ilike.\(importe),amount_minor.in.(1250,-1250)")
        let gasto = #""*-12,50*""#
        XCTAssertEqual(try filtro("-12,50"),
                       "description.ilike.\(gasto),notes.ilike.\(gasto),payee.ilike.\(gasto),amount_minor.eq.-1250")
    }

    /// ORC-146: las mismas cadenas que el CI manda al Supabase local (supabase/tests/api/filtros_postgrest.py).
    func testFiltrosCompartidosConAndroidYConElServidor() throws {
        struct File: Decodable { var search: [Search]; var movements: [Fila] }
        struct Search: Decodable { var name: String; var input: String; var filter: String }
        struct Fila: Decodable { var key: String; var id: UUID; var bookedOn: String; var cursor: String }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("testdata/vectors/postgrest_filters.json")
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        XCTAssertFalse(file.search.isEmpty)
        XCTAssertFalse(file.movements.isEmpty)
        for vector in file.search {
            XCTAssertEqual(try filtro(vector.input), vector.filter, vector.name)
        }
        for fila in file.movements {
            let movement = Movement(id: fila.id, householdId: UUID(), accountId: UUID(),
                                    bookedOn: try XCTUnwrap(CalendarDay(iso: fila.bookedOn)), amount: Money(minor: -1), description: "x")
            XCTAssertEqual(SupabaseBackend.afterFilter(movement), fila.cursor, fila.key)
        }
    }

    func testCursorEsDiaAnteriorOMismoDiaYMenorId() throws {
        let movement = Movement(id: UUID(uuidString: "ABCDEF00-0000-0000-0000-000000000001")!, householdId: UUID(), accountId: UUID(),
                                bookedOn: CalendarDay(year: 2021, month: 3, day: 5)!, amount: Money(minor: -1), description: "x")
        XCTAssertEqual(SupabaseBackend.afterFilter(movement),
                       "booked_on.lt.2021-03-05,and(booked_on.eq.2021-03-05,id.lt.abcdef00-0000-0000-0000-000000000001)")
    }
}
