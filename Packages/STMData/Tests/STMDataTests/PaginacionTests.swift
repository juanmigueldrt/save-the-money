import XCTest
@testable import STMData

/// ORC-65: el servidor devuelve como mucho 1000 filas por petición; las listas se piden por páginas
/// y una página fallida hace fallar la carga entera.
final class PaginacionTests: XCTestCase {
    private struct FalloDePagina: Error {}

    /// Páginas falsas con los tamaños dados; anota los rangos pedidos.
    private final class Paginas: @unchecked Sendable {
        var tamanos: [Int]
        var pedidas: [ClosedRange<Int>] = []
        var fallaEn: Int?

        init(_ tamanos: [Int], fallaEn: Int? = nil) {
            self.tamanos = tamanos
            self.fallaEn = fallaEn
        }

        func pagina(desde: Int, hasta: Int) throws -> [Int] {
            pedidas.append(desde...hasta)
            if pedidas.count == fallaEn { throw FalloDePagina() }
            let tamano = pedidas.count <= tamanos.count ? tamanos[pedidas.count - 1] : 0
            return Array(desde..<(desde + tamano))
        }
    }

    func testJuntaTodasLasPaginasHastaUnaIncompleta() async throws {
        let paginas = Paginas([1000, 1000, 37])
        let filas = try await SupabaseBackend.allPages { try paginas.pagina(desde: $0, hasta: $1) }
        XCTAssertEqual(filas, Array(0..<2037))
        XCTAssertEqual(paginas.pedidas, [0...999, 1000...1999, 2000...2999])
    }

    func testExactamenteMilFilasPideUnaPaginaMasVacia() async throws {
        let paginas = Paginas([1000])
        let filas = try await SupabaseBackend.allPages { try paginas.pagina(desde: $0, hasta: $1) }
        XCTAssertEqual(filas, Array(0..<1000))
        XCTAssertEqual(paginas.pedidas, [0...999, 1000...1999])
    }

    func testSinFilasDevuelveListaVacia() async throws {
        let paginas = Paginas([])
        let filas = try await SupabaseBackend.allPages { try paginas.pagina(desde: $0, hasta: $1) }
        XCTAssertEqual(filas, [])
        XCTAssertEqual(paginas.pedidas, [0...999])
    }

    func testUnFalloEnLaSegundaPaginaFallaLaCargaEntera() async {
        let paginas = Paginas([1000, 1000, 37], fallaEn: 2)
        do {
            let filas = try await SupabaseBackend.allPages { try paginas.pagina(desde: $0, hasta: $1) }
            XCTFail("Devolvió \(filas.count) filas en vez de fallar")
        } catch {
            XCTAssertTrue(error is FalloDePagina)
        }
        XCTAssertEqual(paginas.pedidas.count, 2)
    }
}
