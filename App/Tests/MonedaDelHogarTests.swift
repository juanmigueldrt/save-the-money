import XCTest
import STMCore
@testable import STMData

/// ORC-71: el servidor no deja cambiar la moneda de un hogar con importes (STM06) y la app lo explica.
final class MonedaDelHogarTests: XCTestCase {
    func testMonedaBloqueadaTieneSuMensaje() {
        let error = SupabaseBackend.appError(postgresCode: "STM06",
                                             message: "La moneda del hogar no se puede cambiar con importes guardados")
        XCTAssertEqual(error, .invalidInput(Household.currencyLocked))
        XCTAssertEqual(error.errorDescription,
                       "No se puede cambiar la moneda del hogar mientras tenga cuentas, presupuestos u otros importes guardados.")
    }
}
