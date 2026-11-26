import XCTest
import STMCore
@testable import STMData

/// ORC-142: las claves que manda la app a cada función `create_…` / `update_…` son exactamente los parámetros de la
/// función. La lista (`testdata/vectors/rpc_escrituras.json`) está escrita a mano desde la migración; la comparten la
/// prueba de Android y `supabase/tests/api/escrituras_idempotentes.py`, que hace esas llamadas al PostgREST local.
final class RpcEscriturasTests: XCTestCase {
    private struct Function: Decodable { var name: String; var keys: [String] }
    private struct File: Decodable { var functions: [Function] }

    private func vectors() throws -> [String: Set<String>] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("testdata/vectors/rpc_escrituras.json")
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        return Dictionary(uniqueKeysWithValues: file.functions.map { ($0.name, Set($0.keys)) })
    }

    /// Una llamada de cada función, con datos inventados. Lo que lleva versión es un cambio; lo que no, un alta.
    private func calls() throws -> [RpcCall] {
        let home = UUID(), account = UUID(), seen = "2026-11-01T10:00:00.123456+00:00"
        let day = try XCTUnwrap(CalendarDay(year: 2026, month: 11, day: 5))
        let money = Money(minor: 10_000)
        let series = RecurringSeries(householdId: home, name: "Alquiler", amount: money, startsOn: day)
        let goal = Goal(householdId: home, name: "Vacaciones", target: money)
        let terms = CreditCardTerms(accountId: account, householdId: home, creditLimit: money)
        let plan = CardInstallment(householdId: home, accountId: account, movementId: UUID(), months: 6)
        let holding = Holding(householdId: home, name: "Fondo", price: 10)
        let investment = InvestmentPlan(householdId: home, holdingId: holding.id, amount: money, startsOn: day)
        let category = BudgetCategory(householdId: home, name: "Mascotas")
        let extra = ExtraBudget(householdId: home, name: "Viaje", limit: money, startsOn: day)
        let charge = RecurringCharge(householdId: home, seriesId: series.id, dueOn: day, amount: money, updatedAt: seen)
        var seenTerms = terms, seenPlan = plan, seenExtra = extra
        seenTerms.updatedAt = seen
        seenPlan.updatedAt = seen
        seenExtra.updatedAt = seen
        return [
            SupabaseBackend.createAccountCall(AccountDraft(name: "Corriente"), in: home),
            SupabaseBackend.updateAccountCall(Account(householdId: home, name: "Corriente", updatedAt: seen)),
            SupabaseBackend.createGoalCall(goal),
            SupabaseBackend.updateGoalCall(goal),
            SupabaseBackend.addContributionCall(GoalContribution(householdId: home, goalId: goal.id, amount: money, madeOn: day)),
            SupabaseBackend.createRecurringCall(series),
            SupabaseBackend.updateRecurringCall(series),
            SupabaseBackend.saveCreditCardCall(terms),
            SupabaseBackend.saveCreditCardCall(seenTerms),
            SupabaseBackend.saveInstallmentCall(plan),
            SupabaseBackend.saveInstallmentCall(seenPlan),
            SupabaseBackend.createHoldingCall(holding),
            SupabaseBackend.updateHoldingCall(holding),
            SupabaseBackend.createPlanCall(investment),
            SupabaseBackend.updatePlanCall(investment),
            SupabaseBackend.createCategoryCall(category),
            SupabaseBackend.updateCategoryCall(category),
            SupabaseBackend.saveExtraBudgetCall(extra),
            SupabaseBackend.saveExtraBudgetCall(seenExtra),
            SupabaseBackend.updateChargeCall(charge, status: .skipped, transactionId: nil)
        ]
    }

    func testLasClavesDeCadaLlamadaSonLosParametrosDeSuFuncion() throws {
        let expected = try vectors()
        let calls = try calls()
        XCTAssertEqual(expected.count, 20)
        XCTAssertEqual(calls.map(\.function).sorted(), expected.keys.sorted(), "una llamada por función, sin faltar ninguna")
        for call in calls {
            let keys = try XCTUnwrap(expected[call.function], call.function)
            XCTAssertEqual(Set(call.params.keys), keys, call.function)
        }
    }

    /// Un parámetro sin valor va como `null` explícito, no se omite: las funciones de cambio no tienen valores por defecto.
    func testLosNulosVanExplicitos() throws {
        let call = SupabaseBackend.updateGoalCall(Goal(householdId: UUID(), name: "Vacaciones", target: Money(minor: 1)))
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(call.params), encoding: .utf8))
        XCTAssertTrue(json.contains("\"seen\":null"), json)
        XCTAssertTrue(json.contains("\"account\":null"), json)
    }
}
