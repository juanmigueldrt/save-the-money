package com.savethemoney.android.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

/**
 * Una llamada a una función `create_…` o `update_…` del servidor (ORC-142): su nombre y sus parámetros. Las claves tienen
 * que ser exactamente los nombres de los parámetros de la función: PostgREST no encuentra la función si sobra o falta
 * alguno sin valor por defecto.
 */
internal class RpcCall(val function: String, val params: JsonObject)

/**
 * Lo que manda la app a cada función de alta y de cambio. Aparte de [SupabaseFinance] para poder probarlo sin red:
 * RpcEscriturasTest compara las claves con `testdata/vectors/rpc_escrituras.json`, el mismo fichero que usa
 * `supabase/tests/api/escrituras_idempotentes.py` contra el PostgREST local.
 *
 * Los parámetros van todos, también los nulos: las funciones de cambio no tienen valores por defecto. Un alta que llega
 * sin id (quien llama no es un formulario que vaya a reintentar) recibe uno nuevo.
 */
internal object RpcEscrituras {
    private fun newId() = java.util.UUID.randomUUID().toString()

    /** Los parámetros comunes más uno: el hogar al dar de alta, la versión leída al cambiar. */
    private fun JsonObject.with(key: String, value: String?) = JsonObject(this + (key to JsonPrimitive(value)))

    fun createAccount(draft: AccountDraft, householdId: String) = RpcCall(
        "create_account",
        buildJsonObject {
            put("account", draft.id)
            put("household", householdId)
            put("label", draft.trimmedName)
            put("account_kind", Json.encodeToJsonElement(draft.kind))
            put("opening", draft.openingMinor)
            put("owner", draft.ownerId)
        },
    )

    fun updateAccount(account: Account) = RpcCall(
        "update_account",
        buildJsonObject {
            put("account", account.id)
            put("seen", account.updatedAt)
            put("label", account.name.trim())
            put("account_kind", Json.encodeToJsonElement(account.kind))
            put("opening", account.openingMinor)
            put("owner", account.ownerId)
            put("archived", account.archivedAt)
            put("make_default", account.isDefault && !account.isArchived)
            put("in_net_worth", account.includeInNetWorth)
        },
    )

    /** El grupo del 50/30/20 solo va en los gastos. */
    private fun BudgetCategory.group() = if (kind == CategoryKind.Expense) budgetGroup else null

    fun createCategory(category: BudgetCategory) = RpcCall(
        "create_category",
        buildJsonObject {
            put("category", category.id.ifEmpty(::newId))
            put("household", category.householdId)
            put("label", category.trimmedName)
            put("category_kind", Json.encodeToJsonElement(category.kind))
            put("budget", Json.encodeToJsonElement(category.group()))
            put("icon_name", category.icon)
        },
    )

    /** Solo nombre, grupo e icono: el tipo de una categoría no se cambia. */
    fun updateCategory(category: BudgetCategory) = RpcCall(
        "update_category",
        buildJsonObject {
            put("category", category.id)
            put("seen", category.updatedAt)
            put("label", category.trimmedName)
            put("budget", Json.encodeToJsonElement(category.group()))
            put("icon_name", category.icon)
        },
    )

    /** Sin versión es uno nuevo (create_extra_budget); con versión, un cambio (update_extra_budget). */
    fun saveExtraBudget(budget: ExtraBudget) = RpcCall(
        if (budget.updatedAt == null) "create_extra_budget" else "update_extra_budget",
        buildJsonObject {
            put("budget", budget.id)
            put("label", budget.trimmedName)
            put("cap", budget.limit)
            put("starts", budget.startsOn.toString())
            put("ends", budget.endsOn?.toString())
            putJsonArray("category_list") { budget.categoryIds.forEach { add(JsonPrimitive(it)) } }
            putJsonArray("account_list") { budget.accountIds.forEach { add(JsonPrimitive(it)) } }
            put("favorite", budget.isFavorite)
            if (budget.updatedAt == null) put("household", budget.householdId) else put("seen", budget.updatedAt)
        },
    )

    /**
     * Lo que comparten create_recurring_series y update_recurring_series. Sin `pendingFrom`, el servidor pone hoy al crear y
     * deja el que había al cambiar.
     */
    private fun RecurringSeries.params() = buildJsonObject {
        put("series", id)
        put("label", trimmedName)
        put("series_kind", RECURRING_KIND.getValue(kind))
        put("amount", amountMinor)
        put("account", accountId)
        put("category", categoryId)
        put("step", every)
        put("step_unit", unit.name.lowercase())
        put("starts", startsOn)
        put("ends", endsOn)
        put("remind_days", remindDaysBefore)
        put("archived", archivedAt)
        put("intro_amount", introMinor)
        put("intro_count", introCharges)
        put("pending", createsPending)
        put("pending_start", pendingFrom)
    }

    fun createRecurring(series: RecurringSeries) =
        RpcCall("create_recurring_series", series.copy(id = series.id.ifEmpty(::newId)).params().with("household", series.householdId))

    fun updateRecurring(series: RecurringSeries) = RpcCall("update_recurring_series", series.params().with("seen", series.updatedAt))

