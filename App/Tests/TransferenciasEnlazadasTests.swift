import XCTest
import STMCore
@testable import SaveTheMoney

/// ORC-75: desde la app, una transferencia se cambia y se borra como una sola operación. Datos inventados.
@MainActor
final class TransferenciasEnlazadasAppTests: XCTestCase {
    private let hoy = CalendarDay(year: 2026, month: 11, day: 5) ?? CalendarDay()

    private struct Hogar {
        let finance: FinanceModel
        let corriente: Account
        let ahorro: Account
    }

    /// Ana con una corriente de 1.000,00 €, un ahorro y 300,00 € pasados de una a otra.
    private func hogar() async throws -> Hogar {
        let services = AppServices.demo()
        let session = SessionModel(services: services)
        try await session.signUp(SignUpForm(username: "ana", password: "contrasena-de-prueba", passwordConfirmation: "contrasena-de-prueba"))
        try await session.createHousehold(name: "Casa de prueba")
        guard case .ready(_, let home) = session.state else { throw AppError.unknown("sin hogar") }
        let finance = FinanceModel(household: home, service: services.finance)
        _ = await finance.createAccount(AccountDraft(name: "Corriente", openingBalance: Money(minor: 100_000)))
        _ = await finance.createAccount(AccountDraft(name: "Ahorro"))
        let corriente = try XCTUnwrap(finance.activeAccounts.first { $0.name == "Corriente" })
        let ahorro = try XCTUnwrap(finance.activeAccounts.first { $0.name == "Ahorro" })
        let hecha = await finance.transfer(from: corriente, to: ahorro, amount: Money(minor: 30_000), on: hoy, description: "Al ahorro")
        XCTAssertTrue(hecha)
        return Hogar(finance: finance, corriente: corriente, ahorro: ahorro)
    }

    func testBorrarUnaPataBorraLasDosYNoOfreceDeshacer() async throws {
        let hogar = try await hogar()
        let (finance, corriente, ahorro) = (hogar.finance, hogar.corriente, hogar.ahorro)
        let entrada = try XCTUnwrap(finance.recent.first { !$0.isExpense })
        let borrada = await finance.delete(entrada)
        XCTAssertTrue(borrada)
        XCTAssertTrue(finance.recent.isEmpty, "se van las dos patas")
        XCTAssertEqual(finance.balance(of: corriente), Money(minor: 100_000))
        XCTAssertEqual(finance.balance(of: ahorro), .zero)
        XCTAssertNil(finance.lastDeleted, "deshacer volvería a apuntar solo una pata")
    }

    func testBorrarLasDosPatasElegidasNoFalla() async throws {
        let hogar = try await hogar()
        let (finance, corriente) = (hogar.finance, hogar.corriente)
        let borradas = await finance.delete(finance.recent)
        XCTAssertTrue(borradas)
        XCTAssertNil(finance.error)
        XCTAssertTrue(finance.recent.isEmpty)
        XCTAssertEqual(finance.balance(of: corriente), Money(minor: 100_000))
    }

    func testCambiarUnaPataCambiaLaOtra() async throws {
        let hogar = try await hogar()
        let (finance, corriente, ahorro) = (hogar.finance, hogar.corriente, hogar.ahorro)
        var salida = try XCTUnwrap(finance.recent.first { $0.isExpense })
        salida.amount = Money(minor: -25_000)
        let guardada = await finance.update(salida)
        XCTAssertTrue(guardada)
        XCTAssertEqual(finance.recent.map(\.amount.minor).sorted(), [-25_000, 25_000])
        XCTAssertEqual(finance.balance(of: corriente), Money(minor: 75_000))
        XCTAssertEqual(finance.balance(of: ahorro), Money(minor: 25_000))
    }

    func testCambiarLaFechaDeLasDosPatasALaVezNoFalla() async throws {
        let finance = try await hogar().finance
        let otroDia = hoy.adding(days: 2)
        let guardadas = await finance.update(MovementBulkEdit(bookedOn: otroDia).changes(for: finance.recent))
        XCTAssertTrue(guardadas, finance.error ?? "")
        XCTAssertEqual(Set(finance.recent.map(\.bookedOn)), [otroDia])
    }
}
