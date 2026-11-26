package com.savethemoney.android.ui

import com.savethemoney.android.data.AccountDraft
import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.BudgetCategory
import com.savethemoney.android.data.CreditScore
import com.savethemoney.android.data.ExtraBudget
import com.savethemoney.android.data.FinanceService
import com.savethemoney.android.data.Holding
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.InMemoryFinance
import com.savethemoney.android.data.InvestmentTrade
import com.savethemoney.android.data.Movement
import com.savethemoney.android.data.MovementDraft
import com.savethemoney.android.data.TradeCash
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.math.BigDecimal
import java.time.LocalDate

/**
 * Lo guardado sigue guardado aunque falle la recarga de después (ORC-119): la escritura no lanza (el formulario se cierra
 * y no se vuelve a pulsar «Guardar») y el fallo queda como problema de carga del modelo. Datos inventados.
 */
class RecargaFallidaTest {
    private val today = LocalDate.of(2026, 11, 5)
    private val red = AppError.Network.message

    /** Un servicio que solo falla en las lecturas que se hacen para recargar, mientras [offline] esté a true. */
    private class SinRecarga(private val backend: InMemoryFinance) : FinanceService by backend {
        var offline = false

        private fun check() {
            if (offline) throw AppError.Network
        }

        override suspend fun accounts(householdId: String) = check().let { backend.accounts(householdId) }
        override suspend fun balances(householdId: String) = check().let { backend.balances(householdId) }
        override suspend fun movements(householdId: String, accountId: String?, limit: Int): List<Movement> =
            check().let { backend.movements(householdId, accountId, limit) }
        override suspend fun categories(householdId: String) = check().let { backend.categories(householdId) }
        override suspend fun extraBudgets(householdId: String) = check().let { backend.extraBudgets(householdId) }
        override suspend fun creditScores() = check().let { backend.creditScores() }
    }

    @Test
    fun movimientoGuardadoConRecargaFallidaNoEsFalloDeGuardado() = runBlocking {
        val backend = InMemoryFinance()
        val checking = backend.createAccount(AccountDraft("Corriente", openingMinor = 100_000), "h")
        val service = SinRecarga(backend)
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()

        service.offline = true
        model.add(MovementDraft(checking.id, null, today, -1_250, "Café de prueba", id = "m1"))
        assertEquals("el fallo de la recarga se ve como problema de carga", red, model.error)
        assertEquals(1, backend.movements("h", null, 50).size)

        // «Reintentar» vuelve a cargar, no a guardar.
        service.offline = false
        model.load()
        assertNull(model.error)
        assertEquals(listOf("m1"), model.recent.map { it.id })
        assertEquals(98_750L, model.balances[checking.id])
    }

    @Test
    fun compraConCargoGuardadaConRecargaFallidaNoEsFalloDeGuardado() = runBlocking {
        val backend = InMemoryFinance()
        val checking = backend.createAccount(AccountDraft("Corriente", openingMinor = 100_000), "h")
        val fund = backend.createHolding(Holding("", "h", "Fondo de prueba", price = BigDecimal("10")))
        val service = SinRecarga(backend)
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()

        service.offline = true
        val trade = InvestmentTrade("t1", "h", fund.id, today.toString(), quantity = BigDecimal("2"), price = BigDecimal("10"))
        model.addTrade(trade, TradeCash(checking.id, null, -2_000, "Compra de prueba"))
        assertEquals(red, model.error)
        assertEquals(listOf("t1"), model.investments.trades.map { it.id })
        assertEquals(1, backend.trades("h").size)
        assertEquals(1, backend.movements("h", null, 50).size)
    }

    @Test
    fun categoriaGuardadaConRecargaFallidaSeVeYNoSeDuplica() = runBlocking {
        val backend = InMemoryFinance()
        val service = SinRecarga(backend)
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()
        val before = backend.categories("h").size

        service.offline = true
        model.save(BudgetCategory("nueva", "h", "Mascotas"))
        assertEquals(red, model.error)
        // Ya está en la lista: guardarla otra vez la actualiza, no crea otra.
        val saved = model.categories.single { it.name == "Mascotas" }
        service.offline = false
        model.save(saved.copy(name = "Mascotas y veterinario"))
        assertEquals(before + 1, backend.categories("h").size)
    }

    @Test
    fun presupuestoExtraYPuntuacionGuardadosConRecargaFallidaNoLanzan() = runBlocking {
        val backend = InMemoryFinance()
        val service = SinRecarga(backend)
        val household = Household("h", "Casa")
        val budgets = BudgetModel(household, service, com.savethemoney.android.data.NoNotifier, { today })
        val tracking = TrackingModel(household, service, { today })

        service.offline = true
        budgets.save(ExtraBudget("e1", "h", "Viaje de prueba", 50_000, startsOn = today))
        assertEquals(red, budgets.error)
        assertEquals(listOf("e1"), budgets.extraBudgets.map { it.id })

        tracking.add(CreditScore("", 700, recordedOn = today.toString()))
        assertEquals(red, tracking.error)
        assertEquals(1, tracking.scores.size)
        assertEquals(1, backend.creditScores().size)
    }
}
