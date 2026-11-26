package com.savethemoney.android.data

import com.savethemoney.android.ui.FinanceModel
import com.savethemoney.android.ui.PlanningModel
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.fail
import org.junit.Test
import java.math.BigDecimal
import java.time.LocalDate

/**
 * El resto de tablas (ORC-142): guardar dos veces el mismo formulario (el mismo identificador) no duplica, y un cambio
 * sobre una versión antigua avisa y recarga. Datos inventados.
 */
class IdempotentTablesTest {
    private val today = LocalDate.of(2026, 11, 5)
    private val json = Json { ignoreUnknownKeys = true }

    private suspend fun rejected(expected: String, block: suspend () -> Unit) {
        try {
            block()
            fail("debería fallar: $expected")
        } catch (e: AppError) {
            assertEquals(expected, e.message)
        }
    }

    @Test
    fun accounts() = runBlocking {
        val backend = InMemoryFinance()
        var offline = false
        val service = object : FinanceService by backend {
            override suspend fun accounts(householdId: String): List<Account> {
                if (offline) throw AppError.Network
                return backend.accounts(householdId)
            }
        }
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()
        val draft = AccountDraft("Corriente", openingMinor = 100_000)

        // La cuenta se guarda pero la respuesta no llega (falla la recarga): «Guardar» otra vez lleva el mismo borrador.
        offline = true
        model.createAccount(draft)
        assertEquals(AppError.Network.message, model.error)
        offline = false
        assertEquals("la cuenta lleva el identificador que eligió la app", draft.id, model.createAccount(draft).id)
        assertEquals("queda una sola fila", listOf(draft.id), model.accounts.map { it.id })
        rejected(TransferDraft.STORED_WITH_OTHER_DATA) { model.createAccount(draft.copy(openingMinor = 5)) }

        // Otro dispositivo la cambia mientras este tiene abierta la versión anterior.
        val read = model.accounts.single()
        assertNotNull("cada cuenta guardada tiene versión", read.updatedAt)
        val saved = backend.updateAccount(read.copy(name = "Nómina"))
        assertNotEquals(read.updatedAt, saved.updatedAt)
        rejected(AppError.MovementChanged.message) { model.updateAccount(read.copy(openingMinor = 1)) }
        rejected(AppError.MovementChanged.message) { backend.updateAccount(saved.copy(updatedAt = null)) }
        assertEquals("se ve lo que guardó el otro dispositivo, no se pisa", listOf("Nómina" to 100_000L), model.accounts.map { it.name to it.openingMinor })

        // Con la cuenta recargada, el cambio entra.
        model.updateAccount(model.accounts.single().copy(openingMinor = 1))
        assertEquals(listOf(1L), model.accounts.map { it.openingMinor })

        // Una borrada tampoco se cambia.
        val gone = model.accounts.single()
        backend.deleteAccount(gone.id)
        rejected(AppError.MovementChanged.message) { backend.updateAccount(gone) }
    }

