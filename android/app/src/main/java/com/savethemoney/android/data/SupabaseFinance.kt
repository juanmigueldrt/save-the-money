package com.savethemoney.android.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.addJsonObject
import java.math.BigDecimal
import java.time.LocalDate
import java.time.YearMonth

/** Cuentas, categorías y movimientos sobre Supabase. El RLS del servidor decide qué se ve. */
class SupabaseFinance(private val backend: SupabaseBackend) : FinanceService {
    private val client get() = backend.client

    private fun fail(text: String): Nothing = throw AppError.InvalidInput(text)

    override suspend fun accounts(householdId: String): List<Account> = backend.mapped {
        client.from("accounts").select(Columns.raw(ACCOUNT)) {
            filter { eq("household_id", householdId) }
            order("created_at", Order.ASCENDING)
        }.decodeList()
    }

    override suspend fun balances(householdId: String): Map<String, Long> = backend.mapped {
        client.from("account_balances").select(Columns.raw("account_id,balance_minor")) {
            filter { eq("household_id", householdId) }
        }.decodeList<BalanceRow>().associate { it.accountId to it.balanceMinor }
    }

    override suspend fun createAccount(draft: AccountDraft, householdId: String): Account = backend.mapped {
        draft.issue?.let(::fail)
        client.from("accounts").insert(NewAccountRow(householdId, draft.trimmedName, draft.kind, draft.openingMinor, draft.ownerId)) {
            select(Columns.raw(ACCOUNT))
        }.decodeSingle()
    }

    override suspend fun updateAccount(account: Account): Account = backend.mapped {
        client.from("accounts").update(AccountChanges(
            account.name.trim(), account.kind, account.openingMinor, account.ownerId, account.archivedAt,
            account.isDefault && !account.isArchived, account.includeInNetWorth,
        )) {
            select(Columns.raw(ACCOUNT))
            filter { eq("id", account.id) }
        }.decodeSingle()
    }

    override suspend fun deleteAccount(accountId: String) = backend.mapped {
        client.from("accounts").delete { filter { eq("id", accountId) } }
        Unit
    }

    override suspend fun categories(householdId: String): List<BudgetCategory> = backend.mapped {
        client.from("categories").select(Columns.raw(CATEGORY)) {
            filter { eq("household_id", householdId) }
            order("name", Order.ASCENDING)
        }.decodeList()
    }

    private fun CategoryKind.groupOf(category: BudgetCategory) = if (this == CategoryKind.Expense) category.budgetGroup else null

    override suspend fun createCategory(category: BudgetCategory): BudgetCategory = backend.mapped {
        category.issue(emptyList())?.let(::fail)
        val row = NewCategoryRow(category.householdId, category.kind, category.trimmedName, category.kind.groupOf(category), category.icon)
        client.from("categories").insert(row) { select(Columns.raw(CATEGORY)) }.decodeSingle()
    }

    /** Solo nombre, grupo e icono: el tipo de una categoría no se cambia. */
    override suspend fun updateCategory(category: BudgetCategory): BudgetCategory = backend.mapped {
        category.issue(emptyList())?.let(::fail)
        client.from("categories").update(CategoryChanges(category.trimmedName, category.kind.groupOf(category), category.icon)) {
            select(Columns.raw(CATEGORY))
            filter { eq("id", category.id) }
        }.decodeSingle()
    }

    override suspend fun deleteCategory(categoryId: String) = backend.mapped {
        client.from("categories").delete { filter { eq("id", categoryId) } }
        Unit
    }

    override suspend fun movements(householdId: String, accountId: String?, limit: Int): List<Movement> = backend.mapped {
        client.from("transactions").select(Columns.raw(MOVEMENT)) {
            filter {
                eq("household_id", householdId)
                if (accountId != null) eq("account_id", accountId)
            }
            order("booked_on", Order.DESCENDING)
            order("created_at", Order.DESCENDING)
            limit(limit.toLong())
        }.decodeList()
    }

    override suspend fun movements(householdId: String, ids: List<String>): List<Movement> = backend.mapped {
        if (ids.isEmpty()) return@mapped emptyList()
        client.from("transactions").select(Columns.raw(MOVEMENT)) {
            filter {
                eq("household_id", householdId)
                isIn("id", ids)
            }
        }.decodeList()
    }

    override suspend fun movements(householdId: String, accountId: String, since: LocalDate, limit: Int): List<Movement> = backend.mapped {
        client.from("transactions").select(Columns.raw(MOVEMENT)) {
            filter {
                eq("household_id", householdId)
                eq("account_id", accountId)
                gte("booked_on", since.toString())
            }
            order("booked_on", Order.DESCENDING)
            order("created_at", Order.DESCENDING)
            limit(limit.toLong())
        }.decodeList()
    }

