package com.savethemoney.android.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

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
        client.from("accounts").update(AccountChanges(account.name.trim(), account.kind, account.openingMinor, account.ownerId, account.archivedAt)) {
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

    override suspend fun addMovement(draft: MovementDraft, householdId: String): Movement = backend.mapped {
        draft.issue?.let(::fail)
        client.from("transactions").insert(NewMovementRow.of(draft, householdId)) { select(Columns.raw(MOVEMENT)) }.decodeSingle()
    }

    override suspend fun updateMovement(movement: Movement): Movement = backend.mapped {
        movement.toDraft().issue?.let(::fail)
        val changes = MovementChanges(
            movement.accountId, movement.categoryId, movement.bookedOn, movement.amountMinor, movement.description.trim(), movement.notes,
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

    private companion object {
        const val ACCOUNT = "id,household_id,name,kind,currency,opening_balance_minor,owner_id,archived_at"
        const val CATEGORY = "id,household_id,name,kind,budget_group,icon"
        const val MOVEMENT = "id,household_id,account_id,category_id,booked_on,amount_minor,description,notes,import_hash"

        /** Filas por petición al importar, para no mandar un CSV enorme de golpe. */
        const val IMPORT_BATCH = 500
    }
}

// Filas que se envían. Nunca llevan id ni created_by: el servidor no deja escribirlos.
// Los opcionales van como null explícito: todas las filas de un lote deben llevar las mismas claves.

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
) {
    companion object {
        fun of(d: MovementDraft, householdId: String) = NewMovementRow(
            householdId, d.accountId, d.categoryId, d.bookedOn.toString(), d.amountMinor, d.description.trim(), d.notes, d.importHash,
        )
    }
}

@Serializable
private data class MovementChanges(
    @SerialName("account_id") val accountId: String,
    @SerialName("category_id") val categoryId: String?,
    @SerialName("booked_on") val bookedOn: String,
    @SerialName("amount_minor") val amountMinor: Long,
    val description: String,
    val notes: String?,
)