    @Test
    fun goalsAndContributions() = runBlocking {
        val backend = InMemoryFinance()
        var lost = false
        // Con `lost`, el servidor guarda pero la respuesta no llega.
        val service = object : FinanceService by backend {
            override suspend fun createGoal(goal: Goal): Goal = backend.createGoal(goal).also { if (lost) throw AppError.Network }
            override suspend fun addContribution(contribution: GoalContribution): GoalContribution =
                backend.addContribution(contribution).also { if (lost) throw AppError.Network }
        }
        val planning = PlanningModel(Household("h", "Casa"), service, NoNotifier) { today }
        planning.load()
        // El formulario crea la meta (y su id) una vez; cada «Guardar» manda la misma.
        val goal = Goal("g1", "h", "Vacaciones", targetMinor = 200_000)
        lost = true
        rejected(AppError.Network.message) { planning.save(goal) }
        lost = false
        planning.save(goal)
        planning.save(goal)
        assertEquals("queda una sola meta", listOf("g1"), planning.goals.map { it.id })
        rejected(TransferDraft.STORED_WITH_OTHER_DATA) { planning.save(goal.copy(targetMinor = 5)) }

        // Otro dispositivo la cambia mientras este tiene abierta la versión anterior.
        val read = planning.goals.single()
        assertNotNull("cada meta guardada tiene versión", read.updatedAt)
        backend.updateGoal(read.copy(name = "Viaje"))
        rejected(AppError.MovementChanged.message) { planning.save(read.copy(targetMinor = 1)) }
        assertEquals("se ve lo que guardó el otro dispositivo, no se pisa", listOf("Viaje" to 200_000L), planning.goals.map { it.name to it.targetMinor })
        planning.save(planning.goals.single().copy(targetMinor = 300_000))
        assertEquals(listOf(300_000L), planning.goals.map { it.targetMinor })

        // La aportación lleva el id del formulario.
        lost = true
        rejected(AppError.Network.message) { planning.contribute(10_000, planning.goals.single(), today, null, "c1") }
        lost = false
        planning.contribute(10_000, planning.goals.single(), today, null, "c1")
        assertEquals("el dinero se aporta una sola vez", listOf(10_000L), planning.contributions.map { it.amountMinor })
        rejected(TransferDraft.STORED_WITH_OTHER_DATA) { planning.contribute(20_000, planning.goals.single(), today, null, "c1") }
        assertEquals(listOf(10_000L), backend.contributions("h").map { it.amountMinor })
    }

    @Test
    fun recurringSeries() = runBlocking {
        val backend = InMemoryFinance()
        var lost = false
        // Con `lost`, el servidor guarda pero la respuesta no llega.
        val service = object : FinanceService by backend {
            override suspend fun createRecurring(series: RecurringSeries): RecurringSeries =
                backend.createRecurring(series).also { if (lost) throw AppError.Network }
        }
        val planning = PlanningModel(Household("h", "Casa"), service, NoNotifier) { today }
        planning.load()
        // El formulario crea el pago fijo (y su id) una vez; cada «Guardar» manda el mismo.
        val rent = RecurringSeries("s1", "h", "Alquiler", RecurringKind.Essential, 80_000, startsOn = today.toString())
        lost = true
        rejected(AppError.Network.message) { planning.save(rent) }
        lost = false
        planning.save(rent)
        planning.save(rent)
        assertEquals("queda un solo pago fijo", listOf("s1"), planning.series.map { it.id })
        rejected(TransferDraft.STORED_WITH_OTHER_DATA) { planning.save(rent.copy(amountMinor = 90_000)) }

        // Otro dispositivo lo cambia mientras este tiene abierta la versión anterior.
        val read = planning.series.single()
        assertNotNull("cada pago fijo guardado tiene versión", read.updatedAt)
        backend.updateRecurring(read.copy(name = "Alquiler del piso"))
        rejected(AppError.MovementChanged.message) { planning.save(read.copy(amountMinor = 1)) }
        assertEquals(
            "se ve lo que guardó el otro dispositivo, no se pisa",
            listOf("Alquiler del piso" to 80_000L), planning.series.map { it.name to it.amountMinor },
        )
        planning.save(planning.series.single().copy(amountMinor = 85_000))
        assertEquals(listOf(85_000L), planning.series.map { it.amountMinor })

        // El pago fijo que nace de un gasto lleva el id del movimiento: guardar otra vez el formulario no crea otro.
        val card = backend.createAccount(AccountDraft("Tarjeta", AccountKind.CreditCard), "h")
        val draft = MovementDraft(card.id, null, today, -999, "Música", id = "m1")
        repeat(2) { backend.createRecurring(CardPurchase.series(backend.addMovement(draft, "h"), Recurrence(1, RecurrenceUnit.Month))) }
        assertEquals(listOf("m1", "s1"), backend.recurringSeries("h").map { it.id }.sorted())
    }

