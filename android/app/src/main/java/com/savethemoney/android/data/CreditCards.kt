package com.savethemoney.android.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.ChronoUnit
import kotlin.math.max
import kotlin.math.min

// CreditCards.swift de STMCore: condiciones, compras aplazadas y cuánto se paga cada mes.
// Los tipos de interés se guardan en Double (numeric(5, 2) en la base de datos) y las cuentas se hacen
// con BigDecimal, como Decimal en iOS; los importes, siempre en céntimos.

/**
 * El tipo tal como se escribió: `BigDecimal.valueOf` usa el decimal más corto que da ese Double
 * (14.99 → 14.99, no 14.9900000000000002131628…). Exacto para tipos de hasta 15 cifras.
 */
internal fun Double.exact(): BigDecimal = BigDecimal.valueOf(this)

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
    /**
     * Versión de la fila: el `updated_at` del servidor tal cual llegó (como [Movement.updatedAt]). Nulo en unas condiciones
     * que aún no se han guardado: guardarlas es un alta.
     */
    @SerialName("updated_at") val updatedAt: String? = null,
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
    /**
     * Versión de la fila: el `updated_at` del servidor tal cual llegó (como [Movement.updatedAt]). Nulo en un aplazado que
     * aún no se ha guardado: guardarlo es un alta.
     */
    @SerialName("updated_at") val updatedAt: String? = null,
) {
    val issue: String? get() = when {
        months !in 2..48 -> "Se puede aplazar de 2 a 48 meses."
        rate < 0 || rate > 60 -> "El interés tiene que estar entre 0 y 60 %."
        else -> null
    }

    companion object {
        /** Plazos que se ofrecen en la app. La base de datos admite de 2 a 48. */
        val commonMonths = listOf(3, 6, 9, 12)

        /**
         * Cuota mensual de una compra de [principal] (en positivo), sistema francés:
         * P·r/(1 − (1 + r)^−n) = P·r·(1 + r)^n/((1 + r)^n − 1), con r = TIN/1200.
         * Con BigDecimal a [INTEREST_SCALE] decimales y la cuota al céntimo, mitad hacia arriba (igual en iOS).
         */
        fun payment(principal: Long, months: Int, rate: Double): Long {
            if (months <= 0 || principal <= 0) return 0
            val p = BigDecimal(principal)
            val tin = rate.exact()
            if (tin.signum() == 0) return p.divide(BigDecimal(months), 0, RoundingMode.HALF_UP).toLong()
            val r = tin.divide(BigDecimal(1200), INTEREST_SCALE, RoundingMode.HALF_UP)
            var growth = BigDecimal.ONE
            repeat(months) { growth = growth.timesRounded(BigDecimal.ONE + r) }
            val factor = r.timesRounded(growth).divide(growth - BigDecimal.ONE, INTEREST_SCALE, RoundingMode.HALF_UP)
            return p.multiply(factor).setScale(0, RoundingMode.HALF_UP).toLong()
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
    /**
     * Aplazados cuya compra no está entre los movimientos recibidos. Sin la compra no se sabe ni la cuota ni el
     * capital: no salen en [payments] y su deuda queda dentro de [revolvingBalance]. Si no está vacío, las cifras
     * de la tarjeta no son de fiar.
     */
    val unresolvedInstallments: List<String>,
    /**
     * Abonos sin categoría de los extractos sin cobrar: no se sabe si son un pago de la tarjeta o una devolución.
     * Hasta que se clasifiquen cuentan como un pago: bajan la deuda, pero no los cargos. Si no está vacío, hay que
     * pedir que se les ponga categoría.
     */
    val uncategorizedCredits: List<String>,
    /**
     * Los movimientos de los extractos sin cobrar no se han podido cargar todos (hay más que el tope de una petición):
     * los cargos, lo gastado en el ciclo y la deuda con intereses pueden salir más bajos de lo que son.
     */
    val movementsTruncated: Boolean = false,
) {
    val next: CardPayment? get() = payments.firstOrNull()
    val isOverAlert: Boolean get() = terms.alertPercent != null && usedFraction * 100 >= terms.alertPercent
}

object CreditCardCalculator {
    /**
     * Extracto (día en que se cierra) más antiguo cuyo cargo aún no ha pasado. Para calcular la tarjeta hacen falta todos
     * sus movimientos desde [CreditCardTerms.cycleStart] de este extracto.
     */
    fun firstUnpaidStatement(terms: CreditCardTerms, today: LocalDate): LocalDate {
        var closing = terms.statementClosing(today).minusMonths(1)
        while (!terms.paymentDate(closing).isBefore(today)) closing = closing.minusMonths(1)
        return closing.plusMonths(1)
    }

    /**
     * @param balance saldo actual de la cuenta de la tarjeta (negativo = se debe).
     * @param movements movimientos de la tarjeta: los de los extractos sin cobrar y la compra de cada aplazado, por antigua que sea.
     * @param transferCategories categorías de tipo transferencia: un positivo con una de ellas es un pago de la tarjeta.
     */
    fun summary(
        terms: CreditCardTerms, balance: Long, movements: List<Movement>, installments: List<CardInstallment>,
        transferCategories: Set<String>, today: LocalDate, count: Int = 6,
    ): CreditCardSummary {
        val total = max(count, 1)
        val mine = movements.filter { it.accountId == terms.accountId }
        val byId = mine.reversed().associateBy { it.id }
        val own = installments.filter { it.accountId == terms.accountId }
        val plans = own.mapNotNull { plan ->
            byId[plan.movementId]?.takeIf { it.amountMinor < 0 }?.let { plan to it }
        }
        val unresolved = own.filter { it.movementId !in byId }.map { it.id }
        val deferred = plans.map { it.second.id }.toSet()
        // Compras normales y devoluciones, sin pagos de la tarjeta ni compras aplazadas.
        // Un abono sin categoría no es una devolución: si fuera el pago del extracto anterior, dejaría el cargo a 0.
        val credits = mine.filter { it.amountMinor > 0 && it.categoryId == null }
        val unclassified = credits.map { it.id }.toSet()
        val charges = mine.filter { it.id !in deferred && it.id !in unclassified && !isCardPayment(it, transferCategories) }

        val used = max(0, -balance)
        val openStatement = terms.statementClosing(today)

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
        val closing = firstUnpaidStatement(terms, today)
        val statements = (0 until total).map { closing.plusMonths(it.toLong()) }

        // Capital de los aplazados cuyas cuotas aún no se han cobrado: se pagan aparte, en su cuota.
        val firstUnpaid = statements[0]
        // Solo se avisa de los abonos que caen en un extracto sin cobrar: los anteriores ya no cambian ningún cargo.
        val firstStart = terms.cycleStart(firstUnpaid)
        val uncategorized = credits.filter { !it.day.isBefore(firstStart) }.map { it.id }
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
            payments, revolvingAtStart, payments.sumOf { it.interest }, payoff, unresolved, uncategorized,
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
        val interest = monthlyInterest(capital, terms.revolvingRate)
        val owed = capital + interest
        val percent = (BigDecimal(capital) * terms.minPaymentPercent.exact()).divide(BigDecimal(100), 0, RoundingMode.HALF_UP).toLong()
        val minimum = max(percent + interest, terms.minPayment)
        val wanted = if (terms.paymentMode == CardPaymentMode.Fixed) max(terms.fixedPayment ?: 0, minimum) else minimum
        val payment = min(wanted, owed)
        return Step(payment, interest, owed - payment)
    }

    internal data class Row(val payment: Long, val interest: Long, val principal: Long)

    /** Intereses de un mes: capital × TIN / 1200, exactos y al céntimo, mitad hacia arriba. */
    internal fun monthlyInterest(capital: Long, rate: Double): Long =
        (BigDecimal(capital) * rate.exact()).divide(BigDecimal(1200), 0, RoundingMode.HALF_UP).toLong()

    /** Cuotas de un aplazado: la última ajusta el redondeo para que el capital cuadre. */
    internal fun amortization(principal: Long, months: Int, rate: Double): List<Row> {
        val quota = CardInstallment.payment(principal, months, rate)
        var remaining = principal
        return List(months) { index ->
            val interest = monthlyInterest(remaining, rate)
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

/** Tipo de compra al apuntar un gasto nuevo en una tarjeta: normal, a plazos o recurrente. */
sealed interface CardPurchase {
    data object Normal : CardPurchase
    data class Installments(val months: Int) : CardPurchase
    data class Recurring(val recurrence: Recurrence) : CardPurchase

    /** Cuota al mes, total e intereses de aplazar [principal] (en positivo). */
    data class Quote(val monthly: Long, val total: Long, val interest: Long)

    companion object {
        /** Muchos contratos sólo aplazan desde aquí; no se bloquea, sólo se avisa. */
        const val USUAL_MINIMUM = 5_000L
        const val DEFAULT_MONTHS = 3
        val MONTHS = 2..48

        fun quote(principal: Long, months: Int, rate: Double): Quote {
            val monthly = CardInstallment.payment(principal, months, rate)
            val total = monthly * months
            return Quote(monthly, total, maxOf(0, total - principal))
        }

        /** El aplazado del gasto recién guardado. Lleva el id de su movimiento (hay uno por compra): repetirlo no crea otro. */
        fun installment(movement: Movement, months: Int, rate: Double) =
            CardInstallment(movement.id, movement.householdId, movement.accountId, movement.id, months, rate)

        /**
         * El pago fijo del gasto recién guardado: empieza ese día y crea pendientes desde el día
         * siguiente, para que el cargo que ya está apuntado no salga además como pendiente. Lleva el id del
         * movimiento (que el formulario elige una vez): guardar otra vez el mismo formulario no crea otro pago fijo.
         */
        fun series(movement: Movement, recurrence: Recurrence) = RecurringSeries(
            movement.id, movement.householdId, movement.description.trim(), RecurringKind.Subscription, -movement.amountMinor,
            movement.accountId, movement.categoryId, recurrence.every, recurrence.unit, movement.day.toString(),
            createsPending = true, pendingFrom = movement.day.plusDays(1).toString(),
        )
    }
}
