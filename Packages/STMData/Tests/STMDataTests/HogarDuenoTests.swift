import XCTest
import STMCore
@testable import STMData

/// ORC-148: un cambio del hogar sin fila de vuelta no era del dueño (RLS). Renombrar y cambiar el día de inicio
/// dan el mismo mensaje, en vez de «Algo ha fallado».
final class HogarDuenoTests: XCTestCase {
    func testSinFilaEsSoloDuenoAlRenombrarComoAlCambiarElDia() throws {
        XCTAssertThrowsError(try SupabaseBackend.changedHousehold([], ownerOnly: Household.monthStartDayOwnerOnly)) { error in
            XCTAssertEqual(error as? AppError, .invalidInput(Household.monthStartDayOwnerOnly))
        }
    }

    func testConFilaDevuelveElHogarActualizado() throws {
        let home = Household(name: "Piso nuevo")
        XCTAssertEqual(try SupabaseBackend.changedHousehold([home], ownerOnly: Household.monthStartDayOwnerOnly), home)
    }
}
