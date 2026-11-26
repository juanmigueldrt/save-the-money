package com.savethemoney.android.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.annotations.SupabaseExperimental
import io.github.jan.supabase.postgrest.query.PostgrestRequestBuilder
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
import kotlin.math.abs

/** Cuentas, categorías y movimientos sobre Supabase. El RLS del servidor decide qué se ve. */
class SupabaseFinance(private val backend: SupabaseBackend) : FinanceService {
    private val client get() = backend.client

    private fun fail(text: String): Nothing = throw AppError.InvalidInput(text)

    override suspend fun accounts(householdId: String): List<Account> = backend.mapped {
        allPages { from, to ->
            client.from("accounts").select(Columns.raw(ACCOUNT)) {
                filter { eq("household_id", householdId) }
                order("created_at", Order.ASCENDING)
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<Account>()
        }
    }

    override suspend fun balances(householdId: String): Map<String, Long> = backend.mapped {
        allPages { from, to ->
            client.from("account_balances").select(Columns.raw("account_id,balance_minor")) {
                filter { eq("household_id", householdId) }
                order("account_id", Order.ASCENDING)
                range(from, to)
            }.decodeList<BalanceRow>()
        }.associate { it.accountId to it.balanceMinor }
    }

    override suspend fun createAccount(draft: AccountDraft, householdId: String): Account = backend.mapped {
        draft.issue?.let(::fail)
        // create_account no repite una cuenta ya guardada con ese id: devuelve la que había.
        val params = buildJsonObject {
            put("account", draft.id)
            put("household", householdId)
            put("label", draft.trimmedName)
            put("account_kind", Json.encodeToJsonElement(draft.kind))
            put("opening", draft.openingMinor)
            put("owner", draft.ownerId)
        }
        client.postgrest.rpc("create_account", params) { select(Columns.raw(ACCOUNT)) }.decodeSingle()
    }

    override suspend fun updateAccount(account: Account): Account = backend.mapped {
        // update_account compara la versión y cambia la fila en la misma sentencia; si no coincide falla con STM05.
        val params = buildJsonObject {
            put("account", account.id)
            put("seen", account.updatedAt)
            put("label", account.name.trim())
            put("account_kind", Json.encodeToJsonElement(account.kind))
            put("opening", account.openingMinor)
            put("owner", account.ownerId)
            put("archived", account.archivedAt)
            put("make_default", account.isDefault && !account.isArchived)
            put("in_net_worth", account.includeInNetWorth)
        }
        client.postgrest.rpc("update_account", params) { select(Columns.raw(ACCOUNT)) }.decodeSingle()
    }

    override suspend fun deleteAccount(accountId: String) = backend.mapped {
        client.from("accounts").delete { filter { eq("id", accountId) } }
        Unit
    }

    override suspend fun categories(householdId: String): List<BudgetCategory> = backend.mapped {
        allPages { from, to ->
            client.from("categories").select(Columns.raw(CATEGORY)) {
                filter { eq("household_id", householdId) }
                order("name", Order.ASCENDING)
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<BudgetCategory>()
        }
    }

    private fun CategoryKind.groupOf(category: BudgetCategory) = if (this == CategoryKind.Expense) category.budgetGroup else null

    override suspend fun createCategory(category: BudgetCategory): BudgetCategory = backend.mapped {
        category.issue(emptyList())?.let(::fail)
        // create_category no repite una categoría ya guardada con ese id: devuelve la que había.
        val params = buildJsonObject {
            put("category", category.id.ifEmpty(::newId))
            put("household", category.householdId)
            put("label", category.trimmedName)
            put("category_kind", Json.encodeToJsonElement(category.kind))
            put("budget", Json.encodeToJsonElement(category.kind.groupOf(category)))
            put("icon_name", category.icon)
        }
        client.postgrest.rpc("create_category", params) { select(Columns.raw(CATEGORY)) }.decodeSingle()
    }

    /** Solo nombre, grupo e icono: el tipo de una categoría no se cambia. */
    override suspend fun updateCategory(category: BudgetCategory): BudgetCategory = backend.mapped {
        category.issue(emptyList())?.let(::fail)
        // update_category compara la versión y cambia la fila en la misma sentencia; si no coincide falla con STM05.
        val params = buildJsonObject {
            put("category", category.id)
            put("seen", category.updatedAt)
            put("label", category.trimmedName)
            put("budget", Json.encodeToJsonElement(category.kind.groupOf(category)))
            put("icon_name", category.icon)
        }
        client.postgrest.rpc("update_category", params) { select(Columns.raw(CATEGORY)) }.decodeSingle()
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

    /**
     * Páginas por cursor (día e id de la última fila) y no por `range`: si entra o se borra un movimiento entre página y
     * página, la siguiente no repite ni se salta filas.
     */
    override suspend fun movements(householdId: String, accountId: String?, search: MovementSearch?, after: Movement?, limit: Int): List<Movement> =
        backend.mapped {
            client.from("transactions").select(Columns.raw(MOVEMENT)) {
                movementPage(householdId, accountId, search, after)
                order("booked_on", Order.DESCENDING)
                order("id", Order.DESCENDING)
                limit(limit.toLong())
            }.decodeList()
        }

    override suspend fun movements(householdId: String, ids: List<String>): List<Movement> = backend.mapped {
        if (ids.isEmpty()) return@mapped emptyList()
        allPages { from, to ->
            client.from("transactions").select(Columns.raw(MOVEMENT)) {
                filter {
                    eq("household_id", householdId)
                    isIn("id", ids)
                }
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<Movement>()
        }
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

    /** create_movement no repite un movimiento ya guardado con ese id: devuelve el que había. */
    override suspend fun addMovement(draft: MovementDraft, householdId: String): Movement = backend.mapped {
        draft.issue?.let(::fail)
        val params = buildJsonObject {
            put("movement", draft.id)
            put("household", householdId)
            put("account", draft.accountId)
            put("category", draft.categoryId)
            put("booked", draft.bookedOn.toString())
            put("amount", draft.amountMinor)
            put("label", draft.description.trim())
            put("note", draft.notes)
            put("is_excluded", draft.excluded)
            put("payee_name", Payee.clean(draft.payee))
            putJsonArray("tag_list") { draft.tags.forEach { add(JsonPrimitive(it)) } }
        }
        client.postgrest.rpc("create_movement", params) { select(Columns.raw(MOVEMENT)) }.decodeSingle()
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
        // update_movement compara la versión y cambia la fila en la misma sentencia; si no coincide falla con STM05.
        val params = buildJsonObject {
            put("movement", movement.id)
            // El `updated_at` tal cual llegó del servidor: es la versión que se leyó.
            put("seen", movement.updatedAt)
            put("account", movement.accountId)
            put("category", movement.categoryId)
            put("booked", movement.bookedOn)
            put("amount", movement.amountMinor)
            put("label", movement.description.trim())
            put("note", movement.notes)
            put("is_excluded", movement.excluded)
            put("reviewed", movement.reviewedAt)
            put("payee_name", Payee.clean(movement.payee))
            putJsonArray("tag_list") { movement.tags.forEach { add(JsonPrimitive(it)) } }
        }
        client.postgrest.rpc("update_movement", params) { select(Columns.raw(MOVEMENT)) }.decodeSingle()
    }

    override suspend fun deleteMovement(movementId: String) = backend.mapped {
        client.from("transactions").delete { filter { eq("id", movementId) } }
        Unit
    }

    /** delete_transfer borra las dos patas en una sola transacción, o ninguna (STM07). */
    override suspend fun deleteTransfer(transferId: String) = backend.mapped {
        client.postgrest.rpc("delete_transfer", buildJsonObject { put("transfer", transferId) })
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
        val params = buildJsonObject {
            put("budget", budget.id)
            put("label", budget.trimmedName)
            put("cap", budget.limit)
            put("starts", budget.startsOn.toString())
            put("ends", budget.endsOn?.toString())
            putJsonArray("category_list") { budget.categoryIds.forEach { add(JsonPrimitive(it)) } }
            putJsonArray("account_list") { budget.accountIds.forEach { add(JsonPrimitive(it)) } }
            put("favorite", budget.isFavorite)
            if (budget.updatedAt == null) put("household", budget.householdId) else put("seen", budget.updatedAt)
        }
        // Sin versión es uno nuevo (create_extra_budget no lo repite si ya estaba); con versión, un cambio
        // (update_extra_budget falla con STM05 si ya no es la que se leyó).
        val function = if (budget.updatedAt == null) "create_extra_budget" else "update_extra_budget"
        client.postgrest.rpc(function, params) { select(Columns.raw(EXTRA)) }.decodeSingle<ExtraRow>().extra
    }

    override suspend fun deleteExtraBudget(id: String) = backend.mapped {
        client.from("extra_budgets").delete { filter { eq("id", id) } }
        Unit
    }

    override suspend fun resetHousehold(householdId: String) = backend.mapped<Unit> {
        client.postgrest.rpc("reset_household", buildJsonObject { put("target_household", householdId) })
    }

    override suspend fun movements(householdId: String, from: LocalDate, through: LocalDate): List<Movement> = backend.mapped {
        allPages { first, last ->
            client.from("transactions").select(Columns.raw(MOVEMENT)) {
                filter {
                    eq("household_id", householdId)
                    gte("booked_on", from.toString())
                    lte("booked_on", through.toString())
                }
                order("booked_on", Order.DESCENDING)
                order("id", Order.ASCENDING)
                range(first, last)
            }.decodeList<Movement>()
        }
    }

    // MARK: pagos fijos y metas. household_id solo al insertar: el servidor no deja cambiarlo después.

    override suspend fun recurringSeries(householdId: String): List<RecurringSeries> = backend.mapped {
        allPages { from, to ->
            client.from("recurring_series").select(Columns.raw(SERIES)) {
                filter { eq("household_id", householdId) }
                order("name", Order.ASCENDING)
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<RecurringSeries>()
        }
    }

    override suspend fun createRecurring(series: RecurringSeries): RecurringSeries = backend.mapped {
        series.issue?.let(::fail)
        // create_recurring_series no repite un pago fijo ya guardado con ese id: devuelve el que había.
        val params = series.copy(id = series.id.ifEmpty(::newId)).params().with("household", series.householdId)
        client.postgrest.rpc("create_recurring_series", params) { select(Columns.raw(SERIES)) }.decodeSingle()
    }

    override suspend fun updateRecurring(series: RecurringSeries): RecurringSeries = backend.mapped {
        series.issue?.let(::fail)
        // update_recurring_series compara la versión y cambia la fila en la misma sentencia; si no coincide falla con STM05.
        client.postgrest.rpc("update_recurring_series", series.params().with("seen", series.updatedAt)) { select(Columns.raw(SERIES)) }.decodeSingle()
    }

    override suspend fun deleteRecurring(seriesId: String) = backend.mapped {
        client.from("recurring_series").delete { filter { eq("id", seriesId) } }
        Unit
    }

    // Cargos pendientes: de quien los crea; se borran con su serie (on delete cascade).

    override suspend fun recurringCharges(householdId: String): List<RecurringCharge> = backend.mapped {
        allPages { from, to ->
            client.from("recurring_charges").select(Columns.raw(CHARGE)) {
                filter { eq("household_id", householdId) }
                order("due_on", Order.DESCENDING)
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<RecurringCharge>()
        }
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

    override suspend fun updateCharge(charge: RecurringCharge, status: ChargeStatus, transactionId: String?): RecurringCharge = backend.mapped {
        // update_recurring_charge compara la versión y cambia la fila en la misma sentencia; si no coincide falla con STM05.
        val params = buildJsonObject {
            put("charge", charge.id)
            put("seen", charge.updatedAt)
            put("new_status", status.name.lowercase())
            put("movement", if (status == ChargeStatus.Pending) null else transactionId)
        }
        client.postgrest.rpc("update_recurring_charge", params) { select(Columns.raw(CHARGE)) }.decodeSingle()
    }

    override suspend fun goals(householdId: String): List<Goal> = backend.mapped {
        allPages { from, to ->
            client.from("goals").select(Columns.raw(GOAL)) {
                filter { eq("household_id", householdId) }
                order("created_at", Order.ASCENDING)
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<Goal>()
        }
    }

    override suspend fun createGoal(goal: Goal): Goal = backend.mapped {
        goal.issue?.let(::fail)
        // create_goal no repite una meta ya guardada con ese id: devuelve la que había.
        val params = goal.copy(id = goal.id.ifEmpty(::newId)).params().with("household", goal.householdId)
        client.postgrest.rpc("create_goal", params) { select(Columns.raw(GOAL)) }.decodeSingle()
    }

    override suspend fun updateGoal(goal: Goal): Goal = backend.mapped {
        goal.issue?.let(::fail)
        // update_goal compara la versión y cambia la fila en la misma sentencia; si no coincide falla con STM05.
        client.postgrest.rpc("update_goal", goal.params().with("seen", goal.updatedAt)) { select(Columns.raw(GOAL)) }.decodeSingle()
    }

    override suspend fun deleteGoal(goalId: String) = backend.mapped {
        client.from("goals").delete { filter { eq("id", goalId) } }
        Unit
    }

    override suspend fun contributions(householdId: String): List<GoalContribution> = backend.mapped {
        allPages { from, to ->
            client.from("goal_contributions").select(Columns.raw(CONTRIBUTION)) {
                filter { eq("household_id", householdId) }
                order("made_on", Order.DESCENDING)
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<GoalContribution>()
        }
    }

    override suspend fun addContribution(contribution: GoalContribution): GoalContribution = backend.mapped {
        contribution.issue?.let(::fail)
        val params = buildJsonObject {
            put("contribution", contribution.id.ifEmpty(::newId))
            put("household", contribution.householdId)
            put("goal", contribution.goalId)
            put("amount", contribution.amountMinor)
            put("made", contribution.madeOn)
            put("remark", contribution.note)
        }
        client.postgrest.rpc("create_goal_contribution", params) { select(Columns.raw(CONTRIBUTION)) }.decodeSingle()
    }

    override suspend fun creditCards(householdId: String): List<CreditCardTerms> = backend.mapped {
        allPages { from, to ->
            client.from("credit_cards").select(Columns.raw(CARD)) {
                filter { eq("household_id", householdId) }
                order("account_id", Order.ASCENDING)
                range(from, to)
            }.decodeList<CreditCardTerms>()
        }
    }

    // No se usa upsert: haría UPDATE de la cuenta y el hogar, que no se pueden cambiar.
    override suspend fun saveCreditCard(terms: CreditCardTerms): CreditCardTerms = backend.mapped {
        terms.issue?.let(::fail)
        if (terms.updatedAt == null) {
            // Sin versión son condiciones nuevas: create_credit_card no las repite si ya estaban guardadas.
            client.postgrest.rpc("create_credit_card", terms.params().with("household", terms.householdId)) { select(Columns.raw(CARD)) }.decodeSingle()
        } else {
            // update_credit_card compara la versión y cambia la fila en la misma sentencia; si no coincide falla con STM05.
            client.postgrest.rpc("update_credit_card", terms.params().with("seen", terms.updatedAt)) { select(Columns.raw(CARD)) }.decodeSingle()
        }
    }

    override suspend fun cardInstallments(householdId: String): List<CardInstallment> = backend.mapped {
        allPages { from, to ->
            client.from("card_installments").select(Columns.raw(INSTALLMENT)) {
                filter { eq("household_id", householdId) }
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<CardInstallment>()
        }
    }

    override suspend fun saveInstallment(installment: CardInstallment): CardInstallment = backend.mapped {
        installment.issue?.let(::fail)
        val params = buildJsonObject {
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
        }
        // Sin versión es un aplazado nuevo (create_card_installment no lo repite si ya estaba); con versión, un cambio
        // (update_card_installment falla con STM05 si ya no es la que se leyó).
        val function = if (installment.updatedAt == null) "create_card_installment" else "update_card_installment"
        client.postgrest.rpc(function, params) { select(Columns.raw(INSTALLMENT)) }.decodeSingle()
    }

    override suspend fun creditScores(): List<CreditScore> = backend.mapped {
        allPages { from, to ->
            client.from("credit_scores").select(Columns.raw(SCORE)) {
                order("recorded_on", Order.DESCENDING)
                order("created_at", Order.DESCENDING)
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<CreditScore>()
        }
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
        allPages { from, to ->
            client.from("holdings").select(Columns.raw(HOLDING)) {
                filter { eq("household_id", householdId) }
                order("name", Order.ASCENDING)
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<Holding>()
        }
    }

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

    override suspend fun createHolding(holding: Holding): Holding = backend.mapped {
        holding.issue?.let(::fail)
        // create_holding no repite un activo ya guardado con ese id: devuelve el que había.
        val params = holding.copy(id = holding.id.ifEmpty(::newId)).params().with("household", holding.householdId)
        client.postgrest.rpc("create_holding", params) { select(Columns.raw(HOLDING)) }.decodeSingle()
    }

    override suspend fun updateHolding(holding: Holding): Holding = backend.mapped {
        holding.issue?.let(::fail)
        // update_holding compara la versión y cambia la fila en la misma sentencia; si no coincide falla con STM05.
        client.postgrest.rpc("update_holding", holding.params().with("seen", holding.updatedAt)) { select(Columns.raw(HOLDING)) }.decodeSingle()
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
        allPages { from, to ->
            client.from("investment_plans").select(Columns.raw(PLAN)) {
                filter { eq("household_id", householdId) }
                order("starts_on", Order.ASCENDING)
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<InvestmentPlan>()
        }
    }

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

    override suspend fun createPlan(plan: InvestmentPlan): InvestmentPlan = backend.mapped {
        plan.issue?.let(::fail)
        // create_investment_plan no repite un plan ya guardado con ese id: devuelve el que había.
        val params = plan.copy(id = plan.id.ifEmpty(::newId)).params().with("household", plan.householdId).with("holding", plan.holdingId)
        client.postgrest.rpc("create_investment_plan", params) { select(Columns.raw(PLAN)) }.decodeSingle()
    }

    override suspend fun updatePlan(plan: InvestmentPlan): InvestmentPlan = backend.mapped {
        plan.issue?.let(::fail)
        // update_investment_plan compara la versión y cambia la fila en la misma sentencia; si no coincide falla con STM05.
        client.postgrest.rpc("update_investment_plan", plan.params().with("seen", plan.updatedAt)) { select(Columns.raw(PLAN)) }.decodeSingle()
    }

    override suspend fun deletePlan(planId: String) = backend.mapped<Unit> {
        client.from("investment_plans").delete { filter { eq("id", planId) } }
    }

    /** Todas las filas del hogar, por páginas ([allPages]). */
    private suspend inline fun <reified Row : Any> allRows(table: String, columns: String, householdId: String, orderBy: String): List<Row> = backend.mapped {
        allPages { from, to ->
            client.from(table).select(Columns.raw(columns)) {
                filter { eq("household_id", householdId) }
                order(orderBy, Order.ASCENDING)
                order("id", Order.ASCENDING)
                range(from, to)
            }.decodeList<Row>()
        }
    }

    private companion object {
        const val SERIES = "id,household_id,name,kind,amount_minor,account_id,category_id,every,unit,starts_on,ends_on,remind_days_before,archived_at,intro_amount_minor,intro_charges,creates_pending,pending_from,updated_at"
        const val CHARGE = "id,household_id,series_id,due_on,amount_minor,status,transaction_id,updated_at"
        const val GOAL = "id,household_id,name,kind,target_minor,starting_minor,monthly_plan_minor,target_on,account_id,icon,completed_at,archived_at,updated_at"
        const val CONTRIBUTION = "id,household_id,goal_id,amount_minor,made_on,note,created_by"
        const val BUDGET = "household_id,month,ends_on,expected_income_minor,needs_pct,wants_pct,savings_pct,carry_over,warn_pct,budget_lines(category_id,limit_minor)"
        const val EXTRA = "id,household_id,name,limit_minor,starts_on,ends_on,category_ids,account_ids,is_favorite,updated_at"
        const val ACCOUNT = "id,household_id,name,kind,currency,opening_balance_minor,owner_id,archived_at,is_default,include_in_net_worth,created_at,updated_at"
        const val CATEGORY = "id,household_id,name,kind,budget_group,icon,updated_at"
        const val MOVEMENT = "id,household_id,account_id,category_id,booked_on,amount_minor,description,notes,import_hash,excluded,reviewed_at,payee,tags,updated_at,transfer_id"

        /** Filas por petición al importar, para no mandar un CSV enorme de golpe. */
        const val IMPORT_BATCH = 500
    }
}

private const val CARD = "account_id,household_id,credit_limit_minor,statement_day,payment_day,payment_delay_months,payment_mode," +
    "fixed_payment_minor,min_payment_percent,min_payment_minor,revolving_rate,installment_rate,pay_from_account_id,remind_days_before,alert_percent,updated_at"
private const val HOLDING = "id,household_id,name,symbol,kind,asset_class,currency,account_id,owner_id,price,price_on,fee_rate,note,archived_at,updated_at"
private const val PRICE = "id,household_id,holding_id,priced_on,price"
private const val TRADE = "id,household_id,holding_id,traded_on,side,quantity,price,fee_minor,note"
private const val PLAN = "id,household_id,holding_id,account_id,amount_minor,every,unit,starts_on,ends_on,expected_annual_return,remind_days_before,paused_at,archived_at,updated_at"
private const val SCORE = "id,score,max_score,provider,recorded_on,note"
private const val INSTALLMENT = "id,household_id,account_id,transaction_id,months,rate,updated_at"

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

/**
 * Columnas editables, con los nulos explícitos para poder borrar un valor: lo que comparten create_recurring_series y
 * update_recurring_series. Sin `pendingFrom`, el servidor pone hoy al crear y deja el que había al cambiar.
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

private val RECURRING_KIND = mapOf(RecurringKind.Subscription to "subscription", RecurringKind.Essential to "essential", RecurringKind.Income to "income")

/** Un id para una fila nueva que llega sin él: quien llama no es un formulario que vaya a reintentar. */
private fun newId() = java.util.UUID.randomUUID().toString()

/** Los parámetros de una función del servidor más uno: el hogar al dar de alta, la versión leída al cambiar. */
private fun JsonObject.with(key: String, value: String?) = JsonObject(this + (key to JsonPrimitive(value)))

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
    @SerialName("updated_at") val updatedAt: String? = null,
) {
    val extra: ExtraBudget get() = ExtraBudget(
        id, householdId, name, limit, LocalDate.parse(startsOn.take(10)), endsOn?.let { LocalDate.parse(it.take(10)) },
        categoryIds, accountIds, isFavorite, updatedAt,
    )
}

@Serializable
private data class BalanceRow(@SerialName("account_id") val accountId: String, @SerialName("balance_minor") val balanceMinor: Long)

@Serializable
private data class IdRow(val id: String)

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

/**
 * Los filtros de una página de la lista (ORC-85): el hogar, la cuenta, la búsqueda y el cursor. La búsqueda y el cursor van
 * cada uno en su `or=(…)`, que PostgREST junta con AND. Van por [PostgrestRequestBuilder.params] y no por `filter { or {} }`:
 * en postgrest-kt 3.2 un segundo `or {}` pisa al primero, y su escapado deja sin comillas un valor con `\` o `"` si no
 * lleva `,.:()`, con lo que PostgREST leería las barras tal cual y la búsqueda de "50%" no encontraría nada.
 */
@OptIn(SupabaseExperimental::class)
internal fun PostgrestRequestBuilder.movementPage(householdId: String, accountId: String?, search: MovementSearch?, after: Movement?) {
    filter {
        eq("household_id", householdId)
        if (accountId != null) eq("account_id", accountId)
    }
    val logic = listOfNotNull(search?.let(::movementSearchFilter), after?.let(::movementAfterFilter))
    if (logic.isNotEmpty()) params["or"] = (params["or"] ?: emptyList()) + logic.map { "($it)" }
}

/**
 * Lo que va dentro de `or=(…)` para buscar. El texto del usuario va siempre entre comillas (así comas, puntos, paréntesis y
 * dos puntos no son sintaxis de PostgREST) y con los comodines de LIKE escapados. La etiqueta, los ids y el importe no
 * llevan nada que escapar: sólo letras, números, «-», «_» o un entero. Como `searchFilter` de iOS.
 */
internal fun movementSearchFilter(search: MovementSearch): String {
    val pattern = postgrestQuoted("*" + likeEscaped(search.text) + "*")
    val parts = listOf("description", "notes", "payee").map { "$it.ilike.$pattern" }.toMutableList()
    search.tag?.let { parts += "tags.cs.{$it}" }
    if (search.categoryIds.isNotEmpty()) parts += "category_id.in.(${search.categoryIds.joinToString(",") { it.lowercase() }})"
    search.amountMinor?.let { amount ->
        parts += if (search.signedAmount) "amount_minor.eq.$amount" else "amount_minor.in.(${abs(amount)},${-abs(amount)})"
    }
    return parts.joinToString(",")
}

/** Las filas que van detrás de [after] en el orden de la lista: un día anterior, o el mismo día y un id menor. */
internal fun movementAfterFilter(after: Movement): String =
    "booked_on.lt.${after.bookedOn},and(booked_on.eq.${after.bookedOn},id.lt.${after.id.lowercase()})"

/**
 * `\`, `%` y `_` se buscan tal cual. PostgREST convierte cada `*` en `%` y no deja escaparlo, así que un `*` escrito cuenta
 * como «un carácter cualquiera» (`_`): encuentra lo mismo y algo más, nunca menos.
 */
internal fun likeEscaped(text: String): String = buildString {
    text.forEach { ch ->
        when (ch) {
            '\\', '%', '_' -> append('\\').append(ch)
            '*' -> append('_')
            else -> append(ch)
        }
    }
}

/** Un valor entre comillas dobles para un filtro de PostgREST: dentro, `\` y `"` van con `\` delante. */
internal fun postgrestQuoted(value: String): String = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
