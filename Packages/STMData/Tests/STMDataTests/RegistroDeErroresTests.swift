import XCTest
import STMCore
import Supabase
@testable import STMData

/// ORC-72: la línea del registro lleva la operación, el tipo, el código y el estado HTTP, y nada más. Los errores de
/// estas pruebas llevan datos personales inventados en el mensaje, el cuerpo o el valor: ninguno puede salir.
final class RegistroDeErroresTests: XCTestCase {
    private let personales = ["Carmen", "López", "1234,56", "regalo", "carmen@example.com", "K7Q2-9XPA", "eyJhbGci"]

    private func sinDatosPersonales(_ line: String, file: StaticString = #filePath, lineNumber: UInt = #line) {
        for dato in personales {
            XCTAssertFalse(line.contains(dato), "«\(dato)» ha salido en: \(line)", file: file, line: lineNumber)
        }
    }

    private func respuesta(_ status: Int) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(url: URL(fileURLWithPath: "/"), statusCode: status, httpVersion: nil, headerFields: nil))
    }

    func testPostgresDesconocidoGuardaCodigoYTipoSinElMensaje() {
        let error = PostgrestError(
            details: "Failing row contains (Carmen López, 1234,56, regalo, carmen@example.com).",
            hint: "K7Q2-9XPA", code: "XX000", message: "nota «regalo» de Carmen López por 1234,56"
        )
        let line = ErrorLog.line(operation: "createMovement(_:in:)", error: error)
        XCTAssertEqual(line, "operacion=createMovement(_:in:) tipo=PostgrestError codigo=XX000")
        sinDatosPersonales(line)
        // Lo que ve el usuario sigue siendo el aviso genérico, con el código para el registro.
        XCTAssertEqual(SupabaseBackend.appError(postgresCode: error.code, message: error.message), .unknown("XX000"))
    }

    func testAuthGuardaCodigoYEstadoSinElCuerpo() throws {
        let error = AuthError.api(
            message: "User carmen@example.com not allowed", errorCode: ErrorCode("invalid_credentials"),
            underlyingData: Data(#"{"email":"carmen@example.com","access_token":"eyJhbGci"}"#.utf8),
            underlyingResponse: try respuesta(400)
        )
        let line = ErrorLog.line(operation: "signIn(username:password:)", error: error)
        XCTAssertEqual(line, "operacion=signIn(username:password:) tipo=AuthError codigo=invalid_credentials http=400")
        sinDatosPersonales(line)
    }

    func testHTTPGuardaSoloElEstado() throws {
        let error = HTTPError(data: Data("Carmen López 1234,56".utf8), response: try respuesta(503))
        let line = ErrorLog.line(operation: "accounts(in:)", error: error)
        XCTAssertEqual(line, "operacion=accounts(in:) tipo=HTTPError http=503")
        sinDatosPersonales(line)
    }

    func testRedGuardaElCodigoDeURLError() {
        let error = URLError(.notConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: "Carmen López"])
        XCTAssertEqual(
            ErrorLog.line(operation: "households()", error: error),
            "operacion=households() tipo=URLError codigo=-1009"
        )
    }

    func testAppErrorSoloLaEtiquetaDelCaso() {
        let validacion = ErrorLog.line(operation: "op", error: AppError.invalidInput("Carmen López debe 1234,56"))
        XCTAssertEqual(validacion, "operacion=op tipo=AppError.invalidInput")
        sinDatosPersonales(validacion)
        XCTAssertEqual(ErrorLog.line(operation: "op", error: AppError.network), "operacion=op tipo=AppError.network")
        XCTAssertEqual(
            ErrorLog.line(operation: "op", error: AppError.unknown("create_movement")),
            "operacion=op tipo=AppError.unknown codigo=create_movement"
        )
    }

    func testErrorCualquieraSoloElTipo() {
        struct FalloDePrueba: Error { let nota = "regalo para Carmen López, 1234,56" }
        let nsError = NSError(domain: "prueba", code: 7, userInfo: [NSLocalizedDescriptionKey: "Carmen López"])
        XCTAssertEqual(ErrorLog.line(operation: "op", error: FalloDePrueba()), "operacion=op tipo=FalloDePrueba")
        XCTAssertEqual(ErrorLog.line(operation: "op", error: nsError), "operacion=op tipo=NSError")
    }

    func testUnCodigoConTextoNoPasaEntero() {
        let error = PostgrestError(code: "XX000 Carmen López 1234,56 regalo carmen@example.com K7Q2-9XPA", message: "")
        let line = ErrorLog.line(operation: "op", error: error)
        XCTAssertEqual(line, "operacion=op tipo=PostgrestError codigo=no_valido")
        sinDatosPersonales(line)
    }
}
