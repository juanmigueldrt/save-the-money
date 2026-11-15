package com.savethemoney.android.data

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.jsonPrimitive
import java.math.BigDecimal
import java.math.RoundingMode
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToLong

// Investments.swift de STMCore: activos, precios a mano, compras y ventas, y planes de aportación.
// Las participaciones y los precios son BigDecimal; los importes en euros, céntimos.

/** Un `numeric` de Postgres: se lee del texto del número para no pasar por coma flotante. */
object NumericSerializer : KSerializer<BigDecimal> {
    override val descriptor = PrimitiveSerialDescriptor("numeric", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: BigDecimal) = encoder.encodeString(value.toPlainString())
    override fun deserialize(decoder: Decoder): BigDecimal =
        (decoder as? JsonDecoder)?.decodeJsonElement()?.jsonPrimitive?.content?.toBigDecimal() ?: decoder.decodeString().toBigDecimal()
}

private typealias Numeric = @Serializable(with = NumericSerializer::class) BigDecimal

private val HUNDRED = BigDecimal(100)
private const val WORK_SCALE = 30

/** Unos euros con decimales, redondeados al céntimo (0,5 hacia arriba, y hacia abajo en negativos). */
fun BigDecimal.toMinor(): Long = multiply(HUNDRED).setScale(0, RoundingMode.HALF_UP).toLong()
private fun Long.euros(): BigDecimal = BigDecimal(this).movePointLeft(2)

@Serializable
enum class InvestmentKind(val title: String) {
    @SerialName("fund") Fund("Fondo"),
    @SerialName("etf") Etf("ETF"),
    @SerialName("stock") Stock("Acción"),
    @SerialName("bond") Bond("Bono"),
    @SerialName("crypto") Crypto("Cripto"),
    @SerialName("pension") Pension("Plan de pensiones"),
    @SerialName("cash") Cash("Liquidez"),
    @SerialName("other") Other("Otro");

    val defaultAssetClass: AssetClass get() = when (this) {
        Fund, Etf, Stock, Pension -> AssetClass.Equity
        Bond -> AssetClass.FixedIncome
        Crypto -> AssetClass.Crypto
        Cash -> AssetClass.Cash
        Other -> AssetClass.Other
    }
}

@Serializable
enum class AssetClass(val title: String) {
    @SerialName("equity") Equity("Renta variable"),
    @SerialName("fixed_income") FixedIncome("Renta fija"),
    @SerialName("crypto") Crypto("Cripto"),
    @SerialName("cash") Cash("Liquidez"),
    @SerialName("other") Other("Otros"),
}

@Serializable
enum class TradeSide(val title: String) { @SerialName("buy") Buy("Compra"), @SerialName("sell") Sell("Venta") }

/** Un fondo, ETF, acción... del hogar. El precio se apunta a mano. */
@Serializable
data class Holding(
    val id: String,
    @SerialName("household_id") val householdId: String,
    val name: String,
    val symbol: String? = null,
    val kind: InvestmentKind = InvestmentKind.Fund,
    @SerialName("asset_class") val assetClass: AssetClass = kind.defaultAssetClass,
    val currency: String = "EUR",
    @SerialName("account_id") val accountId: String? = null,
    @SerialName("owner_id") val ownerId: String? = null,
    val price: Numeric = BigDecimal.ZERO,
    @SerialName("price_on") val priceOn: String? = null,
    @SerialName("fee_rate") val feeRate: Numeric = BigDecimal.ZERO,
    val note: String? = null,
    @SerialName("archived_at") val archivedAt: String? = null,
) {
    val isArchived: Boolean get() = archivedAt != null
    val trimmedName: String get() = name.trim()
    val trimmedSymbol: String? get() = symbol?.trim()?.ifEmpty { null }?.uppercase()
    val priceDay: LocalDate? get() = priceOn?.let { LocalDate.parse(it.take(10)) }

    val issue: String? get() = when {
        trimmedName.isEmpty() -> "Ponle un nombre."
        trimmedName.length > 60 -> "El nombre es demasiado largo."
        (trimmedSymbol?.length ?: 0) > 20 -> "El código es demasiado largo."
        price.signum() < 0 -> "El precio no puede ser negativo."
        feeRate.signum() < 0 || feeRate > BigDecimal.TEN -> "La comisión tiene que estar entre 0 y 10 %."
        (note?.length ?: 0) > 200 -> "La nota es demasiado larga."
        else -> null
    }
}