    @Test
    fun creditCardsAndInstallments() = runBlocking {
        val backend = InMemoryFinance()
        var lost = false
        // Con `lost`, el servidor guarda pero la respuesta no llega.
        val service = object : FinanceService by backend {
            override suspend fun saveCreditCard(terms: CreditCardTerms): CreditCardTerms =
                backend.saveCreditCard(terms).also { if (lost) throw AppError.Network }
            override suspend fun saveInstallment(installment: CardInstallment): CardInstallment =
                backend.saveInstallment(installment).also { if (lost) throw AppError.Network }
        }
        val card = backend.createAccount(AccountDraft("Tarjeta", AccountKind.CreditCard), "h")
        val purchase = backend.addMovement(MovementDraft(card.id, null, today, -60_000, "Portátil", id = "m1"), "h")
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()
        val cards = model.cards

        // Sin versión son condiciones nuevas: guardarlas otra vez no las duplica ni las cambia.
        val terms = CreditCardTerms(card.id, "h", 300_000)
        lost = true
        rejected(AppError.Network.message) { cards.save(terms) }
        lost = false
        cards.save(terms)
        assertEquals(listOf(300_000L), backend.creditCards("h").map { it.creditLimit })
        rejected(TransferDraft.STORED_WITH_OTHER_DATA) { cards.save(terms.copy(creditLimit = 5)) }

        // Otro dispositivo las cambia mientras este tiene abierta la versión anterior.
        val read = cards.terms.getValue(card.id)
        assertNotNull("las condiciones guardadas tienen versión", read.updatedAt)
        backend.saveCreditCard(read.copy(statementDay = 10))
        rejected(AppError.MovementChanged.message) { cards.save(read.copy(creditLimit = 1)) }
        val reloaded = cards.terms.getValue(card.id)
        assertEquals("se ve lo que guardó el otro dispositivo, no se pisa", 10 to 300_000L, reloaded.statementDay to reloaded.creditLimit)
        cards.save(reloaded.copy(creditLimit = 250_000))
        assertEquals(listOf(250_000L), backend.creditCards("h").map { it.creditLimit })

        // El aplazado nuevo lleva el id de su movimiento: repetirlo no crea otro.
        lost = true
        rejected(AppError.Network.message) { cards.deferPurchase(purchase, 6, card, 14.0) }
        lost = false
        cards.deferPurchase(purchase, 6, card, 14.0)
        assertEquals(listOf("m1" to 6), backend.cardInstallments("h").map { it.id to it.months })
        val plan = cards.installments.single()
        backend.saveInstallment(plan.copy(months = 9))
        rejected(AppError.MovementChanged.message) { backend.saveInstallment(plan.copy(months = 3)) }
        assertEquals(listOf(9), backend.cardInstallments("h").map { it.months })
    }