    override suspend fun addMovement(draft: MovementDraft, householdId: String): Movement = backend.mapped {
        draft.issue?.let(::fail)
        client.from("transactions").insert(NewMovementRow.of(draft, householdId)) { select(Columns.raw(MOVEMENT)) }.decodeSingle()
    }

    /** create_transfer guarda las dos patas en una sola transacción y no repite una ya guardada. */
    override suspend fun addTransfer(draft: TransferDraft, householdId: String): List<Movement> = backend.mapped {
        draft.issue?.let(::fail)
        val params = buildJsonObject {
            put("transfer", draft.id)
            put("household", householdId)
            put("from_account", draft.fromAccountId)
            put("to_account", draft.toAccountId)
            put("booked", draft.bookedOn.toString())
            put("amount", draft.amountMinor)
            put("category", draft.categoryId)
            put("from_label", draft.fromDescription.trim())
            put("to_label", draft.toDescription.trim())
            put("note", draft.notes)
            put("is_excluded", draft.excluded)
            put("payee_name", Payee.clean(draft.payee))
            putJsonArray("tag_list") { draft.tags.forEach { add(JsonPrimitive(it)) } }
        }
        client.postgrest.rpc("create_transfer", params) { select(Columns.raw(MOVEMENT)) }.decodeList()
    }

    override suspend fun updateMovement(movement: Movement): Movement = backend.mapped {
        movement.toDraft().issue?.let(::fail)
        val changes = MovementChanges(
            movement.accountId, movement.categoryId, movement.bookedOn, movement.amountMinor, movement.description.trim(), movement.notes,
            movement.excluded, movement.reviewedAt, Payee.clean(movement.payee), movement.tags,
        )
        client.from("transactions").update(changes) {
            select(Columns.raw(MOVEMENT))
            filter { eq("id", movement.id) }
        }.decodeSingle()
    }

    override suspend fun deleteMovement(movementId: String) = backend.mapped {
        client.from("transactions").delete { filter { eq("id", movementId) } }
        Unit
    }

    override suspend fun importMovements(drafts: List<MovementDraft>, householdId: String): ImportResult = backend.mapped {
        drafts.firstNotNullOfOrNull { it.issue }?.let(::fail)
        var inserted = 0
        for (batch in drafts.chunked(IMPORT_BATCH)) {
            // ON CONFLICT (account_id, import_hash) DO NOTHING: solo vuelven las filas nuevas.
            inserted += client.from("transactions").upsert(batch.map { NewMovementRow.of(it, householdId) }) {
                onConflict = "account_id,import_hash"
                ignoreDuplicates = true
                select(Columns.raw("id"))
            }.decodeList<IdRow>().size
        }
        ImportResult(inserted, drafts.size - inserted)
    }

    override suspend fun budget(householdId: String, startingOn: LocalDate): Budget? = backend.mapped {
        client.from("budgets").select(Columns.raw(BUDGET)) {
            filter {
                eq("household_id", householdId)
                eq("month", startingOn.toString())
            }
            limit(1)
        }.decodeList<BudgetRow>().firstOrNull()?.budget
    }

    override suspend fun latestBudget(householdId: String, before: LocalDate): Budget? = backend.mapped {
        client.from("budgets").select(Columns.raw(BUDGET)) {
            filter {
                eq("household_id", householdId)
                lt("month", before.toString())
            }
            order("month", Order.DESCENDING)
            limit(1)
        }.decodeList<BudgetRow>().firstOrNull()?.budget
    }

    /** save_period_budget hace presupuesto y límites en una sola transacción con los permisos de quien llama. */
    override suspend fun saveBudget(budget: Budget): Budget = backend.mapped {
        budget.issue?.let(::fail)
        client.postgrest.rpc("save_period_budget", buildJsonObject {
            put("target_household", budget.householdId)
            put("starts_on", budget.period.start.toString())
            put("ends_on", budget.period.end.toString())
            put("expected_income", budget.expectedIncome)
            put("needs", budget.template.needs)
            put("wants", budget.template.wants)
            put("savings", budget.template.savings)
            put("carry", budget.carryOver)
            put("warn", budget.warnPercent)
            putJsonArray("lines") {
                budget.limits.filterValues { it > 0 }.toSortedMap().forEach { (category, limit) ->
                    addJsonObject {
                        put("category_id", category)
                        put("limit_minor", limit)
                    }
                }
            }
        })
        budget(budget.householdId, budget.period.start) ?: budget
    }

    override suspend fun paySchedule(): PaySchedule? = backend.mapped {
        client.from("pay_schedules").select(Columns.raw("frequency,day1,day2,anchor_on")) { limit(1) }
            .decodeList<PayScheduleRow>().firstOrNull()?.schedule
    }