/** Un precio apuntado a mano un día concreto (uno por activo y día). */
@Serializable
data class HoldingPrice(
    val id: String,
    @SerialName("household_id") val householdId: String,
    @SerialName("holding_id") val holdingId: String,
    @SerialName("priced_on") val pricedOn: String,
    val price: Numeric,
) {
    val day: LocalDate get() = LocalDate.parse(pricedOn.take(10))
}

/** Una compra o venta de participaciones. */
@Serializable
data class InvestmentTrade(
    val id: String,
    @SerialName("household_id") val householdId: String,
    @SerialName("holding_id") val holdingId: String,
    @SerialName("traded_on") val tradedOn: String,
    val side: TradeSide = TradeSide.Buy,
    val quantity: Numeric,
    val price: Numeric,
    @SerialName("fee_minor") val feeMinor: Long = 0,
    val note: String? = null,
) {
    val day: LocalDate get() = LocalDate.parse(tradedOn.take(10))
    val gross: Long get() = quantity.multiply(price).toMinor()

    /** Lo que sale de la cuenta en una compra (más la comisión) o entra en una venta (menos la comisión). */
    val cashImpact: Long get() = if (side == TradeSide.Buy) -(gross + feeMinor) else gross - feeMinor

    val issue: String? get() = when {
        quantity.signum() <= 0 -> "Indica cuántas participaciones."
        quantity.setScale(8, RoundingMode.HALF_UP).compareTo(quantity) != 0 -> "Como mucho 8 decimales en las participaciones."
        price.signum() < 0 -> "El precio no puede ser negativo."
        feeMinor < 0 -> "La comisión no puede ser negativa."
        (note?.length ?: 0) > 200 -> "La nota es demasiado larga."
        else -> null
    }

    /** Además de [issue]: no se pueden vender más participaciones de las que había ese día. */
    fun issue(others: List<InvestmentTrade>): String? {
        issue?.let { return it }
        if (side != TradeSide.Sell) return null
        val held = Position.quantity(holdingId, others.filter { it.id != id }, day)
        return if (quantity > held) "No tienes tantas participaciones para vender." else null
    }
}

/** El cálculo de "Comprar activo": por importe o por participaciones. */
data class BuyQuote(val amount: Long, val quantity: BigDecimal, val fee: Long) {
    val total: Long get() = amount + fee

    fun trade(holding: Holding, price: BigDecimal, day: LocalDate, note: String? = null) =
        InvestmentTrade("", holding.householdId, holding.id, day.toString(), TradeSide.Buy, quantity, price, fee, note)

    companion object {
        fun byAmount(amount: Long, price: BigDecimal, feeRate: BigDecimal): BuyQuote? {
            if (amount <= 0 || price.signum() <= 0) return null
            val quantity = amount.euros().divide(price, 8, RoundingMode.DOWN)
            if (quantity.signum() <= 0) return null
            return BuyQuote(amount, quantity, fee(amount, feeRate))
        }

        fun byQuantity(quantity: BigDecimal, price: BigDecimal, feeRate: BigDecimal): BuyQuote? {
            if (quantity.signum() <= 0 || price.signum() <= 0) return null
            val down = quantity.setScale(8, RoundingMode.DOWN)
            val amount = down.multiply(price).toMinor()
            if (amount <= 0) return null
            return BuyQuote(amount, down, fee(amount, feeRate))
        }

        fun fee(amount: Long, rate: BigDecimal): Long = amount.euros().multiply(rate).divide(HUNDRED, WORK_SCALE, RoundingMode.HALF_UP).toMinor()
    }
}

/** Lo que se tiene de un activo, con el método del precio medio. */
class Position(val holding: Holding, trades: List<InvestmentTrade>, through: LocalDate? = null) {
    val quantity: BigDecimal
    /** Coste de las participaciones que quedan, con comisiones. */
    val cost: Long
    /** Ganancia ya hecha con las ventas, después de comisiones. */
    val realized: Long
    /** Todo lo comprado, con comisiones. */
    val invested: Long

    init {
        var held = BigDecimal.ZERO
        var costMinor = 0L
        var realizedMinor = 0L
        var investedMinor = 0L
        for (trade in ordered(trades, holding.id, through)) {
            if (trade.side == TradeSide.Buy) {
                held += trade.quantity
                costMinor += trade.gross + trade.feeMinor
                investedMinor += trade.gross + trade.feeMinor
            } else {
                if (held.signum() <= 0) continue
                val sold = trade.quantity.min(held)
                val removed = BigDecimal(costMinor).multiply(sold).divide(held, WORK_SCALE, RoundingMode.HALF_UP).divide(HUNDRED).toMinor()
                realizedMinor += sold.multiply(trade.price).toMinor() - trade.feeMinor - removed
                costMinor -= removed
                held -= sold
            }
        }
        quantity = held
        cost = if (held.signum() > 0) costMinor else 0
        realized = realizedMinor
        invested = investedMinor
    }

