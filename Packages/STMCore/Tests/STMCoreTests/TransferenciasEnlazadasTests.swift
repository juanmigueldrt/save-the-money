import XCTest
@testable import STMCore

/// Una transferencia es una sola operación: sus dos patas se cambian y se borran juntas, y no cuentan como
/// gasto ni como ingreso. Con el servicio en memoria, que hace lo mismo que el servidor. Datos inventados.
final class TransferenciasEnlazadasTests: XCTestCase {
    private struct Home {
        let backend: InMemoryBackend
        let id: UUID
        let checking: Account
        let savings: Account
        let categories: [BudgetCategory]
    }

    private let day = CalendarDay(year: 2026, month: 11, day: 4)!

    private func home() async throws -> Home {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        let home = try await backend.createHousehold(name: "Casa de prueba")
        let checking = try await backend.createAccount(AccountDraft(name: "Corriente", openingBalance: Money(minor: 100_000)), in: home.id)
        let savings = try await backend.createAccount(AccountDraft(name: "Ahorro"), in: home.id)
        let categories = try await backend.categories(in: home.id)
        return Home(backend: backend, id: home.id, checking: checking, savings: savings, categories: categories)
    }

    /// 300,00 € de la corriente al ahorro, con la categoría de transferencia.
    private func transfer(_ home: Home, id: UUID = UUID()) async throws -> [Movement] {
        let category = home.categories.first { $0.kind == .transfer }
        XCTAssertNotNil(category, "las categorías de partida traen una de transferencia")
        let draft = TransferDraft(id: id, fromAccountId: home.checking.id, toAccountId: home.savings.id, categoryId: category?.id,
                                  bookedOn: day, amount: Money(minor: 30_000), fromDescription: "Al ahorro", toDescription: "Al ahorro")
        return try await home.backend.addTransfer(draft, in: home.id)
    }

    private func all(_ home: Home) async throws -> [Movement] {
        try await home.backend.movements(in: home.id, accountId: nil, limit: 50)
    }

    func testLasDosPatasLlevanElIdDeLaTransferencia() async throws {
        let home = try await home()
        let id = UUID()
        let legs = try await transfer(home, id: id)
        XCTAssertEqual(legs.map(\.transferId), [id, id])
        let stored = try await all(home)
        XCTAssertEqual(stored.map(\.transferId), [id, id], "también al leerlas")
    }

    func testCambiarImporteYDiaDeUnaPataCambiaLaOtra() async throws {
        let home = try await home()
        let legs = try await transfer(home)
        let newDay = CalendarDay(year: 2026, month: 11, day: 6)!
        var incoming = legs[1]
        incoming.amount = Money(minor: 25_000)
        incoming.bookedOn = newDay
        incoming.notes = "Solo en la entrada"
        _ = try await home.backend.updateMovement(incoming)

        let stored = try await all(home)
        let out = try XCTUnwrap(stored.first { $0.id == legs[0].id })
        XCTAssertEqual(out.amount, Money(minor: -25_000), "la salida baja igual")
        XCTAssertEqual(out.bookedOn, newDay)
        XCTAssertNil(out.notes, "lo demás de la otra pata no se toca")
        XCTAssertNotEqual(out.updatedAt, legs[0].updatedAt, "la otra pata tiene versión nueva")
        let balances = try await home.backend.balances(in: home.id)
        XCTAssertEqual(balances[home.checking.id], Money(minor: 75_000))
        XCTAssertEqual(balances[home.savings.id], Money(minor: 25_000))

        // Quien tenía la versión vieja de la salida no la pisa.
        var stale = legs[0]
        stale.amount = Money(minor: -1_000)
        do {
            _ = try await home.backend.updateMovement(stale)
            XCTFail("tenía que fallar")
        } catch {
            XCTAssertEqual(error as? AppError, .movementChanged)
        }
    }

