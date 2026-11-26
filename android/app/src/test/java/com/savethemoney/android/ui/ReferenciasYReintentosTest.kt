package com.savethemoney.android.ui

import com.savethemoney.android.data.AccountDraft
import com.savethemoney.android.data.AccountKind
import com.savethemoney.android.data.CategoryKind
import com.savethemoney.android.data.CreditCardTerms
import com.savethemoney.android.data.Goal
import com.savethemoney.android.data.Holding
import com.savethemoney.android.data.Household
import com.savethemoney.android.data.ImportMarks
import com.savethemoney.android.data.InMemoryFinance
import com.savethemoney.android.data.RecurringSeries
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

/**
 * ORC-147: borrar una cuenta o una categoría no deja versiones viejas en los otros modelos, y repetir una importación CSV
 * no duplica los pagos fijos que crea. Como ReferenciasYReintentosTests de iOS. Datos inventados.
 */
class ReferenciasYReintentosTest {
    private val hoy = LocalDate.of(2026, 11, 5)

    @Test
    fun trasBorrarUnaCuentaLaSiguienteEdicionNoAvisaDeUnCambio() = runBlocking {
        val service = InMemoryFinance()
        val model = FinanceModel(Household("h", "Casa"), service, { hoy })
        val cuenta = service.createAccount(AccountDraft("Corriente", openingMinor = 100_000), "h")
        val tarjeta = service.createAccount(AccountDraft("Tarjeta", AccountKind.CreditCard), "h")
        model.load()

        // Todo lo que apunta a la cuenta con `on delete set null` en el servidor.
        model.planning.save(Goal("", "h", "Viaje", targetMinor = 50_000, accountId = cuenta.id))
        model.planning.save(RecurringSeries("", "h", "Luz", amountMinor = 4_000, accountId = cuenta.id, startsOn = "2026-11-05"))
        model.investments.save(Holding("", "h", "Fondo", accountId = cuenta.id))
        model.cards.save(CreditCardTerms(tarjeta.id, "h", creditLimit = 300_000, payFromAccountId = cuenta.id))

        model.deleteAccount(cuenta)

        val goal = model.planning.goals.single()
        assertNull("se ve sin la cuenta borrada", goal.accountId)
        model.planning.save(goal.copy(name = "Viaje a Lisboa"))
        val series = model.planning.series.single()
        assertNull(series.accountId)
        model.planning.save(series.copy(name = "Luz y gas"))
        val fondo = model.investments.holdings.single()
        assertNull(fondo.accountId)
        model.investments.save(fondo.copy(name = "Fondo indexado"))
        val terms = model.cards.terms.getValue(tarjeta.id)
        assertNull(terms.payFromAccountId)
        model.cards.save(terms.copy(creditLimit = 400_000))
        assertEquals(listOf("Viaje a Lisboa"), service.goals("h").map { it.name })
    }

    @Test
    fun trasBorrarUnaCategoriaLaSiguienteEdicionNoAvisaDeUnCambio() = runBlocking {
        val service = InMemoryFinance()
        val model = FinanceModel(Household("h", "Casa"), service, { hoy })
        model.load()
        val categoria = model.categories.first { it.kind == CategoryKind.Expense }
        model.planning.save(RecurringSeries("", "h", "Gimnasio", amountMinor = 3_500, categoryId = categoria.id, startsOn = "2026-11-05"))

        model.delete(categoria)

        val series = model.planning.series.single()
        assertNull("se ve sin la categoría borrada", series.categoryId)
        model.planning.save(series.copy(amountMinor = 3_900))
        assertEquals(listOf(3_900L), service.recurringSeries("h").map { it.amountMinor })
    }

    /**
     * El alta de un pago fijo llegó al servidor pero se perdió la respuesta, y la persona repite la importación. Cada
     * intento hace un plan nuevo (sin id): el id fijado al empezar es el que se manda otra vez.
     */
    @Test
    fun repetirLaImportacionNoDuplicaLosPagosFijos() = runBlocking {
        val service = InMemoryFinance()
        val model = FinanceModel(Household("h", "Casa"), service, { hoy })
        fun plan() = listOf(RecurringSeries("", "h", "Netflix", amountMinor = 1_299, startsOn = "2026-11-05"))
        val ids = mutableMapOf<String, String>()

        val primero = ImportMarks.pinned(plan(), ids)
        service.createRecurring(primero.single())

        val segundo = ImportMarks.pinned(plan(), ids)
        assertEquals(primero.map { it.id }, segundo.map { it.id })
        model.planning.save(segundo)
        assertEquals("queda un solo pago fijo", listOf("Netflix"), service.recurringSeries("h").map { it.name })
    }
}