    val averagePrice: BigDecimal get() = if (quantity.signum() > 0) cost.euros().divide(quantity, 6, RoundingMode.HALF_UP) else BigDecimal.ZERO
    val value: Long get() = quantity.multiply(holding.price).toMinor()
    val gain: Long get() = value - cost
    /** Ganancia sobre el coste; nulo si no queda nada. */
    val gainFraction: Double? get() = if (cost > 0) gain.toDouble() / cost else null

    companion object {
        fun quantity(holdingId: String, trades: List<InvestmentTrade>, through: LocalDate?): BigDecimal =
            ordered(trades, holdingId, through).fold(BigDecimal.ZERO) { held, trade ->
                if (trade.side == TradeSide.Buy) held + trade.quantity else (held - trade.quantity).max(BigDecimal.ZERO)
            }

        /** Las operaciones del activo por fecha; el mismo día, las compras antes que las ventas. */
        private fun ordered(trades: List<InvestmentTrade>, holdingId: String, through: LocalDate?) =
            trades.filter { it.holdingId == holdingId && (through == null || !it.day.isAfter(through)) }
                .sortedWith(compareBy({ it.day }, { it.side != TradeSide.Buy }))
    }
}

data class AllocationSlice(val assetClass: AssetClass, val value: Long, val fraction: Double)

/** Todas las posiciones del hogar con algo dentro. */
class Portfolio(holdings: List<Holding>, trades: List<InvestmentTrade>) {
    val positions: List<Position> = holdings.filter { !it.isArchived }.map { Position(it, trades) }.filter { it.quantity.signum() > 0 }
        .sortedWith(compareBy({ -it.value }, { it.holding.trimmedName }))

    val value: Long get() = positions.sumOf { it.value }
    val cost: Long get() = positions.sumOf { it.cost }
    val gain: Long get() = value - cost
    val gainFraction: Double? get() = if (cost > 0) gain.toDouble() / cost else null

    /** Por clase de activo, de mayor a menor, sin las vacías. */
    val allocation: List<AllocationSlice> get() {
        val total = value
        if (total <= 0) return emptyList()
        val byClass = positions.groupBy { it.holding.assetClass }.mapValues { (_, list) -> list.sumOf { it.value } }
        return AssetClass.entries.mapNotNull { kind -> byClass[kind]?.takeIf { it > 0 }?.let { AllocationSlice(kind, it, it.toDouble() / total) } }
            .sortedByDescending { it.value }
    }
}

enum class ChartRange(val title: String) {
    Day("1D"), Week("1S"), Month("1M"), HalfYear("6M"), Year("1A"), FiveYears("5A"), All("Todo");

    fun start(today: LocalDate, earliest: LocalDate?): LocalDate = when (this) {
        Day -> today.minusDays(1)
        Week -> today.minusDays(7)
        Month -> today.minusMonths(1)
        HalfYear -> today.minusMonths(6)
        Year -> today.minusMonths(12)
        FiveYears -> today.minusMonths(60)
        All -> minOf(earliest ?: today.minusMonths(1), today)
    }

    /** Días del gráfico: como mucho [maxPoints], repartidos, siempre con el primero y hoy. */
    fun days(today: LocalDate, earliest: LocalDate?, maxPoints: Int = 60): List<LocalDate> {
        val first = start(today, earliest)
        val span = ChronoUnit.DAYS.between(first, today).toInt()
        if (span <= 0) return listOf(today)
        val step = max(1, ceil(span.toDouble() / max(1, maxPoints - 1)).toInt())
        return (0 until span step step).map { first.plusDays(it.toLong()) } + today
    }
}

data class PortfolioPoint(val day: LocalDate, val value: Long)

object PriceHistory {
    /** Precios conocidos por fecha: operaciones, apuntados y el último del activo (manda lo apuntado). */
    fun points(holding: Holding, prices: List<HoldingPrice>, trades: List<InvestmentTrade>): List<Pair<LocalDate, BigDecimal>> {
        val byDay = sortedMapOf<LocalDate, BigDecimal>()
        trades.filter { it.holdingId == holding.id }.forEach { byDay[it.day] = it.price }
        prices.filter { it.holdingId == holding.id }.forEach { byDay[it.day] = it.price }
        holding.priceDay?.let { byDay[it] = holding.price }
        return byDay.map { it.key to it.value }
    }

    private fun price(day: LocalDate, points: List<Pair<LocalDate, BigDecimal>>, fallback: BigDecimal) =
        points.lastOrNull { !it.first.isAfter(day) }?.second ?: points.firstOrNull()?.second ?: fallback