    override suspend fun savePaySchedule(schedule: PaySchedule): PaySchedule = backend.mapped {
        schedule.issue?.let(::fail)
        // La fila es de quien llama (user_id por defecto = auth.uid()). Los null van explícitos
        // para quitar el segundo día o la fecha al cambiar de frecuencia.
        client.from("pay_schedules").upsert(buildJsonObject {
            put("frequency", schedule.frequency.raw)
            put("day1", schedule.day1)
            put("day2", if (schedule.frequency == PayFrequency.TwiceMonthly) schedule.day2 else null)
            put("anchor_on", if (schedule.frequency.usesAnchor) schedule.anchor?.toString() else null)
        }) { onConflict = "user_id" }
        schedule
    }

    override suspend fun extraBudgets(householdId: String): List<ExtraBudget> = backend.mapped {
        client.from("extra_budgets").select(Columns.raw(EXTRA)) {
            filter { eq("household_id", householdId) }
            order("is_favorite", Order.DESCENDING)
            order("starts_on", Order.DESCENDING)
        }.decodeList<ExtraRow>().map { it.extra }
    }

    /** Se actualiza por id; si no había fila, se crea. */
    override suspend fun saveExtraBudget(budget: ExtraBudget): ExtraBudget = backend.mapped {
        budget.issue?.let(::fail)
        val changes = buildJsonObject {
            put("name", budget.trimmedName)
            put("limit_minor", budget.limit)
            put("starts_on", budget.startsOn.toString())
            put("ends_on", budget.endsOn?.toString())
            putJsonArray("category_ids") { budget.categoryIds.forEach { add(JsonPrimitive(it)) } }
            putJsonArray("account_ids") { budget.accountIds.forEach { add(JsonPrimitive(it)) } }
            put("is_favorite", budget.isFavorite)
        }
        client.from("extra_budgets").update(changes) {
            select(Columns.raw(EXTRA))
            filter { eq("id", budget.id) }
        }.decodeList<ExtraRow>().firstOrNull()?.extra
            ?: client.from("extra_budgets").insert(JsonObject(changes + mapOf("id" to JsonPrimitive(budget.id), "household_id" to JsonPrimitive(budget.householdId)))) {
                select(Columns.raw(EXTRA))
            }.decodeSingle<ExtraRow>().extra
    }

    override suspend fun deleteExtraBudget(id: String) = backend.mapped {
        client.from("extra_budgets").delete { filter { eq("id", id) } }
        Unit
    }

    /** El servidor devuelve como mucho 1000 filas por petición (max_rows): se pide por páginas. */
    override suspend fun resetHousehold(householdId: String) = backend.mapped<Unit> {
        client.postgrest.rpc("reset_household", buildJsonObject { put("target_household", householdId) })
    }

    override suspend fun movements(householdId: String, from: LocalDate, through: LocalDate): List<Movement> = backend.mapped {
        val all = mutableListOf<Movement>()
        while (true) {
            val start = all.size.toLong()
            val page = client.from("transactions").select(Columns.raw(MOVEMENT)) {
                filter {
                    eq("household_id", householdId)
                    gte("booked_on", from.toString())
                    lte("booked_on", through.toString())
                }
                order("booked_on", Order.DESCENDING)
                order("id", Order.ASCENDING)
                range(start, start + PAGE - 1)
            }.decodeList<Movement>()
            all += page
            if (page.size < PAGE) break
        }
        all
    }

    // MARK: pagos fijos y metas. household_id solo al insertar: el servidor no deja cambiarlo después.

    private fun withHousehold(columns: JsonObject, householdId: String) = JsonObject(columns + ("household_id" to JsonPrimitive(householdId)))

    override suspend fun recurringSeries(householdId: String): List<RecurringSeries> = backend.mapped {
        client.from("recurring_series").select(Columns.raw(SERIES)) {
            filter { eq("household_id", householdId) }
            order("name", Order.ASCENDING)
        }.decodeList()
    }

    override suspend fun createRecurring(series: RecurringSeries): RecurringSeries = backend.mapped {
        series.issue?.let(::fail)
        client.from("recurring_series").insert(withHousehold(series.columns(), series.householdId)) { select(Columns.raw(SERIES)) }.decodeSingle()
    }

    override suspend fun updateRecurring(series: RecurringSeries): RecurringSeries = backend.mapped {
        series.issue?.let(::fail)
        client.from("recurring_series").update(series.columns()) {
            select(Columns.raw(SERIES))
            filter { eq("id", series.id) }
        }.decodeSingle()
    }

