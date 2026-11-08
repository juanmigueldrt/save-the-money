package com.savethemoney.android.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.ChronoUnit
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

// CreditCards.swift de STMCore: condiciones, compras aplazadas y cuánto se paga cada mes.
// Los tipos de interés van en Double como en el cálculo de iOS; los importes, siempre en céntimos.

@Serializable
enum class CardPaymentMode(val title: String, val detail: String) {
    @SerialName("full") Full("Todo a fin de mes", "Pagas el extracto entero cada mes, sin intereses."),
    @SerialName("fixed") Fixed("Cuota fija", "Pagas la misma cantidad cada mes; lo que queda genera intereses."),
    @SerialName("minimum") Minimum("Pago mínimo", "Pagas lo mínimo que pide el banco; lo que queda genera intereses.");

    /** Las formas que dejan deuda pendiente con intereses (revolving). */
    val isRevolving: Boolean get() = this != Full
}

@Serializable
data class CreditCardTerms(
    @SerialName("account_id") val accountId: String,
    @SerialName("household_id") val householdId: String,
    @SerialName("credit_limit_minor") val creditLimit: Long,
    @SerialName("statement_day") val statementDay: Int = 1,
    @SerialName("payment_day") val paymentDay: Int = 1,
    @SerialName("payment_delay_months") val paymentDelayMonths: Int = 1,
    @SerialName("payment_mode") val paymentMode: CardPaymentMode = CardPaymentMode.Full,
    @SerialName("fixed_payment_minor") val fixedPayment: Long? = null,
    @SerialName("min_payment_percent") val minPaymentPercent: Double = 3.0,
    @SerialName("min_payment_minor") val minPayment: Long = 1_500,
    @SerialName("revolving_rate") val revolvingRate: Double = 20.0,
    @SerialName("installment_rate") val installmentRate: Double = 14.0,
    @SerialName("pay_from_account_id") val payFromAccountId: String? = null,
    @SerialName("remind_days_before") val remindDaysBefore: Int? = 2,
    @SerialName("alert_percent") val alertPercent: Int? = 80,
) {
    /** Problema que impide guardarla, en español, o nulo si es válida. */
    val issue: String? get() = when {
        creditLimit <= 0 -> "El límite tiene que ser mayor que cero."
        statementDay !in 1..28 -> "El día del extracto va del 1 al 28."
        paymentDay !in 1..28 -> "El día del cargo va del 1 al 28."
        paymentDelayMonths !in 0..2 -> "El cargo puede ser el mismo mes del extracto o hasta dos meses después."
        paymentMode == CardPaymentMode.Fixed && (fixedPayment ?: 0) <= 0 -> "Indica la cuota fija que pagas cada mes."
        fixedPayment != null && fixedPayment <= 0 -> "La cuota fija tiene que ser mayor que cero."
        minPaymentPercent < 0 || minPaymentPercent > 100 -> "El % del pago mínimo va de 0 a 100."
        minPayment < 0 -> "El pago mínimo no puede ser negativo."
        revolvingRate < 0 || revolvingRate > 60 || installmentRate < 0 || installmentRate > 60 -> "El interés tiene que estar entre 0 y 60 %."
        payFromAccountId == accountId -> "La tarjeta no se puede pagar a sí misma."
        remindDaysBefore != null && remindDaysBefore !in 0..14 -> "El aviso puede ser de 0 a 14 días antes."
        alertPercent != null && alertPercent !in 1..100 -> "El aviso del límite va del 1 al 100 %."
        else -> null
    }

    /** Día en que se cierra el extracto en el que entra un gasto de [day]. */
    fun statementClosing(day: LocalDate): LocalDate {
        val thisMonth = day.withDayOfMonth(statementDay)
        return if (day.isBefore(thisMonth)) thisMonth else thisMonth.plusMonths(1)
    }

    /** Día en que se cobra el extracto que se cierra en [closing]. */
    fun paymentDate(closing: LocalDate): LocalDate = YearMonth.from(closing).plusMonths(paymentDelayMonths.toLong()).atDay(paymentDay)

    /** Primer día de gasto que entra en el extracto que se cierra en [closing]. */
    fun cycleStart(closing: LocalDate): LocalDate = closing.minusMonths(1)
}

