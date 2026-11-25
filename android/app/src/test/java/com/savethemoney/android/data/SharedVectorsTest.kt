package com.savethemoney.android.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.longOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import java.io.File
import java.time.LocalDate

/**
 * Vectores de `testdata/vectors/`, compartidos con iOS (SharedVectorsTests.swift).
 * Si uno falla aquí y no allí (o al revés), iOS y Android ya no calculan lo mismo.
 */
class SharedVectorsTest {
    /** Gradle corre las pruebas desde `android/app`. */
    private fun load(name: String, key: String = "vectors"): JsonArray =
        Json.parseToJsonElement(File("../../testdata/vectors/$name").readText()).jsonObject[key]!!.jsonArray
            .also { assertFalse("$name sin vectores", it.isEmpty()) }

    private operator fun JsonElement.get(key: String): JsonElement? = jsonObject[key]?.takeUnless { it is JsonNull }
    private fun JsonElement.str(key: String): String = this[key]!!.jsonPrimitive.content
    private fun JsonElement.int(key: String): Int = this[key]!!.jsonPrimitive.int
    private fun JsonElement.date(key: String): LocalDate = LocalDate.parse(str(key))

    @Test
    fun moneyParsing() {
        for (v in load("money_parse.json")) {
            assertEquals("«${v.str("input")}»", v["minor"]?.jsonPrimitive?.long, Money.parse(v.str("input")))
        }
    }

    @Test
    fun decimalParsing() {
        for (v in load("decimal_parse.json")) {
            val expected = v["value"]?.jsonPrimitive?.content?.toBigDecimal()
            val got = parseDecimal(v.str("input"), v.int("maxFractionDigits"))
            // Sin ceros finales: para BigDecimal 1250 y 1250.0 no son iguales.
            assertEquals("«${v.str("input")}» con ${v.str("maxFractionDigits")} decimales", expected?.stripTrailingZeros(), got?.stripTrailingZeros())
        }
    }

    @Test
    fun cardInstallmentsAndStatementDates() {
        for (v in load("card_installments.json", "installments")) {
            val got = CardInstallment.payment(v["principal"]!!.jsonPrimitive.long, v.int("months"), v["rate"]!!.jsonPrimitive.double)
            assertEquals("${v.str("principal")} en ${v.str("months")} meses al ${v.str("rate")} %", v["payment"]!!.jsonPrimitive.long, got)
        }
        for (v in load("card_installments.json", "statementDates")) {
            val terms = CreditCardTerms(
                accountId = "card", householdId = "home", creditLimit = 100_000,
                statementDay = v.int("statementDay"), paymentDay = v.int("paymentDay"), paymentDelayMonths = v.int("paymentDelayMonths"),
            )
            val closing = terms.statementClosing(v.date("purchase"))
            val label = "compra ${v.str("purchase")}"
            assertEquals(label, v.date("closing"), closing)
            assertEquals(label, v.date("payment"), terms.paymentDate(closing))
            assertEquals(label, v.date("cycleStart"), terms.cycleStart(closing))
        }
    }

    @Test
    fun cardSummaries() {
        for (v in load("card_installments.json", "summaries")) {
            val name = v.str("name")
            val terms = CreditCardTerms(
                accountId = "card", householdId = "home", creditLimit = 300_000,
                statementDay = v.int("statementDay"), paymentDay = v.int("paymentDay"), paymentDelayMonths = v.int("paymentDelayMonths"),
            )
            val movements = v["movements"]!!.jsonArray.map {
                val payment = it["payment"]?.jsonPrimitive?.content == "true"
                Movement(it.str("key"), "home", "card", if (payment) "transfer" else null, it.str("day"), it["amount"]!!.jsonPrimitive.long, it.str("key"))
            }
            // Un aplazado cuya compra no está en la lista apunta a un movimiento que no se ha cargado.
            val plans = v["installments"]!!.jsonArray.mapIndexed { i, it ->
                CardInstallment("plan$i", "home", "card", it.str("movement"), it.int("months"), it["rate"]!!.jsonPrimitive.double)
            }
            val s = CreditCardCalculator.summary(terms, v["balance"]!!.jsonPrimitive.long, movements, plans, setOf("transfer"), v.date("today"))
            assertEquals(name, v["used"]!!.jsonPrimitive.long, s.used)
            assertEquals(name, v["revolvingBalance"]!!.jsonPrimitive.long, s.revolvingBalance)
            assertEquals(name, v.int("unresolved"), s.unresolvedInstallments.size)
            val got = s.payments.map { "${it.due} ${it.amount} ${it.purchases} ${it.installments} ${it.interest}" }
            val expected = v["payments"]!!.jsonArray.map {
                "${it.str("due")} ${it.str("amount")} ${it.str("purchases")} ${it.str("installments")} ${it.str("interest")}"
            }
            assertEquals(name, expected, got)
        }
    }