    fun evolution(holdings: List<Holding>, prices: List<HoldingPrice>, trades: List<InvestmentTrade>, range: ChartRange, today: LocalDate): List<PortfolioPoint> {
        val active = holdings.filter { !it.isArchived }
        val ids = active.map { it.id }.toSet()
        val earliest = trades.filter { it.holdingId in ids }.minOfOrNull { it.day }
        val series = active.associate { it.id to points(it, prices, trades) }
        return range.days(today, earliest).map { day ->
            PortfolioPoint(day, active.sumOf { holding ->
                val held = Position.quantity(holding.id, trades, day)
                if (held.signum() <= 0) 0L
                else held.multiply(if (!day.isBefore(today)) holding.price else price(day, series[holding.id].orEmpty(), holding.price)).toMinor()
            })
        }
    }

    fun range(holding: Holding, prices: List<HoldingPrice>, trades: List<InvestmentTrade>, from: LocalDate, through: LocalDate): Pair<BigDecimal, BigDecimal>? {
        val values = points(holding, prices, trades).filter { !it.first.isBefore(from) && !it.first.isAfter(through) }.map { it.second }
        return if (values.isEmpty()) null else values.min() to values.max()
    }
}

/** Plan para invertir una cantidad fija cada cierto tiempo. No compra solo: avisa y se confirma en la app. */
@Serializable
data class InvestmentPlan(
    val id: String,
    @SerialName("household_id") val householdId: String,
    @SerialName("holding_id") val holdingId: String,
    @SerialName("account_id") val accountId: String? = null,
    @SerialName("amount_minor") val amountMinor: Long,
    val every: Int = 1,
    val unit: RecurrenceUnit = RecurrenceUnit.Month,
    @SerialName("starts_on") val startsOn: String,
    @SerialName("ends_on") val endsOn: String? = null,
    @SerialName("expected_annual_return") val expectedAnnualReturn: Numeric = BigDecimal(5),
    @SerialName("remind_days_before") val remindDaysBefore: Int? = 1,
    @SerialName("paused_at") val pausedAt: String? = null,
    @SerialName("archived_at") val archivedAt: String? = null,
) {
    val isPaused: Boolean get() = pausedAt != null
    val isArchived: Boolean get() = archivedAt != null
    val recurrence: Recurrence get() = Recurrence(every, unit)
    val startDay: LocalDate get() = LocalDate.parse(startsOn.take(10))
    val endDay: LocalDate? get() = endsOn?.let { LocalDate.parse(it.take(10)) }

    fun isActive(day: LocalDate): Boolean = !isPaused && !isArchived && endDay?.isBefore(day) != true

    /** El calendario de cargos es el mismo que el de un pago recurrente. */
    private val schedule: RecurringSeries
        get() = RecurringSeries("", householdId, "plan", amountMinor = amountMinor, every = every, unit = unit, startsOn = startsOn, endsOn = endsOn)

    fun occurrences(from: LocalDate, through: LocalDate): List<LocalDate> = schedule.occurrences(from, through)
    fun nextDue(day: LocalDate): LocalDate? = if (isPaused || isArchived) null else schedule.nextDue(day)
    val monthlyAmount: Long get() = schedule.monthlyAmount

    /** Lo que se ha comprado del activo desde que empezó el plan, con comisiones. */
    fun invested(trades: List<InvestmentTrade>, through: LocalDate): Long =
        trades.filter { it.holdingId == holdingId && it.side == TradeSide.Buy && !it.day.isBefore(startDay) && !it.day.isAfter(through) }
            .sumOf { it.gross + it.feeMinor }

    /** Lo que valdrían en [months] meses las aportaciones de ese tiempo (interés compuesto mensual). */
    fun projectedValue(months: Int): Long {
        if (months <= 0) return 0
        val rate = (1 + expectedAnnualReturn.toDouble() / 100).pow(1.0 / 12) - 1
        val factor = if (abs(rate) < 1e-12) months.toDouble() else ((1 + rate).pow(months) - 1) / rate * (1 + rate)
        return (monthlyAmount * factor).roundToLong()
    }

    val issue: String? get() = when {
        amountMinor <= 0 -> "El importe tiene que ser mayor que cero."
        every !in 1..52 -> "La frecuencia no es válida."
        endDay?.isBefore(startDay) == true -> "No puede terminar antes de empezar."
        expectedAnnualReturn < BigDecimal(-50) || expectedAnnualReturn > BigDecimal(50) -> "La rentabilidad supuesta tiene que estar entre −50 y 50 %."
        remindDaysBefore != null && remindDaysBefore !in 0..14 -> "El aviso puede ser de 0 a 14 días antes."
        else -> null
    }
}