@Serializable
data class CardInstallment(
    val id: String,
    @SerialName("household_id") val householdId: String,
    @SerialName("account_id") val accountId: String,
    @SerialName("transaction_id") val movementId: String,
    val months: Int,
    val rate: Double = 14.0,
) {
    val issue: String? get() = when {
        months !in 2..48 -> "Se puede aplazar de 2 a 48 meses."
        rate < 0 || rate > 60 -> "El interés tiene que estar entre 0 y 60 %."
        else -> null
    }

    companion object {
        /** Plazos que se ofrecen en la app. La base de datos admite de 2 a 48. */
        val commonMonths = listOf(3, 6, 9, 12)

        /** Cuota mensual de una compra de [principal] (en positivo), sistema francés. */
        fun payment(principal: Long, months: Int, rate: Double): Long {
            if (months <= 0 || principal <= 0) return 0
            val r = rate / 1200
            val p = principal.toDouble()
            return Math.round(if (r == 0.0) p / months else p * r / (1 - (1 + r).pow(-months.toDouble())))
        }
    }
}

/** Un cargo de la tarjeta en la cuenta de pago. */
data class CardPayment(
    val due: LocalDate,
    val statement: LocalDate,
    val amount: Long,
    /** Compras normales del ciclo (todo a fin de mes) o cuota de la deuda (revolving), con intereses. */
    val purchases: Long,
    val installments: Long,
    /** Intereses incluidos en [amount] (del revolving y de los aplazados). */
    val interest: Long,
    /** El ciclo aún está abierto: el importe puede subir con nuevas compras. */
    val isEstimate: Boolean,
)

data class Payoff(val months: Int, val interest: Long)

/** Lo que hay que saber de una tarjeta hoy. */
data class CreditCardSummary(
    val terms: CreditCardTerms,
    val today: LocalDate,
    /** Deuda total de la tarjeta (en positivo): lo que resta del límite. */
    val used: Long,
    val available: Long,
    val usedFraction: Double,
    val openStatement: LocalDate,
    val spentThisCycle: Long,
    /** Próximos cargos, el primero es el siguiente. */
    val payments: List<CardPayment>,
    /** Deuda con intereses que queda tras el último extracto cerrado, sin los aplazados. */
    val revolvingBalance: Long,
    val interestInPayments: Long,
    /** Sin compras nuevas: meses hasta pagar la deuda. Nulo si no hay deuda o la cuota no cubre los intereses. */
    val payoff: Payoff?,
) {
    val next: CardPayment? get() = payments.firstOrNull()
    val isOverAlert: Boolean get() = terms.alertPercent != null && usedFraction * 100 >= terms.alertPercent
}

