package com.savethemoney.android.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal
import java.time.LocalDate

/** Lo mismo que `supabase/tests/database/11_privacidad.test.sql` y HouseholdFlowTests.swift: cada miembro ve y toca solo lo suyo. Datos inventados. */
class PrivacidadTest {
    private val password = "contrasena-de-prueba"
    private val november = LocalDate.of(2026, 11, 2)
    private val period = BudgetPeriod(LocalDate.of(2026, 11, 1), LocalDate.of(2026, 11, 30))

    private fun user(name: String) = Username.parse(name).getOrThrow()

    private fun rejected(message: String, call: suspend () -> Unit) {
        assertTrue(message, runCatching { runBlocking { call() } }.isFailure)
    }

    private fun idUsed(message: String, call: suspend () -> Unit) {
        val error = runCatching { runBlocking { call() } }.exceptionOrNull()
        assertTrue(message, error is AppError.InvalidInput)
        assertEquals(message, "Ya hay un registro igual guardado. Revisa el formulario.", error?.message)
    }

    @Test
    fun brunoNoVeLasCuentasDeAna() = runBlocking {
        val backend = InMemoryBackend()
        val finance = InMemoryFinance(backend)

        // Ana crea el hogar, apunta sus cosas e invita a Bruno.
        backend.signUp(user("ana"), password, "Ana")
        val home = backend.createHousehold("Casa de prueba").id
        val anaAccount = finance.createAccount(AccountDraft("Cuenta de Ana"), home)
        val anaSavings = finance.createAccount(AccountDraft("Ahorro de Ana"), home)
        val anaMovement = finance.addMovement(MovementDraft(anaAccount.id, null, november, -4500, "Compra de Ana"), home)
        val anaTransfer = TransferDraft("transferencia-de-ana", anaAccount.id, anaSavings.id, bookedOn = november, amountMinor = 1000,
            fromDescription = "A ahorro", toDescription = "Desde la cuenta")
        finance.addTransfer(anaTransfer, home)
        val anaCategory = finance.categories(home).first { it.name == "Supermercado" }
        finance.saveBudget(Budget(home, period, 200_000))
        val anaHolding = finance.createHolding(Holding("", home, "Fondo de Ana", price = BigDecimal.TEN))
        val anaTrade = finance.addTrade(InvestmentTrade("operacion-de-ana", home, anaHolding.id, "2026-11-02", quantity = BigDecimal.ONE, price = BigDecimal.TEN), null)
        val anaGoal = finance.createGoal(Goal("", home, "Viaje", targetMinor = 100_000))
        finance.createRecurring(RecurringSeries("", home, "Música", amountMinor = 999, startsOn = "2026-11-02"))
        finance.saveExtraBudget(ExtraBudget("extra-de-ana", home, "Vacaciones", 80_000, startsOn = november, endsOn = november))
        val code = InviteCode.parse(backend.createInvite(home).code)!!
        backend.signOut()

        // Bruno -----------------------------------------------------------------------------
        backend.signUp(user("bruno"), password, null)
        backend.acceptInvite(code)
        assertEquals("Bruno no ve las cuentas de Ana", 0, finance.accounts(home).size)
        assertEquals("ni sus movimientos", 0, finance.movements(home, null, 100).size)
        assertNull("ni su presupuesto", finance.budget(home, period.start))
        val categories = finance.categories(home)
        assertEquals("Bruno tiene sus propias categorías de partida", 20, categories.size)
        assertFalse("y no ve las de Ana", categories.any { it.id == anaCategory.id })
        assertTrue(
            "ni sus inversiones, metas, pagos fijos o presupuestos extra",
            finance.holdings(home).isEmpty() && finance.trades(home).isEmpty() && finance.goals(home).isEmpty() &&
                finance.recurringSeries(home).isEmpty() && finance.extraBudgets(home).isEmpty(),
        )

        rejected("Bruno no apunta en la cuenta de Ana") {
            finance.addMovement(MovementDraft(anaAccount.id, null, november, -100, "Truco"), home)
        }
        val brunoAccount = finance.createAccount(AccountDraft("Cuenta de Bruno"), home)
        val brunoSavings = finance.createAccount(AccountDraft("Ahorro de Bruno"), home)
        rejected("ni usa una categoría de Ana") {
            finance.addMovement(MovementDraft(brunoAccount.id, anaCategory.id, november, -100, "Con categoría ajena"), home)
        }
        rejected("ni aporta a una meta de Ana") {
            finance.addContribution(GoalContribution("", home, anaGoal.id, 100, "2026-11-02"))
        }
        finance.addMovement(MovementDraft(brunoAccount.id, null, november, -2000, "Compra de Bruno"), home)

        // Un id de Ana no sirve para guardar lo de Bruno (como el 23505 del servidor) ni para cambiarlo.
        idUsed("un movimiento con el id de Ana no se guarda") {
            finance.addMovement(MovementDraft(brunoAccount.id, null, november, -4500, "Mismo id", id = anaMovement.id), home)
        }
        idUsed("una transferencia con el id de Ana no se guarda") {
            finance.addTransfer(anaTransfer.copy(fromAccountId = brunoAccount.id, toAccountId = brunoSavings.id), home)
        }
        val brunoHolding = finance.createHolding(Holding("", home, "Fondo de Bruno", price = BigDecimal.TEN))
        idUsed("una operación con el id de Ana no se guarda") {
            finance.addTrade(anaTrade.copy(holdingId = brunoHolding.id), null)
        }
        val changed = runCatching { finance.updateMovement(anaMovement.copy(description = "Cambiado por Bruno")) }.exceptionOrNull()
        assertEquals("Bruno no cambia un movimiento de Ana", AppError.MovementChanged, changed)

        finance.saveBudget(Budget(home, period, 150_000))
        assertEquals("Bruno guarda su presupuesto del mismo mes y solo ve el suyo", 150_000L, finance.budget(home, period.start)?.expectedIncome)
        finance.deleteAccount(anaAccount.id)
        finance.deleteGoal(anaGoal.id)
        finance.deleteHolding(anaHolding.id)
        finance.deleteAccount(brunoAccount.id)
        assertEquals("Bruno solo puede borrar su cuenta", listOf(brunoSavings.id), finance.accounts(home).map { it.id })
        finance.resetHousehold(home)
        backend.signOut()

        // Carla, de otro hogar, no ve nada del de Ana ni apunta en él.
        backend.signUp(user("carla"), password, null)
        assertTrue("quien no es del hogar no ve sus cuentas", finance.accounts(home).isEmpty())
        rejected("ni crea cuentas en él") { finance.createAccount(AccountDraft("Cuenta de Carla"), home) }
        backend.signOut()

        // Ana -------------------------------------------------------------------------------
        backend.signIn(user("ana"), password)
        assertEquals("Ana sigue con sus cuentas", setOf(anaAccount.id, anaSavings.id), finance.accounts(home).map { it.id }.toSet())
        assertEquals(
            "y ve solo sus movimientos",
            listOf("A ahorro", "Compra de Ana"),
            finance.movements(home, anaAccount.id, 50).map { it.description }.sorted(),
        )
        assertEquals("y su presupuesto no ha cambiado", 200_000L, finance.budget(home, period.start)?.expectedIncome)
        assertTrue("el borrado de Bruno no toca las categorías de Ana", finance.categories(home).any { it.id == anaCategory.id })
        assertEquals("ni sus metas", listOf(anaGoal.id), finance.goals(home).map { it.id })
        assertEquals("ni sus inversiones", listOf(anaHolding.id), finance.holdings(home).map { it.id })
        assertEquals(listOf(anaTrade.id), finance.trades(home).map { it.id })
        assertEquals(1, finance.recurringSeries(home).size)
        assertEquals(1, finance.extraBudgets(home).size)
    }
}