    override suspend fun deleteRecurring(seriesId: String) = backend.mapped {
        client.from("recurring_series").delete { filter { eq("id", seriesId) } }
        Unit
    }

    // Cargos pendientes: de quien los crea; se borran con su serie (on delete cascade).

    override suspend fun recurringCharges(householdId: String): List<RecurringCharge> = backend.mapped {
        client.from("recurring_charges").select(Columns.raw(CHARGE)) {
            filter { eq("household_id", householdId) }
            order("due_on", Order.DESCENDING)
            limit(500)
        }.decodeList()
    }

    override suspend fun createCharges(charges: List<RecurringCharge>): List<RecurringCharge> {
        if (charges.isEmpty()) return emptyList()
        return backend.mapped {
            // ON CONFLICT (series_id, due_on) DO NOTHING: si otro dispositivo ya lo creó, no vuelve.
            client.from("recurring_charges").upsert(charges.map { NewChargeRow(it.householdId, it.seriesId, it.dueOn, it.amountMinor) }) {
                onConflict = "series_id,due_on"
                ignoreDuplicates = true
                select(Columns.raw(CHARGE))
            }.decodeList()
        }
    }

    /** confirm_recurring_charge crea el movimiento y enlaza el cargo en una sola transacción. */
    override suspend fun confirmCharge(chargeId: String, draft: MovementDraft): Movement = backend.mapped {
        draft.issue?.let(::fail)
        val movementId = client.postgrest.rpc("confirm_recurring_charge", buildJsonObject {
            put("charge", chargeId)
            put("account", draft.accountId)
            put("booked", draft.bookedOn.toString())
            put("amount", draft.amountMinor)
            put("category", draft.categoryId)
            put("label", draft.description.trim())
        }).decodeAs<String>()
        client.from("transactions").select(Columns.raw(MOVEMENT)) { filter { eq("id", movementId) } }.decodeSingle()
    }

    override suspend fun updateCharge(chargeId: String, status: ChargeStatus, transactionId: String?) = backend.mapped {
        client.from("recurring_charges").update(buildJsonObject {
            put("status", status.name.lowercase())
            put("transaction_id", if (status == ChargeStatus.Pending) null else transactionId)
        }) { filter { eq("id", chargeId) } }
        Unit
    }

    override suspend fun goals(householdId: String): List<Goal> = backend.mapped {
        client.from("goals").select(Columns.raw(GOAL)) {
            filter { eq("household_id", householdId) }
            order("created_at", Order.ASCENDING)
        }.decodeList()
    }

    override suspend fun createGoal(goal: Goal): Goal = backend.mapped {
        goal.issue?.let(::fail)
        client.from("goals").insert(withHousehold(goal.columns(), goal.householdId)) { select(Columns.raw(GOAL)) }.decodeSingle()
    }

    override suspend fun updateGoal(goal: Goal): Goal = backend.mapped {
        goal.issue?.let(::fail)
        client.from("goals").update(goal.columns()) {
            select(Columns.raw(GOAL))
            filter { eq("id", goal.id) }
        }.decodeSingle()
    }

    override suspend fun deleteGoal(goalId: String) = backend.mapped {
        client.from("goals").delete { filter { eq("id", goalId) } }
        Unit
    }

    override suspend fun contributions(householdId: String): List<GoalContribution> = backend.mapped {
        client.from("goal_contributions").select(Columns.raw(CONTRIBUTION)) {
            filter { eq("household_id", householdId) }
            order("made_on", Order.DESCENDING)
        }.decodeList()
    }

    override suspend fun addContribution(contribution: GoalContribution): GoalContribution = backend.mapped {
        contribution.issue?.let(::fail)
        val row = buildJsonObject {
            put("household_id", contribution.householdId)
            put("goal_id", contribution.goalId)
            put("amount_minor", contribution.amountMinor)
            put("made_on", contribution.madeOn)
            put("note", contribution.note)
        }
        client.from("goal_contributions").insert(row) { select(Columns.raw(CONTRIBUTION)) }.decodeSingle()
    }

    override suspend fun creditCards(householdId: String): List<CreditCardTerms> = backend.mapped {
        client.from("credit_cards").select(Columns.raw(CARD)) { filter { eq("household_id", householdId) } }.decodeList()
    }

    // No se usa upsert: haría UPDATE de la cuenta y el hogar, que no se pueden cambiar.
    override suspend fun saveCreditCard(terms: CreditCardTerms): CreditCardTerms = backend.mapped {
        terms.issue?.let(::fail)
        client.from("credit_cards").update(terms.columns()) {
            select(Columns.raw(CARD))
            filter { eq("account_id", terms.accountId) }
        }.decodeList<CreditCardTerms>().firstOrNull()
            ?: client.from("credit_cards").insert(
                JsonObject(terms.columns() + mapOf("account_id" to JsonPrimitive(terms.accountId), "household_id" to JsonPrimitive(terms.householdId))),
            ) { select(Columns.raw(CARD)) }.decodeSingle()
    }