object CreditCardCalculator {
    /**
     * @param balance saldo actual de la cuenta de la tarjeta (negativo = se debe).
     * @param transferCategories categorías de tipo transferencia: un positivo con una de ellas es un pago de la tarjeta.
     */
    fun summary(
        terms: CreditCardTerms, balance: Long, movements: List<Movement>, installments: List<CardInstallment>,
        transferCategories: Set<String>, today: LocalDate, count: Int = 6,
    ): CreditCardSummary {
        val total = max(count, 1)
        val mine = movements.filter { it.accountId == terms.accountId }
        val byId = mine.reversed().associateBy { it.id }
        val plans = installments.filter { it.accountId == terms.accountId }.mapNotNull { plan ->
            byId[plan.movementId]?.takeIf { it.amountMinor < 0 }?.let { plan to it }
        }
        val deferred = plans.map { it.second.id }.toSet()
        // Compras normales y devoluciones, sin pagos de la tarjeta ni compras aplazadas.
        val charges = mine.filter { it.id !in deferred && !isCardPayment(it, transferCategories) }

        val used = max(0, -balance)
        val openStatement = terms.statementClosing(today)
        val lastClosed = openStatement.minusMonths(1)

        fun chargesIn(closing: LocalDate): Long {
            val start = terms.cycleStart(closing)
            return -charges.filter { !it.day.isBefore(start) && it.day.isBefore(closing) }.sumOf { it.amountMinor }
        }
        val spentThisCycle = chargesIn(openStatement)

        /** Cuota e intereses de los aplazados que caen en un extracto. */
        fun installmentsDue(statement: LocalDate): Pair<Long, Long> {
            var sum = 0L
            var interest = 0L
            for ((plan, movement) in plans) {
                val index = monthsBetween(terms.statementClosing(movement.day), statement)
                if (index < 0 || index >= plan.months) continue
                val row = amortization(-movement.amountMinor, plan.months, plan.rate)[index]
                sum += row.payment
                interest += row.interest
            }
            return sum to interest
        }

        // Extractos cuyo cargo aún no ha pasado, del más antiguo al más nuevo.
        var closing = lastClosed
        while (!terms.paymentDate(closing).isBefore(today)) closing = closing.minusMonths(1)
        closing = closing.plusMonths(1)
        val statements = (0 until total).map { closing.plusMonths(it.toLong()) }

        // Capital de los aplazados cuyas cuotas aún no se han cobrado: se pagan aparte, en su cuota.
        val firstUnpaid = statements[0]
        val deferredPending = plans.sumOf { (plan, movement) ->
            val paid = max(0, min(plan.months, monthsBetween(terms.statementClosing(movement.day), firstUnpaid)))
            amortization(-movement.amountMinor, plan.months, plan.rate).drop(paid).sumOf { it.principal }
        }

        // Deuda con intereses: lo que se debe menos lo que aún no ha entrado en un extracto.
        val unbilled = statements.filter { !it.isBefore(openStatement) }.sumOf { chargesIn(it) }
        var revolving = max(0, used - unbilled - deferredPending)
        val revolvingAtStart = revolving
        val payments = statements.map { statement ->
            val (fees, feeInterest) = installmentsDue(statement)
            val estimate = !statement.isBefore(openStatement)
            if (!terms.paymentMode.isRevolving) {
                val normal = if (statement.isAfter(openStatement)) 0 else max(0, chargesIn(statement))
                CardPayment(terms.paymentDate(statement), statement, normal + fees, normal, fees, feeInterest, estimate)
            } else {
                // El capital de los extractos ya cerrados está en `revolving`; los abiertos se van sumando.
                if (estimate) revolving += max(0, chargesIn(statement))
                val step = revolvingStep(revolving, terms)
                revolving = step.remaining
                CardPayment(terms.paymentDate(statement), statement, step.payment + fees, step.payment, fees, step.interest + feeInterest, estimate)
            }
        }

        var payoff: Payoff? = null
        if (terms.paymentMode.isRevolving && revolvingAtStart + spentThisCycle > 0) {
            var capital = revolvingAtStart + max(0, spentThisCycle)
            var interest = 0L
            var months = 0
            while (capital > 0 && months < MAX_PAYOFF) {
                val step = revolvingStep(capital, terms)
                if (step.payment <= step.interest && step.remaining >= capital) {
                    months = MAX_PAYOFF
                    break
                }
                interest += step.interest
                capital = step.remaining
                months++
            }
            if (months < MAX_PAYOFF) payoff = Payoff(months, interest)
        }

        return CreditCardSummary(
            terms, today, used, terms.creditLimit - used, used.toDouble() / max(terms.creditLimit, 1), openStatement, spentThisCycle,
            payments, revolvingAtStart, payments.sumOf { it.interest }, payoff,
        )
    }

    /** Cuántas cuotas de un aplazado quedan por cobrar. */
    fun remainingInstallments(plan: CardInstallment, movement: Movement, summary: CreditCardSummary): Int {
        val firstUnpaid = summary.next?.statement ?: return plan.months
        val paid = monthsBetween(summary.terms.statementClosing(movement.day), firstUnpaid)
        return plan.months - paid.coerceIn(0, plan.months)
    }

    fun isCardPayment(movement: Movement, transferCategories: Set<String>): Boolean =
        movement.amountMinor >= 0 && movement.categoryId != null && movement.categoryId in transferCategories

    internal data class Step(val payment: Long, val interest: Long, val remaining: Long)