    func testUnaPataNoCambiaDeSignoNiSeVaALaCuentaDeLaOtra() async throws {
        let home = try await home()
        let legs = try await transfer(home)
        var flipped = legs[0]
        flipped.amount = Money(minor: 30_000)
        var sameAccount = legs[1]
        sameAccount.accountId = home.checking.id
        for change in [flipped, sameAccount] {
            do {
                _ = try await home.backend.updateMovement(change)
                XCTFail("tenía que fallar")
            } catch {
                guard case .invalidInput = error as? AppError else { return XCTFail("\(error)") }
            }
        }
        let stored = try await all(home)
        XCTAssertEqual(Set(stored.map(\.amount)), [Money(minor: -30_000), Money(minor: 30_000)], "no cambia nada")
        XCTAssertEqual(Set(stored.map(\.accountId)), [home.checking.id, home.savings.id])
    }

    func testBorrarLaTransferenciaBorraLasDosPatas() async throws {
        let home = try await home()
        let legs = try await transfer(home)
        let other = try await home.backend.addMovement(MovementDraft(accountId: home.checking.id, bookedOn: day,
                                                                     amount: Money(minor: -1_000), description: "Café"), in: home.id)
        try await home.backend.deleteTransfer(try XCTUnwrap(legs[0].transferId))
        let stored1 = try await all(home)
        XCTAssertEqual(stored1.map(\.id), [other.id], "solo queda el movimiento que no es de la transferencia")
        let balances = try await home.backend.balances(in: home.id)
        XCTAssertEqual(balances[home.checking.id], Money(minor: 99_000))
        XCTAssertEqual(balances[home.savings.id], .zero)

        // Repetir la petición (por ejemplo tras un corte de red) no falla ni borra nada más.
        try await home.backend.deleteTransfer(try XCTUnwrap(legs[0].transferId))
        let stored2 = try await all(home)
        XCTAssertEqual(stored2.map(\.id), [other.id])
    }

    func testSiFallaNoSeBorraNinguna() async throws {
        let home = try await home()
        let legs = try await transfer(home)
        await home.backend.failCalls("deleteTransfer(_:)")
        do {
            try await home.backend.deleteTransfer(try XCTUnwrap(legs[0].transferId))
            XCTFail("tenía que fallar")
        } catch {
            XCTAssertEqual(error as? AppError, .network)
        }
        await home.backend.clearFailures()
        let stored3 = try await all(home)
        XCTAssertEqual(stored3.count, 2)
    }

    func testSiLaOtraPataYaNoExisteLaQueQuedaEsUnMovimientoNormal() async throws {
        let home = try await home()
        let legs = try await transfer(home)
        // Por ejemplo, la borró una versión anterior de la app.
        try await home.backend.deleteMovement(legs[1].id)
        var left = legs[0]
        left.amount = Money(minor: -20_000)
        let saved = try await home.backend.updateMovement(left)
        XCTAssertEqual(saved.amount, Money(minor: -20_000))
        try await home.backend.deleteTransfer(try XCTUnwrap(legs[0].transferId))
        let stored4 = try await all(home)
        XCTAssertTrue(stored4.isEmpty)
    }

    func testLasTransferenciasNoCuentanComoGastoNiIngreso() async throws {
        let home = try await home()
        let salary = try XCTUnwrap(home.categories.first { $0.kind == .income })
        _ = try await home.backend.addMovement(MovementDraft(accountId: home.checking.id, categoryId: salary.id, bookedOn: day,
                                                             amount: Money(minor: 200_000), description: "Nómina"), in: home.id)
        _ = try await transfer(home)
        let movements = try await all(home)
        let month = MonthKey(year: 2026, month: 11)

        let report = BudgetReport(budget: nil, month: month, categories: home.categories, movements: movements)
        XCTAssertEqual(report.income.minor, 200_000, "solo la nómina")
        XCTAssertEqual(report.totalSpent.minor, 0)
        XCTAssertEqual(report.uncategorized.minor, 0)

        let days = MovementDay.group(movements, categories: home.categories)
        XCTAssertEqual(days.map(\.total.minor), [200_000], "el día suma solo la nómina")

        XCTAssertTrue(WeeklySummary.expenses(movements: movements, categories: home.categories).isEmpty)
    }
}