    override suspend fun cardInstallments(householdId: String): List<CardInstallment> = backend.mapped {
        client.from("card_installments").select(Columns.raw(INSTALLMENT)) { filter { eq("household_id", householdId) } }.decodeList()
    }

    override suspend fun saveInstallment(installment: CardInstallment): CardInstallment = backend.mapped {
        installment.issue?.let(::fail)
        val changes = buildJsonObject {
            put("months", installment.months)
            put("rate", installment.rate)
        }
        client.from("card_installments").update(changes) {
            select(Columns.raw(INSTALLMENT))
            filter { eq("transaction_id", installment.movementId) }
        }.decodeList<CardInstallment>().firstOrNull()
            ?: client.from("card_installments").insert(
                JsonObject(
                    changes + mapOf(
                        "household_id" to JsonPrimitive(installment.householdId),
                        "account_id" to JsonPrimitive(installment.accountId),
                        "transaction_id" to JsonPrimitive(installment.movementId),
                    ),
                ),
            ) { select(Columns.raw(INSTALLMENT)) }.decodeSingle()
    }

    override suspend fun creditScores(): List<CreditScore> = backend.mapped {
        client.from("credit_scores").select(Columns.raw(SCORE)) {
            order("recorded_on", Order.DESCENDING)
            order("created_at", Order.DESCENDING)
        }.decodeList()
    }

    override suspend fun addCreditScore(score: CreditScore): CreditScore = backend.mapped {
        score.issue?.let(::fail)
        val row = buildJsonObject {
            put("score", score.score)
            put("max_score", score.maxScore)
            put("provider", score.trimmedProvider)
            put("recorded_on", score.recordedOn)
            put("note", score.note?.trim()?.ifEmpty { null })
        }
        client.from("credit_scores").insert(row) { select(Columns.raw(SCORE)) }.decodeSingle()
    }

    override suspend fun deleteCreditScore(scoreId: String) = backend.mapped {
        client.from("credit_scores").delete { filter { eq("id", scoreId) } }
        Unit
    }

    override suspend fun deleteInstallment(installmentId: String) = backend.mapped {
        client.from("card_installments").delete { filter { eq("id", installmentId) } }
        Unit
    }

    override suspend fun deleteContribution(contributionId: String) = backend.mapped {
        client.from("goal_contributions").delete { filter { eq("id", contributionId) } }
        Unit
    }

    override suspend fun holdings(householdId: String): List<Holding> = backend.mapped {
        client.from("holdings").select(Columns.raw(HOLDING)) {
            filter { eq("household_id", householdId) }
            order("name", Order.ASCENDING)
        }.decodeList()
    }

    private fun Holding.columns() = buildJsonObject {
        put("name", trimmedName)
        put("symbol", trimmedSymbol)
        put("kind", Json.encodeToJsonElement(kind))
        put("asset_class", Json.encodeToJsonElement(assetClass))
        put("account_id", accountId)
        put("owner_id", ownerId)
        put("price", price.toPlainString())
        put("price_on", priceOn)
        put("fee_rate", feeRate.toPlainString())
        put("note", note)
        put("archived_at", archivedAt)
    }

    override suspend fun createHolding(holding: Holding): Holding = backend.mapped {
        holding.issue?.let(::fail)
        val row = JsonObject(holding.columns() + ("household_id" to JsonPrimitive(holding.householdId)))
        client.from("holdings").insert(row) { select(Columns.raw(HOLDING)) }.decodeSingle()
    }

    override suspend fun updateHolding(holding: Holding): Holding = backend.mapped {
        holding.issue?.let(::fail)
        client.from("holdings").update(holding.columns()) {
            select(Columns.raw(HOLDING))
            filter { eq("id", holding.id) }
        }.decodeSingle()
    }

    override suspend fun deleteHolding(holdingId: String) = backend.mapped<Unit> {
        client.from("holdings").delete { filter { eq("id", holdingId) } }
    }

    override suspend fun holdingPrices(householdId: String): List<HoldingPrice> =
        allRows("holding_prices", PRICE, householdId, "priced_on")

    /** record_holding_price apunta el precio del día y el precio actual del activo en una sola transacción. */
    override suspend fun recordPrice(price: BigDecimal, day: LocalDate, holdingId: String): Holding = backend.mapped {
        if (price.signum() < 0) fail("El precio no puede ser negativo.")
        val params = buildJsonObject {
            put("holding", holdingId)
            put("priced", day.toString())
            put("new_price", price.toPlainString())
        }
        client.postgrest.rpc("record_holding_price", params) { select(Columns.raw(HOLDING)) }.decodeList<Holding>().first()
    }