    fun updateCharge(charge: RecurringCharge, status: ChargeStatus, transactionId: String?) = RpcCall(
        "update_recurring_charge",
        buildJsonObject {
            put("charge", charge.id)
            put("seen", charge.updatedAt)
            put("new_status", status.name.lowercase())
            put("movement", if (status == ChargeStatus.Pending) null else transactionId)
        },
    )

    /** Lo que comparten create_goal y update_goal. */
    private fun Goal.params() = buildJsonObject {
        put("goal", id)
        put("label", trimmedName)
        put("goal_kind", kind.name.lowercase())
        put("target", targetMinor)
        put("starting", startingMinor)
        put("monthly_plan", monthlyPlanMinor)
        put("due", targetOn)
        put("account", accountId)
        put("icon_name", icon)
        put("completed", completedAt)
        put("archived", archivedAt)
    }

    fun createGoal(goal: Goal) = RpcCall("create_goal", goal.copy(id = goal.id.ifEmpty(::newId)).params().with("household", goal.householdId))

    fun updateGoal(goal: Goal) = RpcCall("update_goal", goal.params().with("seen", goal.updatedAt))

    fun addContribution(contribution: GoalContribution) = RpcCall(
        "create_goal_contribution",
        buildJsonObject {
            put("contribution", contribution.id.ifEmpty(::newId))
            put("household", contribution.householdId)
            put("goal", contribution.goalId)
            put("amount", contribution.amountMinor)
            put("made", contribution.madeOn)
            put("remark", contribution.note)
        },
    )

    /** Lo que comparten create_credit_card y update_credit_card. */
    private fun CreditCardTerms.params() = buildJsonObject {
        put("card", accountId)
        put("credit_limit", creditLimit)
        put("statement", statementDay)
        put("payment", paymentDay)
        put("delay_months", paymentDelayMonths)
        put("mode", paymentMode.name.lowercase())
        put("fixed_payment", fixedPayment)
        put("min_percent", minPaymentPercent)
        put("min_payment", minPayment)
        put("revolving", revolvingRate)
        put("installments", installmentRate)
        put("pay_from", payFromAccountId)
        put("remind_days", remindDaysBefore)
        put("alert", alertPercent)
    }

    /** Sin versión son condiciones nuevas (create_credit_card); con versión, un cambio (update_credit_card). */
    fun saveCreditCard(terms: CreditCardTerms) =
        if (terms.updatedAt == null) {
            RpcCall("create_credit_card", terms.params().with("household", terms.householdId))
        } else {
            RpcCall("update_credit_card", terms.params().with("seen", terms.updatedAt))
        }

    /** Sin versión es un aplazado nuevo (create_card_installment); con versión, un cambio (update_card_installment). */
    fun saveInstallment(installment: CardInstallment) = RpcCall(
        if (installment.updatedAt == null) "create_card_installment" else "update_card_installment",
        buildJsonObject {
            put("installment", installment.id.ifEmpty(::newId))
            put("plan_months", installment.months)
            put("plan_rate", installment.rate)
            if (installment.updatedAt == null) {
                put("household", installment.householdId)
                put("card", installment.accountId)
                put("movement", installment.movementId)
            } else {
                put("seen", installment.updatedAt)
            }
        },
    )

    /** Lo que comparten create_holding y update_holding. La moneda no va: la pone el servidor al crear. */
    private fun Holding.params() = buildJsonObject {
        put("holding", id)
        put("label", trimmedName)
        put("ticker", trimmedSymbol)
        put("holding_kind", Json.encodeToJsonElement(kind))
        put("asset", Json.encodeToJsonElement(assetClass))
        put("account", accountId)
        put("owner", ownerId)
        put("unit_price", price.toPlainString())
        put("priced", priceOn)
        put("fee", feeRate.toPlainString())
        put("remark", note)
        put("archived", archivedAt)
    }

    fun createHolding(holding: Holding) =
        RpcCall("create_holding", holding.copy(id = holding.id.ifEmpty(::newId)).params().with("household", holding.householdId))

    fun updateHolding(holding: Holding) = RpcCall("update_holding", holding.params().with("seen", holding.updatedAt))

    /** Lo que comparten create_investment_plan y update_investment_plan. El activo de un plan no se cambia. */
    private fun InvestmentPlan.params() = buildJsonObject {
        put("plan", id)
        put("account", accountId)
        put("amount", amountMinor)
        put("step", every)
        put("step_unit", Json.encodeToJsonElement(unit))
        put("starts", startsOn)
        put("ends", endsOn)
        put("annual_return", expectedAnnualReturn.toPlainString())
        put("remind_days", remindDaysBefore)
        put("paused", pausedAt)
        put("archived", archivedAt)
    }

    fun createPlan(plan: InvestmentPlan) = RpcCall(
        "create_investment_plan",
        plan.copy(id = plan.id.ifEmpty(::newId)).params().with("household", plan.householdId).with("holding", plan.holdingId),
    )

    fun updatePlan(plan: InvestmentPlan) = RpcCall("update_investment_plan", plan.params().with("seen", plan.updatedAt))
}
