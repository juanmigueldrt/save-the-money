package com.savethemoney.android.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.math.BigDecimal
import java.time.LocalDate

/**
 * ORC-142: las claves que manda la app a cada función `create_…` / `update_…` son exactamente los parámetros de la función.
 * La lista (`testdata/vectors/rpc_escrituras.json`) está escrita a mano desde la migración; la comparten la prueba de iOS
 * (RpcEscriturasTests) y `supabase/tests/api/escrituras_idempotentes.py`, que hace esas llamadas al PostgREST local.
 */
class RpcEscriturasTest {
    private val seen = "2026-11-01T10:00:00.123456+00:00"
    private val day = LocalDate.of(2026, 11, 5)

    // Gradle corre las pruebas desde `android/app`.
    private val expected: Map<String, Set<String>> =
        Json.parseToJsonElement(File("../../testdata/vectors/rpc_escrituras.json").readText()).jsonObject["functions"]!!.jsonArray.associate { f ->
            f.jsonObject["name"]!!.jsonPrimitive.content to f.jsonObject["keys"]!!.jsonArray.map { it.jsonPrimitive.content }.toSet()
        }

    /** Una llamada de cada función, con datos inventados. Lo que lleva versión es un cambio; lo que no, un alta. */
    private fun calls(): List<RpcCall> {
        val series = RecurringSeries("s1", "h", "Alquiler", amountMinor = 10_000, startsOn = day.toString())
        val goal = Goal("g1", "h", "Vacaciones", targetMinor = 10_000)
        val terms = CreditCardTerms("a1", "h", 300_000)
        val plan = CardInstallment("m1", "h", "a1", "m1", 6)
        val holding = Holding("f1", "h", "Fondo", price = BigDecimal.TEN)
        val investment = InvestmentPlan("p1", "h", "f1", amountMinor = 10_000, startsOn = day.toString())
        val category = BudgetCategory("c1", "h", "Mascotas")
        val extra = ExtraBudget("e1", "h", "Viaje", 10_000, day)
        return listOf(
            RpcEscrituras.createAccount(AccountDraft("Corriente"), "h"),
            RpcEscrituras.updateAccount(Account("a1", "h", "Corriente", updatedAt = seen)),
            RpcEscrituras.createGoal(goal),
            RpcEscrituras.updateGoal(goal),
            RpcEscrituras.addContribution(GoalContribution("", "h", "g1", 10_000, day.toString())),
            RpcEscrituras.createRecurring(series),
            RpcEscrituras.updateRecurring(series),
            RpcEscrituras.saveCreditCard(terms),
            RpcEscrituras.saveCreditCard(terms.copy(updatedAt = seen)),
            RpcEscrituras.saveInstallment(plan),
            RpcEscrituras.saveInstallment(plan.copy(updatedAt = seen)),
            RpcEscrituras.createHolding(holding),
            RpcEscrituras.updateHolding(holding),
            RpcEscrituras.createPlan(investment),
            RpcEscrituras.updatePlan(investment),
            RpcEscrituras.createCategory(category),
            RpcEscrituras.updateCategory(category),
            RpcEscrituras.saveExtraBudget(extra),
            RpcEscrituras.saveExtraBudget(extra.copy(updatedAt = seen)),
            RpcEscrituras.updateCharge(RecurringCharge("x1", "h", "s1", day.toString(), -10_000, updatedAt = seen), ChargeStatus.Skipped, null),
        )
    }

    @Test
    fun theKeysOfEachCallAreTheParametersOfItsFunction() {
        val calls = calls()
        assertEquals(20, expected.size)
        assertEquals("una llamada por función, sin faltar ninguna", expected.keys.sorted(), calls.map { it.function }.sorted())
        calls.forEach { assertEquals(it.function, expected.getValue(it.function), it.params.keys) }
    }

    /** Un parámetro sin valor va como `null` explícito, no se omite: las funciones de cambio no tienen valores por defecto. */
    @Test
    fun nullsAreSentExplicitly() {
        val params = RpcEscrituras.updateGoal(Goal("g1", "h", "Vacaciones", targetMinor = 1)).params
        assertEquals(JsonNull, params["seen"])
        assertEquals(JsonNull, params["account"])
    }
}