    override suspend fun trades(householdId: String): List<InvestmentTrade> =
        allRows("investment_trades", TRADE, householdId, "traded_on")

    /**
     * create_trade guarda la operación y su movimiento en una sola transacción y no repite una ya guardada.
     * Que haya participaciones para vender lo comprueba el servidor, con todas las operaciones del activo.
     */
    override suspend fun addTrade(trade: InvestmentTrade, cash: TradeCash?): InvestmentTrade = backend.mapped {
        trade.issue?.let(::fail)
        cash?.let { MovementDraft(it.accountId, it.categoryId, trade.day, it.amountMinor, it.description).issue?.let(::fail) }
        val params = buildJsonObject {
            put("trade", trade.id.ifEmpty { java.util.UUID.randomUUID().toString() })
            put("household", trade.householdId)
            put("holding", trade.holdingId)
            put("traded", trade.tradedOn)
            put("trade_side", Json.encodeToJsonElement(trade.side))
            put("shares", trade.quantity.toPlainString())
            put("unit_price", trade.price.toPlainString())
            put("fee", trade.feeMinor)
            put("trade_note", trade.note)
            put("account", cash?.accountId)
            put("category", cash?.categoryId)
            put("cash", cash?.amountMinor)
            put("label", cash?.description?.trim())
        }
        client.postgrest.rpc("create_trade", params) { select(Columns.raw(TRADE)) }.decodeList<InvestmentTrade>().first()
    }

    override suspend fun deleteTrade(tradeId: String) = backend.mapped<Unit> {
        client.from("investment_trades").delete { filter { eq("id", tradeId) } }
    }

    override suspend fun investmentPlans(householdId: String): List<InvestmentPlan> = backend.mapped {
        client.from("investment_plans").select(Columns.raw(PLAN)) {
            filter { eq("household_id", householdId) }
            order("starts_on", Order.ASCENDING)
        }.decodeList()
    }

    private fun InvestmentPlan.columns() = buildJsonObject {
        put("account_id", accountId)
        put("amount_minor", amountMinor)
        put("every", every)
        put("unit", Json.encodeToJsonElement(unit))
        put("starts_on", startsOn)
        put("ends_on", endsOn)
        put("expected_annual_return", expectedAnnualReturn.toPlainString())
        put("remind_days_before", remindDaysBefore)
        put("paused_at", pausedAt)
        put("archived_at", archivedAt)
    }

    override suspend fun createPlan(plan: InvestmentPlan): InvestmentPlan = backend.mapped {
        plan.issue?.let(::fail)
        val row = JsonObject(plan.columns() + mapOf("household_id" to JsonPrimitive(plan.householdId), "holding_id" to JsonPrimitive(plan.holdingId)))
        client.from("investment_plans").insert(row) { select(Columns.raw(PLAN)) }.decodeSingle()
    }

    override suspend fun updatePlan(plan: InvestmentPlan): InvestmentPlan = backend.mapped {
        plan.issue?.let(::fail)
        client.from("investment_plans").update(plan.columns()) {
            select(Columns.raw(PLAN))
            filter { eq("id", plan.id) }
        }.decodeSingle()
    }

    override suspend fun deletePlan(planId: String) = backend.mapped<Unit> {
        client.from("investment_plans").delete { filter { eq("id", planId) } }
    }

    /** Todas las filas del hogar, de 1000 en 1000 (el máximo que devuelve el servidor por petición). */
    private suspend inline fun <reified Row : Any> allRows(table: String, columns: String, householdId: String, orderBy: String): List<Row> = backend.mapped {
        val all = mutableListOf<Row>()
        while (true) {
            val start = all.size.toLong()
            val page = client.from(table).select(Columns.raw(columns)) {
                filter { eq("household_id", householdId) }
                order(orderBy, Order.ASCENDING)
                order("id", Order.ASCENDING)
                range(start, start + 999)
            }.decodeList<Row>()
            all += page
            if (page.size < 1000) break
        }
        all
    }

