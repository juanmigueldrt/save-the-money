import XCTest
import STMCore
@testable import STMData

/// Un 23505 sólo es «nombre de usuario en uso» si la restricción es la de profiles.username.
final class ErroresDuplicadosTests: XCTestCase {
    private let generico = AppError.invalidInput("Ya hay un registro igual guardado. Revisa el formulario.")

    private func error(_ message: String) -> AppError {
        SupabaseBackend.appError(postgresCode: "23505", message: message)
    }

    func testNombreDeUsuarioRepetidoDiceNombreEnUso() {
        XCTAssertEqual(error("duplicate key value violates unique constraint \"profiles_username_key\""), .usernameTaken)
    }

    func testCategoriaRepetidaTieneSuMensaje() {
        XCTAssertEqual(
            error("duplicate key value violates unique constraint \"categories_household_name_idx\""),
            .invalidInput("Ya hay una categoría con ese nombre.")
        )
    }

    func testYaEresMiembroDeLHogar() {
        XCTAssertEqual(error("already a member"), .alreadyMember)
    }

    func testCuotaDeTarjetaRepetidaNoDiceNombreDeUsuario() {
        XCTAssertEqual(error("duplicate key value violates unique constraint \"card_installments_transaction_id_key\""), generico)
    }

    func testPrecioDeUnDiaRepetidoNoDiceNombreDeUsuario() {
        XCTAssertEqual(error("duplicate key value violates unique constraint \"holding_prices_holding_id_priced_on_key\""), generico)
    }

    func testPresupuestoDelMesRepetidoNoDiceNombreDeUsuario() {
        XCTAssertEqual(error("duplicate key value violates unique constraint \"budgets_household_creator_month_key\""), generico)
    }

    func testDuplicadoSinNombreDeRestriccionEsGenerico() {
        XCTAssertEqual(error("duplicate key value violates unique constraint"), generico)
    }
}