    @Test
    fun paymentCalendar() {
        for (v in load("payment_calendar.json")) {
            val s = v["series"]!!
            val series = RecurringSeries(
                id = "serie", householdId = "home", name = "Serie",
                kind = RecurringKind.entries.first { it.name.equals(s.str("kind"), ignoreCase = true) },
                amountMinor = s["amount"]!!.jsonPrimitive.long,
                every = s.int("every"),
                unit = RecurrenceUnit.entries.first { it.name.equals(s.str("unit"), ignoreCase = true) },
                startsOn = s.str("startsOn"), endsOn = s["endsOn"]?.jsonPrimitive?.content,
                introMinor = s["introAmount"]?.jsonPrimitive?.longOrNull, introCharges = s["introCharges"]?.jsonPrimitive?.intOrNull,
            )
            val got = PaymentCalendar(listOf(series), emptyList(), emptyList()) { "" }.between(v.date("from"), v.date("through"))
                .map { "${it.day} ${it.amount}" }
            val expected = v["payments"]!!.jsonArray.map { "${it.str("day")} ${it["amount"]!!.jsonPrimitive.long}" }
            assertEquals(v.str("name"), expected, got)
        }
    }

    @Test
    fun budgetPeriods() {
        for (v in load("budget_periods.json")) {
            val schedule = PaySchedule(
                PayFrequency.of(v.str("frequency"))!!, v.int("day1"), v["day2"]?.jsonPrimitive?.intOrNull,
                v["anchor"]?.let { LocalDate.parse(it.jsonPrimitive.content) },
            )
            val period = schedule.period(v.date("day"))
            assertEquals("${v.str("frequency")} ${v.str("day1")} el ${v.str("day")}",
                "${v.str("start")}..${v.str("end")}", "${period.start}..${period.end}")
        }
    }

    @Test
    fun importFingerprint() {
        for (v in load("import_fingerprint.json")) {
            val table = CsvTable.parse(v.str("csv"))
            val mapping = CsvMapping.detect(table)!!
            val got = CsvImporter.rows(table, mapping, "account").map { it.draft?.importHash }
            assertEquals(v.str("name"), v["rows"]!!.jsonArray.map { it.str("importHash") }, got)
        }
    }

    @Test
    fun tradeTimeline() {
        for (v in load("trade_timeline.json")) {
            val trades = v["trades"]!!.jsonArray.mapIndexed { i, t ->
                val side = if (t.str("side") == "buy") TradeSide.Buy else TradeSide.Sell
                InvestmentTrade("t$i", "home", "h", t.str("day"), side, t.str("quantity").toBigDecimal(), 10.toBigDecimal())
            }
            assertEquals(v.str("name"), v["oversold"]!!.jsonPrimitive.boolean, Position.isOversold("h", trades))
        }
    }

    @Test
    fun sha256() {
        for (v in load("sha256.json")) {
            val input = v.str("text").repeat(v.int("repeat"))
            assertEquals(v.int("utf8Bytes"), input.toByteArray(Charsets.UTF_8).size)
            assertEquals("«${v.str("text")}» × ${v.str("repeat")}", v.str("sha256"), CsvImporter.sha256Hex(input))
        }
    }
}