    private companion object {
        const val SERIES = "id,household_id,name,kind,amount_minor,account_id,category_id,every,unit,starts_on,ends_on,remind_days_before,archived_at,intro_amount_minor,intro_charges,creates_pending,pending_from"
        const val CHARGE = "id,household_id,series_id,due_on,amount_minor,status,transaction_id"
        const val GOAL = "id,household_id,name,kind,target_minor,starting_minor,monthly_plan_minor,target_on,account_id,icon,completed_at,archived_at"
        const val CONTRIBUTION = "id,household_id,goal_id,amount_minor,made_on,note,created_by"
        const val BUDGET = "household_id,month,ends_on,expected_income_minor,needs_pct,wants_pct,savings_pct,carry_over,warn_pct,budget_lines(category_id,limit_minor)"
        const val EXTRA = "id,household_id,name,limit_minor,starts_on,ends_on,category_ids,account_ids,is_favorite"
        const val PAGE = 1000
        const val ACCOUNT = "id,household_id,name,kind,currency,opening_balance_minor,owner_id,archived_at,is_default,include_in_net_worth,created_at"
        const val CATEGORY = "id,household_id,name,kind,budget_group,icon"
        const val MOVEMENT = "id,household_id,account_id,category_id,booked_on,amount_minor,description,notes,import_hash,excluded,reviewed_at,payee,tags"

        /** Filas por petición al importar, para no mandar un CSV enorme de golpe. */
        const val IMPORT_BATCH = 500
    }
}

private const val CARD = "account_id,household_id,credit_limit_minor,statement_day,payment_day,payment_delay_months,payment_mode," +
    "fixed_payment_minor,min_payment_percent,min_payment_minor,revolving_rate,installment_rate,pay_from_account_id,remind_days_before,alert_percent"
private const val HOLDING = "id,household_id,name,symbol,kind,asset_class,currency,account_id,owner_id,price,price_on,fee_rate,note,archived_at"
private const val PRICE = "id,household_id,holding_id,priced_on,price"
private const val TRADE = "id,household_id,holding_id,traded_on,side,quantity,price,fee_minor,note"
private const val PLAN = "id,household_id,holding_id,account_id,amount_minor,every,unit,starts_on,ends_on,expected_annual_return,remind_days_before,paused_at,archived_at"
private const val SCORE = "id,score,max_score,provider,recorded_on,note"
private const val INSTALLMENT = "id,household_id,account_id,transaction_id,months,rate"

private fun CreditCardTerms.columns() = buildJsonObject {
    put("credit_limit_minor", creditLimit)
    put("statement_day", statementDay)
    put("payment_day", paymentDay)
    put("payment_delay_months", paymentDelayMonths)
    put("payment_mode", paymentMode.name.lowercase())
    put("fixed_payment_minor", fixedPayment)
    put("min_payment_percent", minPaymentPercent)
    put("min_payment_minor", minPayment)
    put("revolving_rate", revolvingRate)
    put("installment_rate", installmentRate)
    put("pay_from_account_id", payFromAccountId)
    put("remind_days_before", remindDaysBefore)
    put("alert_percent", alertPercent)
}

/** Columnas editables, con los nulos explícitos para poder borrar un valor. */
private fun RecurringSeries.columns() = buildJsonObject {
    put("name", trimmedName)
    put("kind", RECURRING_KIND.getValue(kind))
    put("amount_minor", amountMinor)
    put("account_id", accountId)
    put("category_id", categoryId)
    put("every", every)
    put("unit", unit.name.lowercase())
    put("starts_on", startsOn)
    put("ends_on", endsOn)
    put("remind_days_before", remindDaysBefore)
    put("archived_at", archivedAt)
    put("intro_amount_minor", introMinor)
    put("intro_charges", introCharges)
    put("creates_pending", createsPending)
    pendingFrom?.let { put("pending_from", it) }
}

private val RECURRING_KIND = mapOf(RecurringKind.Subscription to "subscription", RecurringKind.Essential to "essential", RecurringKind.Income to "income")

private fun Goal.columns() = buildJsonObject {
    put("name", trimmedName)
    put("kind", kind.name.lowercase())
    put("target_minor", targetMinor)
    put("starting_minor", startingMinor)
    put("monthly_plan_minor", monthlyPlanMinor)
    put("target_on", targetOn)
    put("account_id", accountId)
    put("icon", icon)
    put("completed_at", completedAt)
    put("archived_at", archivedAt)
}

// Filas que se envían. Nunca llevan id ni created_by: el servidor no deja escribirlos.
// Los opcionales van como null explícito: todas las filas de un lote deben llevar las mismas claves.