    @Test
    fun holdingsAndPlans() = runBlocking {
        val backend = InMemoryFinance()
        var lost = false
        // Con `lost`, el servidor guarda pero la respuesta no llega.
        val service = object : FinanceService by backend {
            override suspend fun createHolding(holding: Holding): Holding = backend.createHolding(holding).also { if (lost) throw AppError.Network }
            override suspend fun createPlan(plan: InvestmentPlan): InvestmentPlan = backend.createPlan(plan).also { if (lost) throw AppError.Network }
        }
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()
        val inv = model.investments
        // El formulario crea el activo (y su id) una vez; cada «Guardar» manda el mismo.
        val fund = Holding("f1", "h", "Fondo indexado", price = BigDecimal.TEN)
        lost = true
        rejected(AppError.Network.message) { inv.save(fund) }
        lost = false
        inv.save(fund)
        inv.save(fund)
        assertEquals("queda un solo activo", listOf("f1"), inv.holdings.map { it.id })
        rejected(TransferDraft.STORED_WITH_OTHER_DATA) { inv.save(fund.copy(kind = InvestmentKind.Stock)) }

        // Otro dispositivo lo cambia mientras este tiene abierta la versión anterior.
        val read = inv.holdings.single()
        assertNotNull("cada activo guardado tiene versión", read.updatedAt)
        backend.updateHolding(read.copy(name = "Fondo mundial"))
        rejected(AppError.MovementChanged.message) { inv.save(read.copy(note = "Pisado")) }
        assertEquals("se ve lo que guardó el otro dispositivo, no se pisa", listOf("Fondo mundial" to null), inv.holdings.map { it.name to it.note })
        // Apuntar un precio cambia el activo en el servidor: también su versión.
        val beforePrice = inv.holdings.single()
        backend.recordPrice(BigDecimal("12"), today, "f1")
        rejected(AppError.MovementChanged.message) { backend.updateHolding(beforePrice.copy(note = "Con el precio antiguo")) }

        // El plan lleva el id del formulario.
        val plan = InvestmentPlan("p1", "h", "f1", amountMinor = 10_000, startsOn = today.toString())
        lost = true
        rejected(AppError.Network.message) { inv.save(plan) }
        lost = false
        inv.save(plan)
        assertEquals("queda un solo plan", listOf("p1"), backend.investmentPlans("h").map { it.id })
        rejected(TransferDraft.STORED_WITH_OTHER_DATA) { inv.save(plan.copy(amountMinor = 20_000)) }
        val planRead = inv.plans.single()
        backend.updatePlan(planRead.copy(amountMinor = 15_000))
        rejected(AppError.MovementChanged.message) { inv.setPaused(true, planRead) }
        assertEquals(listOf(15_000L to null), inv.plans.map { it.amountMinor to it.pausedAt })
    }

    @Test
    fun categories() = runBlocking {
        val backend = InMemoryFinance()
        var lost = false
        // Con `lost`, el servidor guarda pero la respuesta no llega.
        val service = object : FinanceService by backend {
            override suspend fun createCategory(category: BudgetCategory): BudgetCategory =
                backend.createCategory(category).also { if (lost) throw AppError.Network }
        }
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()
        val seeded = model.categories.size
        // El formulario crea la categoría (y su id) una vez; cada «Guardar» manda la misma.
        val pets = BudgetCategory("c1", "h", "Mascotas", CategoryKind.Expense, BudgetGroup.Wants)
        lost = true
        rejected(AppError.Network.message) { model.save(pets) }
        lost = false
        model.save(pets)
        model.save(pets)
        assertEquals("queda una sola categoría nueva", seeded + 1, model.categories.size)
        rejected(TransferDraft.STORED_WITH_OTHER_DATA) { model.save(pets.copy(name = "Animales")) }

        // Otro dispositivo la cambia mientras este tiene abierta la versión anterior.
        val read = model.categories.single { it.id == "c1" }
        assertNotNull("cada categoría guardada tiene versión", read.updatedAt)
        backend.updateCategory(read.copy(name = "Perro"))
        rejected(AppError.MovementChanged.message) { model.save(read.copy(budgetGroup = BudgetGroup.Needs)) }
        val reloaded = model.categories.single { it.id == "c1" }
        assertEquals("se ve lo que guardó el otro dispositivo, no se pisa", "Perro" to BudgetGroup.Wants, reloaded.name to reloaded.budgetGroup)
        model.save(reloaded.copy(budgetGroup = BudgetGroup.Needs))
        // Las de partida también tienen versión: se pueden cambiar.
        val first = model.categories.first { it.id != "c1" }
        assertNotNull(first.updatedAt)
        model.save(first.copy(icon = "star"))
    }

