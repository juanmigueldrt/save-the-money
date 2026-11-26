package com.savethemoney.android.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.serializer
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * ORC-129: cada enumerado que la app manda al servidor se serializa con su `@SerialName`. Los valores esperados están
 * escritos a mano desde las migraciones (enum de Postgres o check), no sacados del código: si un nombre de Kotlin cambia,
 * lo que tiene que cambiar es el `@SerialName`, y estas pruebas lo impiden.
 */
class CodigosDeEnumTest {
    private inline fun <reified T : Enum<T>> codigos(): Map<String, String> =
        enumValues<T>().associate { it.name to Json.encodeToJsonElement(serializer<T>(), it).jsonPrimitive.content }

    // recurrence_unit: ('week', 'month', 'year')
    @Test
    fun laUnidadDeRepeticionVaComoSuEnumeradoDePostgres() {
        assertEquals(mapOf("Week" to "week", "Month" to "month", "Year" to "year"), codigos<RecurrenceUnit>())
    }

    // check de recurring_charges.status: ('pending', 'confirmed', 'skipped')
    @Test
    fun elEstadoDeUnCargoVaComoSuCheckDeLaTabla() {
        assertEquals(mapOf("Pending" to "pending", "Confirmed" to "confirmed", "Skipped" to "skipped"), codigos<ChargeStatus>())
    }

    // goal_kind: ('savings', 'debt')
    @Test
    fun elTipoDeMetaVaComoSuEnumeradoDePostgres() {
        assertEquals(mapOf("Savings" to "savings", "Debt" to "debt"), codigos<GoalKind>())
    }

    // card_payment_mode: ('full', 'fixed', 'minimum')
    @Test
    fun elModoDePagoDeLaTarjetaVaComoSuEnumeradoDePostgres() {
        assertEquals(mapOf("Full" to "full", "Fixed" to "fixed", "Minimum" to "minimum"), codigos<CardPaymentMode>())
    }

    // app_theme: ('system', 'light', 'dark')
    @Test
    fun elTemaVaComoSuEnumeradoDePostgres() {
        assertEquals(mapOf("System" to "system", "Light" to "light", "Dark" to "dark"), codigos<AppTheme>())
    }

    // recurring_kind: ('subscription', 'essential', 'income')
    @Test
    fun elTipoDePagoFijoVaComoSuEnumeradoDePostgres() {
        assertEquals(mapOf("Subscription" to "subscription", "Essential" to "essential", "Income" to "income"), codigos<RecurringKind>())
    }

    /** Los parámetros de las funciones que usan esos enumerados llevan el código, no el nombre de Kotlin. */
    @Test
    fun losParametrosDeEnumeradoDeLasEscriturasLlevanElCodigo() {
        val serie = RecurringSeries("s1", "h", "Alquiler", kind = RecurringKind.Essential, amountMinor = 10_000, unit = RecurrenceUnit.Year, startsOn = "2026-11-05")
        assertEquals(JsonPrimitive("essential"), RpcEscrituras.createRecurring(serie).params["series_kind"])
        assertEquals(JsonPrimitive("year"), RpcEscrituras.createRecurring(serie).params["step_unit"])

        val meta = Goal("g1", "h", "Deuda", kind = GoalKind.Debt, targetMinor = 10_000)
        assertEquals(JsonPrimitive("debt"), RpcEscrituras.updateGoal(meta).params["goal_kind"])

        val tarjeta = CreditCardTerms("a1", "h", 300_000, paymentMode = CardPaymentMode.Minimum)
        assertEquals(JsonPrimitive("minimum"), RpcEscrituras.saveCreditCard(tarjeta).params["mode"])

        val cargo = RecurringCharge("x1", "h", "s1", "2026-11-05", -10_000)
        assertEquals(JsonPrimitive("skipped"), RpcEscrituras.updateCharge(cargo, ChargeStatus.Skipped, null).params["new_status"])
    }
}