@Serializable
private data class BudgetRow(
    @SerialName("household_id") val householdId: String,
    val month: String,
    @SerialName("ends_on") val endsOn: String? = null,
    @SerialName("expected_income_minor") val expectedIncome: Long,
    @SerialName("needs_pct") val needs: Int,
    @SerialName("wants_pct") val wants: Int,
    @SerialName("savings_pct") val savings: Int,
    @SerialName("carry_over") val carryOver: Boolean? = null,
    @SerialName("warn_pct") val warnPct: Int? = null,
    @SerialName("budget_lines") val lines: List<Line>,
) {
    @Serializable
    data class Line(@SerialName("category_id") val categoryId: String, @SerialName("limit_minor") val limit: Long)

    val budget: Budget? get() {
        if (needs + wants + savings != 100) return null
        val start = LocalDate.parse(month.take(10))
        val period = endsOn?.let { BudgetPeriod(start, LocalDate.parse(it.take(10))) } ?: BudgetPeriod(YearMonth.from(start))
        return Budget(
            householdId, period, expectedIncome, BudgetTemplate(needs, wants, savings), lines.associate { it.categoryId to it.limit },
            carryOver ?: false, warnPct ?: 80,
        )
    }
}

@Serializable
private data class PayScheduleRow(
    val frequency: String,
    val day1: Int,
    val day2: Int? = null,
    @SerialName("anchor_on") val anchorOn: String? = null,
) {
    val schedule: PaySchedule? get() = PayFrequency.of(frequency)?.let { PaySchedule(it, day1, day2, anchorOn?.let { d -> LocalDate.parse(d.take(10)) }) }
}

@Serializable
private data class ExtraRow(
    val id: String,
    @SerialName("household_id") val householdId: String,
    val name: String,
    @SerialName("limit_minor") val limit: Long,
    @SerialName("starts_on") val startsOn: String,
    @SerialName("ends_on") val endsOn: String? = null,
    @SerialName("category_ids") val categoryIds: List<String> = emptyList(),
    @SerialName("account_ids") val accountIds: List<String> = emptyList(),
    @SerialName("is_favorite") val isFavorite: Boolean = false,
) {
    val extra: ExtraBudget get() = ExtraBudget(
        id, householdId, name, limit, LocalDate.parse(startsOn.take(10)), endsOn?.let { LocalDate.parse(it.take(10)) },
        categoryIds, accountIds, isFavorite,
    )
}

@Serializable
private data class BalanceRow(@SerialName("account_id") val accountId: String, @SerialName("balance_minor") val balanceMinor: Long)

@Serializable
private data class IdRow(val id: String)

@Serializable
private data class NewAccountRow(
    @SerialName("household_id") val householdId: String,
    val name: String,
    val kind: AccountKind,
    @SerialName("opening_balance_minor") val openingMinor: Long,
    @SerialName("owner_id") val ownerId: String?,
)

@Serializable
private data class AccountChanges(
    val name: String,
    val kind: AccountKind,
    @SerialName("opening_balance_minor") val openingMinor: Long,
    @SerialName("owner_id") val ownerId: String?,
    @SerialName("archived_at") val archivedAt: String?,
    @SerialName("is_default") val isDefault: Boolean,
    @SerialName("include_in_net_worth") val includeInNetWorth: Boolean,
)

@Serializable
private data class NewCategoryRow(
    @SerialName("household_id") val householdId: String,
    val kind: CategoryKind,
    val name: String,
    @SerialName("budget_group") val budgetGroup: BudgetGroup?,
    val icon: String?,
)

@Serializable
private data class CategoryChanges(
    val name: String,
    @SerialName("budget_group") val budgetGroup: BudgetGroup?,
    val icon: String?,
)

@Serializable
private data class NewMovementRow(
    @SerialName("household_id") val householdId: String,
    @SerialName("account_id") val accountId: String,
    @SerialName("category_id") val categoryId: String?,
    @SerialName("booked_on") val bookedOn: String,
    @SerialName("amount_minor") val amountMinor: Long,
    val description: String,
    val notes: String?,
    @SerialName("import_hash") val importHash: String?,
    val excluded: Boolean,
    val payee: String?,
    val tags: List<String>,
) {
    companion object {
        fun of(d: MovementDraft, householdId: String) = NewMovementRow(
            householdId, d.accountId, d.categoryId, d.bookedOn.toString(), d.amountMinor, d.description.trim(), d.notes, d.importHash,
            d.excluded, Payee.clean(d.payee), d.tags,
        )
    }
}

@Serializable
private data class NewChargeRow(
    @SerialName("household_id") val householdId: String,
    @SerialName("series_id") val seriesId: String,
    @SerialName("due_on") val dueOn: String,
    @SerialName("amount_minor") val amountMinor: Long,
)

@Serializable
private data class MovementChanges(
    @SerialName("account_id") val accountId: String,
    @SerialName("category_id") val categoryId: String?,
    @SerialName("booked_on") val bookedOn: String,
    @SerialName("amount_minor") val amountMinor: Long,
    val description: String,
    val notes: String?,
    val excluded: Boolean,
    @SerialName("reviewed_at") val reviewedAt: String?,
    val payee: String?,
    val tags: List<String>,
)