    /**
     * Un mes de revolving: intereses del capital (TIN/12) y la cuota que toca.
     * Pago mínimo = máx(% del capital + intereses, mínimo). Cuota fija = la cuota, sin bajar del mínimo.
     * Ninguno pasa de lo que se debe.
     */
    internal fun revolvingStep(capital: Long, terms: CreditCardTerms): Step {
        if (capital <= 0) return Step(0, 0, 0)
        val interest = Math.round(capital.toDouble() * terms.revolvingRate / 1200)
        val owed = capital + interest
        val percent = Math.round(capital.toDouble() * terms.minPaymentPercent / 100)
        val minimum = max(percent + interest, terms.minPayment)
        val wanted = if (terms.paymentMode == CardPaymentMode.Fixed) max(terms.fixedPayment ?: 0, minimum) else minimum
        val payment = min(wanted, owed)
        return Step(payment, interest, owed - payment)
    }

    internal data class Row(val payment: Long, val interest: Long, val principal: Long)

    /** Cuotas de un aplazado: la última ajusta el redondeo para que el capital cuadre. */
    internal fun amortization(principal: Long, months: Int, rate: Double): List<Row> {
        val quota = CardInstallment.payment(principal, months, rate)
        val r = rate / 1200
        var remaining = principal
        return List(months) { index ->
            val interest = Math.round(remaining.toDouble() * r)
            val part = if (index == months - 1) remaining else min(remaining, quota - interest)
            remaining -= part
            Row(part + interest, interest, part)
        }
    }

    private fun monthsBetween(from: LocalDate, to: LocalDate): Int =
        ChronoUnit.MONTHS.between(YearMonth.from(from), YearMonth.from(to)).toInt()

    private const val MAX_PAYOFF = 600
}

/** Tarjeta con lo que hace falta para sus avisos. */
data class CardReminder(val summary: CreditCardSummary, val name: String, val payFromBalance: Long?)

object CardAlerts {
    /** Prefijo de los avisos de cargos de tarjeta. */
    const val PREFIX = "stm.card."

    private val MESES = listOf("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre")

    /** Aviso antes de cada cargo con importe. */
    fun plan(cards: List<CardReminder>, today: LocalDate, limit: Int = 10, hour: Int = 9): List<PlannedReminder> {
        val result = mutableListOf<PlannedReminder>()
        for (card in cards) {
            val before = card.summary.terms.remindDaysBefore ?: continue
            for (payment in card.summary.payments.take(3)) {
                if (payment.amount <= 0) continue
                val fire = payment.due.minusDays(before.toLong())
                if (fire.isBefore(today)) continue
                val cuando = when (before) {
                    0 -> "Hoy"
                    1 -> "Mañana"
                    else -> "En $before días"
                }
                var body = "Se cobran ${Money.format(payment.amount)} el ${payment.due.dayOfMonth} de ${MESES[payment.due.monthValue - 1]}"
                body += if (payment.isEstimate) " (de momento; puede subir con nuevas compras)." else "."
                if (card.payFromBalance != null && card.payFromBalance < payment.amount) {
                    body += " En la cuenta de pago sólo hay ${Money.format(card.payFromBalance)}."
                }
                result += PlannedReminder("$PREFIX${card.summary.terms.accountId}.${payment.due}", fire.toString(), hour, "$cuando: cargo de ${card.name}", body)
            }
        }
        return result.sortedWith(compareBy({ it.fireOn }, { it.id })).take(limit)
    }

    /** Aviso inmediato al pasar del % del límite de una tarjeta; uno por extracto. */
    fun limitAlert(summary: CreditCardSummary, name: String): BudgetAlert? {
        val percent = summary.terms.alertPercent
        if (!summary.isOverAlert || percent == null) return null
        return BudgetAlert(
            "stm.budget.card.${summary.openStatement}.${summary.terms.accountId}",
            "$name: has usado el ${Math.round(summary.usedFraction * 100)} % del límite",
            "Te quedan ${Money.format(summary.available)} de ${Money.format(summary.terms.creditLimit)}. El aviso salta al $percent %.",
        )
    }
}
