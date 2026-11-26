import XCTest
import STMCore
@testable import STMData
@testable import SaveTheMoney

/// ORC-103: el texto de cada problema de validación, tal cual lo ve el usuario. Los literales se copiaron del código
/// antes de mover los textos a la app: si alguno cambia, el usuario vería otra cosa.
final class TextosDeValidacionTests: XCTestCase {
    private let home = UUID()
    private let account = UUID()
    private let before = CalendarDay(year: 2026, month: 5, day: 1)!
    private let day = CalendarDay(year: 2026, month: 6, day: 1)!
    private let long60 = String(repeating: "a", count: 61)
    private let long200 = String(repeating: "a", count: 201)

    private func pin(_ actual: String?, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    func testPeriodoDeCobro() {
        pin(PaySchedule(day1: 0).issue?.text, "El día de cobro tiene que estar entre 1 y 31.")
        pin(PaySchedule(frequency: .twiceMonthly, day1: 15, day2: 1).issue?.text, "El segundo día de cobro tiene que ir después del primero.")
        pin(PaySchedule(frequency: .weekly).issue?.text, "Elige un día en que hayas cobrado.")
    }

    func testPresupuestoAparte() {
        func extra(_ name: String = "X", limit: Int = 100, endsOn: CalendarDay? = nil, categories: Int = 0) -> ExtraBudget {
            ExtraBudget(householdId: home, name: name, limit: Money(minor: limit), startsOn: day, endsOn: endsOn,
                        categoryIds: (0..<categories).map { _ in UUID() })
        }
        pin(extra("  ").issue?.text, "Ponle un nombre.")
        pin(extra(long60).issue?.text, "El nombre es demasiado largo (máximo 60 caracteres).")
        pin(extra(limit: 0).issue?.text, "El límite tiene que ser mayor que cero.")
        pin(extra(endsOn: before).issue?.text, "La fecha de fin no puede ser anterior a la de inicio.")
        pin(extra(categories: 51).issue?.text, "Demasiadas categorías o cuentas.")
    }

    func testPresupuesto() {
        let period = BudgetPeriod(month: MonthKey(year: 2026, month: 6))
        pin(Budget(householdId: home, period: period, expectedIncome: Money(minor: -1)).issue?.text,
            "Los ingresos previstos no pueden ser negativos.")
        pin(Budget(householdId: home, period: period, limits: [UUID(): Money(minor: -1)]).issue?.text, "Los límites no pueden ser negativos.")
        pin(Budget(householdId: home, period: period, warnPercent: 40).issue?.text, "El aviso tiene que estar entre el 50 % y el 100 %.")
    }

    func testFilasDelCSV() {
        let table = CSVTable(rows: [["32/13/2026", "x", "1,00", ""], ["01/06/2026", "x", "1,00", "2,00"], ["01/06/2026", "x", "", ""]],
                             delimiter: ";")
        let mapping = CSVMapping(headerRow: nil, date: 0, description: 1, amount: .split(debit: 2, credit: 3))
        let rows = CSVImporter.rows(in: table, mapping: mapping, accountId: account)
        XCTAssertEqual(rows.count, 3)
        pin(rows[0].issue?.text, "Fecha no reconocida: «32/13/2026»")
        pin(rows[1].issue?.text, "Tiene cargo y abono a la vez")
        pin(rows[2].issue?.text, "Importe vacío o no válido")
    }

    func testCondicionesDeTarjeta() {
        func terms(_ change: (inout CreditCardTerms) -> Void) -> CreditCardTerms {
            var terms = CreditCardTerms(accountId: account, householdId: home, creditLimit: Money(minor: 100_000))
            change(&terms)
            return terms
        }
        XCTAssertNil(terms { _ in }.issue)
        pin(terms { $0.creditLimit = .zero }.issue?.text, "El límite tiene que ser mayor que cero.")
        pin(terms { $0.statementDay = 29 }.issue?.text, "El día del extracto va del 1 al 28.")
        pin(terms { $0.paymentDay = 29 }.issue?.text, "El día del cargo va del 1 al 28.")
        pin(terms { $0.paymentDelayMonths = 3 }.issue?.text, "El cargo puede ser el mismo mes del extracto o hasta dos meses después.")
        pin(terms { $0.paymentMode = .fixed }.issue?.text, "Indica la cuota fija que pagas cada mes.")
        pin(terms { $0.fixedPayment = Money(minor: -1) }.issue?.text, "La cuota fija tiene que ser mayor que cero.")
        pin(terms { $0.minPaymentPercent = 101 }.issue?.text, "El % del pago mínimo va de 0 a 100.")
        pin(terms { $0.minPayment = Money(minor: -1) }.issue?.text, "El pago mínimo no puede ser negativo.")
        pin(terms { $0.revolvingRate = 61 }.issue?.text, "El interés tiene que estar entre 0 y 60 %.")
        pin(terms { $0.installmentRate = -1 }.issue?.text, "El interés tiene que estar entre 0 y 60 %.")
        pin(terms { $0.payFromAccountId = account }.issue?.text, "La tarjeta no se puede pagar a sí misma.")
        pin(terms { $0.remindDaysBefore = 15 }.issue?.text, "El aviso puede ser de 0 a 14 días antes.")
        pin(terms { $0.alertPercent = 0 }.issue?.text, "El aviso del límite va del 1 al 100 %.")
    }

    func testCompraAplazada() {
        pin(CardInstallment(householdId: home, accountId: account, movementId: UUID(), months: 1).issue?.text,
            "Se puede aplazar de 2 a 48 meses.")
        pin(CardInstallment(householdId: home, accountId: account, movementId: UUID(), months: 12, rate: 61).issue?.text,
            "El interés tiene que estar entre 0 y 60 %.")
    }

    func testCategoria() {
        pin(BudgetCategory(householdId: home, name: "  ").issue(among: [])?.text, "Ponle un nombre a la categoría.")
        pin(BudgetCategory(householdId: home, name: String(repeating: "a", count: 41)).issue(among: [])?.text,
            "El nombre es demasiado largo (máximo 40 letras).")
        pin(BudgetCategory(householdId: home, name: "Bono", kind: .income, budgetGroup: .wants).issue(among: [])?.text,
            "Sólo los gastos van en un grupo del 50/30/20.")
        for (kind, word) in [(CategoryKind.expense, "gasto"), (.income, "ingreso"), (.transfer, "transferencia")] {
            let existing = BudgetCategory(householdId: home, name: "Mascotas", kind: kind)
            pin(BudgetCategory(householdId: home, name: "mascotas ", kind: kind).issue(among: [existing])?.text,
                "Ya hay una categoría de \(word) con ese nombre.")
        }
    }

    func testMovimientoYEtiquetas() {
        func draft(_ text: String = "Algo", cents: Int = 100, notes: String? = nil, payee: String? = nil,
                   tags: [String] = []) -> MovementDraft {
            MovementDraft(accountId: account, bookedOn: day, amount: Money(minor: cents), description: text, notes: notes,
                          payee: payee, tags: tags)
        }
        pin(draft("  ").issue?.text, "Escribe un concepto.")
        pin(draft(long200).issue?.text, "El concepto es demasiado largo (máximo 200 caracteres).")
        pin(draft(cents: 0).issue?.text, "El importe no puede ser cero.")
        pin(draft(notes: String(repeating: "a", count: 501)).issue?.text, "Las notas son demasiado largas (máximo 500 caracteres).")
        pin(draft(payee: String(repeating: "a", count: 81)).issue?.text, "El beneficiario es demasiado largo (máximo 80 caracteres).")
        pin(draft(tags: (1...11).map { "t\($0)" }).issue?.text, "Como mucho 10 etiquetas por movimiento.")
        pin(draft(tags: [""]).issue?.text, "Cada etiqueta debe tener entre 1 y 30 caracteres.")
        pin(draft(tags: ["Viaje"]).issue?.text, "Las etiquetas sólo pueden tener letras, números, «-» y «_».")
        pin(MovementTags.issue((1...11).map { "t\($0)" })?.text, "Como mucho 10 etiquetas por movimiento.")
        pin(MovementTags.issue([String(repeating: "a", count: 31)])?.text, "Cada etiqueta debe tener entre 1 y 30 caracteres.")
        pin(MovementTags.issue(["con espacio"])?.text, "Las etiquetas sólo pueden tener letras, números, «-» y «_».")
    }

    func testCuenta() {
        pin(AccountDraft(name: " ").issue?.text, "Ponle un nombre a la cuenta.")
        pin(AccountDraft(name: long60).issue?.text, "El nombre es demasiado largo (máximo 60 caracteres).")
    }

    func testTransferencia() {
        func transfer(to: UUID = UUID(), cents: Int = 100, from text: String = "Sale") -> TransferDraft {
            TransferDraft(fromAccountId: account, toAccountId: to, bookedOn: day, amount: Money(minor: cents),
                          fromDescription: text, toDescription: "Entra")
        }
        pin(transfer(to: account).issue?.text, "Elige dos cuentas distintas.")
        pin(transfer(cents: 0).issue?.text, "El importe tiene que ser mayor que cero.")
        pin(transfer(from: " ").issue?.text, "Escribe un concepto.")
    }

    func testMetaYAportacion() {
        func goal(_ name: String = "Viaje", kind: GoalKind = .savings, target: Int = 100, starting: Int = 0,
                  monthly: Int? = nil) -> Goal {
            Goal(householdId: home, name: name, kind: kind, target: Money(minor: target), starting: Money(minor: starting),
                 monthlyPlan: monthly.map { Money(minor: $0) })
        }
        pin(goal(" ").issue?.text, "Ponle un nombre a la meta.")
        pin(goal(long60).issue?.text, "El nombre es demasiado largo.")
        pin(goal(kind: .debt, target: 0).issue?.text, "Indica cuánto se debe.")
        pin(goal(target: 0).issue?.text, "Indica cuánto quieres juntar.")
        pin(goal(starting: -1).issue?.text, "Lo que ya tienes no puede ser negativo.")
        pin(goal(monthly: -1).issue?.text, "La aportación mensual no puede ser negativa.")
        pin(GoalContribution(householdId: home, goalId: UUID(), amount: .zero, madeOn: day).issue?.text, "El importe no puede ser cero.")
        pin(GoalContribution(householdId: home, goalId: UUID(), amount: Money(minor: 1), madeOn: day, note: long200).issue?.text,
            "La nota es demasiado larga.")
    }

    func testActivo() {
        func holding(_ name: String = "Fondo", symbol: String? = nil, price: String = "1", fee: Decimal = 0,
                     note: String? = nil) -> Holding {
            Holding(householdId: home, name: name, symbol: symbol, price: Decimal(string: price)!, feeRate: fee, note: note)
        }
        pin(holding(" ").issue?.text, "Ponle un nombre.")
        pin(holding(long60).issue?.text, "El nombre es demasiado largo.")
        pin(holding(symbol: String(repeating: "A", count: 21)).issue?.text, "El código es demasiado largo.")
        pin(holding(price: "-1").issue?.text, "El precio no puede ser negativo.")
        pin(holding(price: "1.1234567").issue?.text, "Como mucho 6 decimales en el precio.")
        pin(holding(fee: 11).issue?.text, "La comisión tiene que estar entre 0 y 10 %.")
        pin(holding(note: long200).issue?.text, "La nota es demasiado larga.")
    }

    func testOperacion() {
        let holdingId = UUID()
        func trade(_ side: TradeSide = .buy, quantity: String = "1", price: String = "1", fee: Int = 0, note: String? = nil,
                   on date: CalendarDay? = nil) -> InvestmentTrade {
            InvestmentTrade(householdId: home, holdingId: holdingId, tradedOn: date ?? day, side: side,
                            quantity: Decimal(string: quantity)!, price: Decimal(string: price)!, fee: Money(minor: fee), note: note)
        }
        pin(trade(quantity: "0").issue?.text, "Indica cuántas participaciones.")
        pin(trade(quantity: "0.123456789").issue?.text, "Como mucho 8 decimales en las participaciones.")
        pin(trade(price: "-1").issue?.text, "El precio no puede ser negativo.")
        pin(trade(price: "1.1234567").issue?.text, "Como mucho 6 decimales en el precio.")
        pin(trade(fee: -1).issue?.text, "La comisión no puede ser negativa.")
        pin(trade(note: long200).issue?.text, "La nota es demasiado larga.")
        pin(trade(quantity: "0").issue(given: [])?.text, "Indica cuántas participaciones.")
        pin(trade(.sell).issue(given: [])?.text, "No tienes tantas participaciones para vender.")
        let buy = trade(on: before)
        let sell = trade(.sell)
        pin(buy.deletionIssue(given: [buy, sell])?.text, "No se puede borrar esta compra: una venta posterior se quedaría sin participaciones.")
    }

    func testPlanDeInversion() {
        func plan(cents: Int = 100, every: Int = 1, endsOn: CalendarDay? = nil, yield: Decimal = 5,
                  remind: Int? = 1) -> InvestmentPlan {
            InvestmentPlan(householdId: home, holdingId: UUID(), amount: Money(minor: cents), recurrence: Recurrence(every: every),
                           startsOn: day, endsOn: endsOn, expectedAnnualReturn: yield, remindDaysBefore: remind)
        }
        pin(plan(cents: 0).issue?.text, "El importe tiene que ser mayor que cero.")
        pin(plan(every: 53).issue?.text, "La frecuencia no es válida.")
        pin(plan(endsOn: before).issue?.text, "No puede terminar antes de empezar.")
        pin(plan(yield: 51).issue?.text, "La rentabilidad supuesta tiene que estar entre −50 y 50 %.")
        pin(plan(remind: 15).issue?.text, "El aviso puede ser de 0 a 14 días antes.")
    }

    func testScoreDeCredito() {
        pin(CreditScore(score: 10, maxScore: 50).issue?.text, "La escala tiene que estar entre 100 y 1000.")
        pin(CreditScore(score: 900).issue?.text, "El score tiene que estar entre 0 y 850.")
        pin(CreditScore(score: 700, provider: long60).issue?.text, "El nombre del proveedor es demasiado largo.")
        pin(CreditScore(score: 700, note: long200).issue?.text, "La nota es demasiado larga.")
    }

    func testRecurrente() {
        func series(_ name: String = "Música", cents: Int = 100, every: Int = 1, endsOn: CalendarDay? = nil, remind: Int? = 1,
                    intro: Int? = nil, charges: Int? = nil) -> RecurringSeries {
            RecurringSeries(householdId: home, name: name, amount: Money(minor: cents), recurrence: Recurrence(every: every),
                            startsOn: day, endsOn: endsOn, remindDaysBefore: remind, introAmount: intro.map { Money(minor: $0) },
                            introCharges: charges)
        }
        pin(series(" ").issue?.text, "Ponle un nombre.")
        pin(series(long60).issue?.text, "El nombre es demasiado largo.")
        pin(series(cents: 0).issue?.text, "El importe tiene que ser mayor que cero.")
        pin(series(every: 53).issue?.text, "La frecuencia no es válida.")
        pin(series(endsOn: before).issue?.text, "No puede terminar antes de empezar.")
        pin(series(remind: 15).issue?.text, "El aviso puede ser de 0 a 14 días antes.")
        pin(series(intro: 50).issue?.text, "Indica el precio de oferta y cuántos cargos dura.")
        pin(series(intro: 0, charges: 3).issue?.text, "El precio de oferta tiene que ser mayor que cero.")
        pin(series(intro: 50, charges: 37).issue?.text, "La oferta puede durar de 1 a 36 cargos.")
    }

    /// Lo que ve el usuario cuando el servicio rechaza el dato: el mismo texto, por el camino de los errores.
    @MainActor
    func testLosServiciosDevuelvenElMismoTexto() async throws {
        let backend = InMemoryBackend()
        _ = try await backend.signUp(username: Username("ana"), password: "contrasena-de-prueba", displayName: nil)
        let house = try await backend.createHousehold(name: "Casa de prueba")
        let card = try await backend.createAccount(AccountDraft(name: "Corriente"), in: house.id)
        func message(_ call: () async throws -> Void) async -> String? {
            do { try await call(); return "sin error" } catch { return FinanceModel.message(for: error) }
        }
        pin(await message { _ = try await backend.createAccount(AccountDraft(name: " "), in: house.id) }, "Ponle un nombre a la cuenta.")
        pin(await message {
            _ = try await backend.addMovement(MovementDraft(accountId: card.id, bookedOn: self.day, amount: .zero, description: "x"),
                                              in: house.id)
        }, "El importe no puede ser cero.")
        pin(await message { _ = try await backend.saveExtraBudget(ExtraBudget(householdId: house.id, name: "X")) },
            "El límite tiene que ser mayor que cero.")
    }

    /// Títulos e iconos de los tipos que la app pinta. Copiados del código antes de moverlos a la app.
    func testTitulosEIconosDeLosTipos() {
        XCTAssertEqual(AccountKind.allCases.map(\.title), ["Cuenta corriente", "Ahorro", "Tarjeta de crédito", "Efectivo", "Inversión",
                                                           "Préstamo", "Otra"])
        XCTAssertEqual(AccountKind.allCases.map(\.systemImage), ["building.columns", "banknote", "creditcard", "eurosign",
                                                                 "chart.line.uptrend.xyaxis", "doc.text", "wallet.pass"])
        XCTAssertEqual(CategoryKind.allCases.map(\.title), ["Ingreso", "Gasto", "Transferencia"])
        XCTAssertEqual(GoalKind.allCases.map(\.title), ["Ahorro", "Pagar una deuda"])
        XCTAssertEqual(GoalKind.allCases.map(\.systemImage), ["banknote", "creditcard"])
        XCTAssertEqual(RecurringKind.allCases.map(\.title), ["Suscripción", "Gasto esencial", "Ingreso fijo"])
        XCTAssertEqual(RecurringKind.allCases.map(\.pluralTitle), ["Suscripciones", "Gastos esenciales", "Ingresos fijos"])
        XCTAssertEqual(RecurringKind.allCases.map(\.systemImage), ["play.rectangle", "bolt.house", "banknote"])
    }

    /// Los códigos del servidor que son una validación del modelo llegan tipados y se leen igual que antes.
    @MainActor
    func testErroresDelServidorConValidacionTipada() {
        let oversold = SupabaseBackend.appError(postgresCode: "STM02", message: "")
        XCTAssertEqual(oversold, .validation(.trade(.notEnoughShares)))
        pin(FinanceModel.message(for: oversold), "No tienes tantas participaciones para vender.")
        let needed = SupabaseBackend.appError(postgresCode: "STM03", message: "")
        XCTAssertEqual(needed, .validation(.trade(.neededByLaterSale)))
        pin(FinanceModel.message(for: needed), "No se puede borrar esta compra: una venta posterior se quedaría sin participaciones.")
        pin(AppError.validation(.transfer(.leg(.tags(.badCharacters)))).text,
            "Las etiquetas sólo pueden tener letras, números, «-» y «_».")
    }
}