    @Test
    fun extraBudgets() = runBlocking {
        val backend = InMemoryFinance()
        var lost = false
        // Con `lost`, el servidor guarda pero la respuesta no llega.
        val service = object : FinanceService by backend {
            override suspend fun saveExtraBudget(budget: ExtraBudget): ExtraBudget =
                backend.saveExtraBudget(budget).also { if (lost) throw AppError.Network }
        }
        val model = FinanceModel(Household("h", "Casa"), service, { today })
        model.load()
        val budgets = model.budgets
        budgets.load()
        // El formulario crea el presupuesto extra (y su id) una vez; cada «Guardar» manda el mismo, sin versión.
        val trip = ExtraBudget("e1", "h", "Vacaciones", 80_000, today, isFavorite = true)
        lost = true
        rejected(AppError.Network.message) { budgets.save(trip) }
        lost = false
        budgets.save(trip)
        budgets.save(trip)
        assertEquals("queda uno solo", listOf("e1"), backend.extraBudgets("h").map { it.id })
        rejected(TransferDraft.STORED_WITH_OTHER_DATA) { budgets.save(trip.copy(limit = 5)) }

        // Otro dispositivo lo cambia mientras este tiene abierta la versión anterior.
        val read = budgets.extraBudgets.single()
        assertNotNull("cada presupuesto extra guardado tiene versión", read.updatedAt)
        backend.saveExtraBudget(read.copy(name = "Viaje"))
        rejected(AppError.MovementChanged.message) { budgets.save(read.copy(limit = 1)) }
        assertEquals("se ve lo que guardó el otro dispositivo, no se pisa", listOf("Viaje" to 80_000L), budgets.extraBudgets.map { it.name to it.limit })
        budgets.save(budgets.extraBudgets.single().copy(limit = 90_000))
        assertEquals(listOf(90_000L), backend.extraBudgets("h").map { it.limit })

        // Otro favorito le quita la marca a este: también cambia su versión, como en el servidor.
        val beforeOther = budgets.extraBudgets.single()
        backend.saveExtraBudget(ExtraBudget("e2", "h", "Obra", 100, today, isFavorite = true))
        rejected(AppError.MovementChanged.message) { backend.saveExtraBudget(beforeOther.copy(limit = 2)) }
    }

    @Test
    fun recurringCharges() = runBlocking {
        val backend = InMemoryFinance()
        val account = backend.createAccount(AccountDraft("Corriente"), "h")
        backend.createRecurring(RecurringSeries("s1", "h", "Gimnasio", amountMinor = 3_200, accountId = account.id, startsOn = today.toString()))
        val planning = PlanningModel(Household("h", "Casa"), backend, NoNotifier) { today }
        planning.load()
        planning.syncCharges(emptyList())
        val pending = planning.pending.single()
        assertNotNull("cada cargo guardado tiene versión", pending.charge.updatedAt)

        // Otro dispositivo lo confirma mientras este lo tiene delante como pendiente.
        backend.confirmCharge(pending.id, MovementDraft(account.id, null, today, -3_200, "Gimnasio"))
        rejected(AppError.MovementChanged.message) { planning.skip(pending) }
        assertEquals("se ve lo que guardó el otro dispositivo, no se pisa", listOf(ChargeStatus.Confirmed), planning.charges.map { it.status })

        // Sin versión, o con la de antes, tampoco se cambia.
        val stored = backend.recurringCharges("h").single()
        rejected(AppError.MovementChanged.message) { backend.updateCharge(stored.copy(updatedAt = null), ChargeStatus.Skipped, null) }
        rejected(AppError.MovementChanged.message) { backend.updateCharge(pending.charge, ChargeStatus.Skipped, null) }
        assertNotEquals(stored.updatedAt, backend.updateCharge(stored, ChargeStatus.Skipped, null).updatedAt)
    }

    @Test
    fun accountVersionIsKeptAsTheExactServerText() {
        val row = """{"id":"a1","household_id":"h","name":"Corriente","updated_at":"2026-11-01T10:00:00.123456+00:00"}"""
        assertEquals("2026-11-01T10:00:00.123456+00:00", json.decodeFromString<Account>(row).updatedAt)
    }
}