data class PlanCharge(val plan: InvestmentPlan, val due: LocalDate)

/** Aportaciones de los planes activos en un mes, por fecha (para el calendario). */
fun List<InvestmentPlan>.charges(month: YearMonth): List<PlanCharge> =
    filter { !it.isPaused && !it.isArchived }
        .flatMap { plan -> plan.occurrences(month.atDay(1), month.atEndOfMonth()).map { PlanCharge(plan, it) } }
        .sortedWith(compareBy({ it.due }, { -it.plan.amountMinor }))

fun List<InvestmentPlan>.monthlyTotal(day: LocalDate): Long = filter { it.isActive(day) }.sumOf { it.monthlyAmount }

fun List<InvestmentPlan>.counts(day: LocalDate): Pair<Int, Int> {
    val live = filter { !it.isArchived && it.endDay?.isBefore(day) != true }
    return live.count { !it.isPaused } to live.count { it.isPaused }
}

/** Lee un número escrito a mano: "12,5", "12.5", "1.234,56" o "1,234.56". Nulo si no se entiende o es negativo. */
fun parseDecimal(text: String): BigDecimal? {
    var s = text.replace("€", "").replace("%", "").filterNot { it.isWhitespace() }
    if (s.isEmpty()) return null
    val comma = s.lastIndexOf(',')
    val dot = s.lastIndexOf('.')
    s = if (comma >= 0 && dot >= 0) {
        if (comma > dot) s.replace(".", "").replace(",", ".") else s.replace(",", "")
    } else {
        s.replace(",", ".")
    }
    if (s.count { it == '.' } > 1 || !s.all { it == '.' || it in '0'..'9' }) return null
    return s.toBigDecimalOrNull()
}

object InvestmentReminders {
    const val PREFIX = "stm.investment."

    /** Avisos de las próximas aportaciones de los planes activos que tienen aviso. */
    fun plan(plans: List<InvestmentPlan>, holdings: List<Holding>, today: LocalDate, horizonDays: Long = 45, limit: Int = 10, hour: Int = 9): List<PlannedReminder> {
        val end = today.plusDays(horizonDays)
        val names = holdings.associate { it.id to it.trimmedName }
        val result = mutableListOf<PlannedReminder>()
        for (plan in plans) {
            if (!plan.isActive(today)) continue
            val before = plan.remindDaysBefore ?: continue
            val name = names[plan.holdingId] ?: continue
            for (due in plan.occurrences(today, end.plusDays(before.toLong()))) {
                val fire = due.minusDays(before.toLong())
                if (fire.isBefore(today) || fire.isAfter(end)) continue
                val time = when (before) { 0 -> "Hoy"; 1 -> "Mañana"; else -> "En $before días" }
                result += PlannedReminder(
                    "$PREFIX${plan.id}.$due", fire.toString(), hour, "$time: aportación a $name",
                    "Toca invertir ${Money.format(plan.amountMinor)} el ${due.dayOfMonth} de ${ReminderPlanner.MESES[due.monthValue - 1]}. Abre la app para confirmar la compra.",
                )
            }
        }
        return result.sortedWith(compareBy({ it.fireOn }, { it.id })).take(limit)
    }
}

/** Formatos de cifras de inversión, como InvestmentText de iOS. */
object InvestmentText {
    private val spain = DecimalFormatSymbols(Locale("es", "ES"))
    private fun format(value: BigDecimal, pattern: String, grouping: Boolean = true) =
        DecimalFormat(pattern, spain).apply { roundingMode = RoundingMode.HALF_EVEN; isGroupingUsed = grouping }.format(value)

    /** "12,5034 €": de 2 a 4 decimales. */
    fun price(value: BigDecimal, currency: String = "EUR") = format(value, "#,##0.00##") + if (currency == "EUR") " €" else " $currency"
    /** "12,5" participaciones, hasta 6 decimales. */
    fun quantity(value: BigDecimal) = format(value, "#,##0.######")
    /** "+12,3 %" o "−4,0 %". */
    fun percent(fraction: Double): String {
        val value = (fraction * 1000).roundToLong() / 10.0
        val text = "%.1f".format(Locale.ROOT, abs(value)).replace(".", ",")
        return (if (value > 0) "+" else if (value < 0) "${Money.MINUS}" else "") + text + " %"
    }
    fun rate(value: BigDecimal) = format(value, "#,##0.###") + " %"
    /** Texto editable: "12,5". */
    fun plain(value: BigDecimal) = format(value, "#,##0.########", grouping = false)
}
