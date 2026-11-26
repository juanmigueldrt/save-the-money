package com.savethemoney.android.data

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth

/** Fase B, como PhaseBTests de iOS: excluidos, revisados, etiquetas, beneficiario, masiva, parecidos, cuentas y CSV. */
class PhaseBTest {
    private val home = "h"
    private val account = "a"
    private var n = 0
    private fun day(y: Int, m: Int, d: Int) = LocalDate.of(y, m, d)

    private fun movement(
        text: String, minor: Long, on: LocalDate = day(2026, 11, 10), category: String? = null,
        excluded: Boolean = false, tags: List<String> = emptyList(), payee: String? = null,
    ) = Movement("m${n++}", home, account, category, on.toString(), minor, text, excluded = excluded, payee = payee, tags = tags)

    @Test
    fun tagsNormalizeAndValidate() {
        assertEquals(listOf("viaje", "cumple", "boda-ana"), MovementTags.normalize("#Viaje, cumple  viaje;Boda-Ana"))
        assertEquals(emptyList<String>(), MovementTags.normalize("  ,, "))
        assertEquals("año", MovementTags.clean("#Año!"))
        assertNull(MovementTags.issue(listOf("viaje", "año_2026")))
        assertNotNull(MovementTags.issue(listOf("Viaje")))
        assertNotNull(MovementTags.issue(listOf("con espacio")))
        assertNotNull(MovementTags.issue(listOf("a".repeat(31))))
        assertNotNull(MovementTags.issue((1..11).map { "t$it" }))
        assertNotNull(MovementDraft(account, null, day(2026, 11, 1), -100, "CAFE", tags = listOf("Mal")).issue)
        assertNotNull(MovementDraft(account, null, day(2026, 11, 1), -100, "CAFE", payee = "x".repeat(81)).issue)
        assertEquals("Tienda del barrio", Payee.clean("  Tienda   del  barrio "))
        assertNull(Payee.clean("   "))
    }

    @Test
    fun tagsAndPayeesByUse() {
        val list = listOf(
            movement("A", -100, tags = listOf("casa", "obra"), payee = "Ferretería"),
            movement("B", -100, tags = listOf("obra"), payee = "ferretería"),
            movement("C", -100, tags = listOf("viaje"), payee = "Hotel"),
        )
        assertEquals(listOf("obra", "casa", "viaje"), MovementTags.all(list))
        assertEquals(2, Payee.all(list).size)
        assertEquals("Hotel", Payee.all(list).last())
    }

    @Test
    fun excludedSkipBudgetReportsAndDayTotals() {
        val food = BudgetCategory("food", home, "Comida", CategoryKind.Expense, BudgetGroup.Needs)
        val list = listOf(movement("SUPER", -5_000, category = food.id), movement("REGALO DEVUELTO", -2_000, category = food.id, excluded = true))
        val range = day(2026, 11, 1)..day(2026, 11, 30)
        assertEquals(5_000L, SpendingReport(list, listOf(food), range).total)
        assertEquals(5_000L, BudgetReport(null, range, listOf(food), list).totalSpent)
        assertEquals(-5_000L, MovementDay.group(list, listOf(food)).first().total)
        assertNull("un excluido no enseña categorías", CategoryLearner(list.filter { it.excluded }).categoryId("REGALO DEVUELTO"))
        // Pero el filtro de excluidos los enseña para poder volver a incluirlos.
        val excluded = MovementFilter(status = MovementStatusFilter.Excluded).apply(list, listOf(food), day(2026, 11, 15))
        assertEquals(listOf("REGALO DEVUELTO"), excluded.map { it.description })
    }

    @Test
    fun reviewedAndTagFilters() {
        val today = day(2026, 11, 15)
        val list = listOf(
            movement("LUZ", -6_000, tags = listOf("casa")).copy(reviewedAt = "2026-11-10T10:00:00Z"),
            movement("CINE", -1_200, tags = listOf("ocio"), payee = "Cines Centro"),
        )
        fun names(f: MovementFilter) = f.apply(list, emptyList(), today).map { it.description }
        assertEquals(listOf("CINE"), names(MovementFilter(status = MovementStatusFilter.Unreviewed)))
        assertEquals(listOf("LUZ"), names(MovementFilter(status = MovementStatusFilter.Reviewed)))
        assertEquals(listOf("LUZ"), names(MovementFilter(tag = "casa")))
        assertEquals(1, MovementFilter(tag = "casa").activeCount)
        assertEquals(listOf("CINE"), names(MovementFilter(search = "#ocio")))
        assertEquals(listOf("CINE"), names(MovementFilter(search = "centro")))
    }

    @Test
    fun bulkEdit() {
        val now = Instant.ofEpochSecond(1_800_000_000)
        val already = movement("B", -200, tags = listOf("viaje")).copy(reviewedAt = "1970-01-01T00:00:01Z")
        val list = listOf(movement("A", -100, tags = listOf("casa")), already)
        val edit = MovementBulkEdit(
            bookedOn = day(2026, 11, 3), categoryId = Change.Set("cat"), accountId = "otra",
            reviewed = true, addTags = listOf("viaje"), removeTags = listOf("casa"),
        )
        val changed = edit.changes(list, now)
        assertEquals(2, changed.size)
        assertEquals(listOf("viaje"), changed[0].tags)
        assertEquals(now.toString(), changed[0].reviewedAt)
        assertEquals("conserva la fecha de revisado", "1970-01-01T00:00:01Z", changed[1].reviewedAt)
        assertTrue(changed.all { it.accountId == "otra" && it.categoryId == "cat" && it.bookedOn == "2026-11-03" })
        // Quitar la categoría y no tocar lo que ya está igual.
        assertEquals(0, MovementBulkEdit(categoryId = Change.Set(null)).changes(list).size)
        assertEquals(2, MovementBulkEdit(excluded = true).changes(list).size)
        assertTrue(MovementBulkEdit().isEmpty)
        assertNull(MovementBulkEdit(reviewed = false).applied(already).reviewedAt)
        assertEquals(MovementTags.MAX_COUNT, MovementBulkEdit(addTags = (1..12).map { "t$it" }).applied(already).tags.size)
    }

    @Test
    fun similarMovements() {
        val first = movement("COMPRA MERCADONA 1234", -3_000)
        val list = listOf(
            first,
            movement("Compra Mercadona 99", -1_500),
            movement("COMPRA MERCADONA", -900, category = "food"),
            movement("DEVOLUCION MERCADONA", 900),
            movement("COMPRA LIDL", -2_000),
        )
        assertEquals("compra mercadona tarj", SimilarMovements.key("COMPRA MERCADONA 1234 TARJ. 5678"))
        assertEquals(listOf("Compra Mercadona 99"), SimilarMovements.matches(first, list, "food").map { it.description })
        assertEquals(listOf("COMPRA MERCADONA"), SimilarMovements.matches(first, list, null).map { it.description })
        assertEquals("cafe", SimilarMovements.key("Café 2"))
    }

    @Test
    fun groupedSpending() {
        val transfer = BudgetCategory("t", home, "Traspaso", CategoryKind.Transfer)
        val list = listOf(
            movement("HOTEL", -20_000, tags = listOf("viaje"), payee = "Hotel Sol"),
            movement("TREN", -5_000, tags = listOf("viaje", "trabajo")),
            movement("DIETAS", 3_000, tags = listOf("trabajo")),
            movement("OCULTO", -9_000, excluded = true, tags = listOf("viaje")),
            movement("A AHORRO", -10_000, category = transfer.id, tags = listOf("viaje")),
            movement("FUERA", -1_000, on = day(2026, 10, 1), tags = listOf("viaje")),
        )
        val range = day(2026, 11, 1)..day(2026, 11, 30)
        val byTag = GroupedSpending.report(GroupedSpending.Grouping.Tag, list, listOf(transfer), range)
        assertEquals(listOf("viaje", "trabajo"), byTag.map { it.title })
        assertEquals(25_000L, byTag[0].spent)
        assertEquals(5_000L, byTag[1].spent)
        assertEquals(3_000L, byTag[1].income)
        assertEquals(2, byTag[1].count)
        val byPayee = GroupedSpending.report(GroupedSpending.Grouping.Payee, list, listOf(transfer), range)
        assertEquals(listOf("Hotel Sol"), byPayee.map { it.title })
    }

    /** Un traspaso importado (dos movimientos sin categoría, mismo día, importes opuestos, cuentas distintas) no es gasto ni ingreso. */
    @Test
    fun groupedSpendingSkipsUncategorizedTransfers() {
        val list = listOf(
            movement("A AHORRO", -10_000, tags = listOf("ahorro")),
            movement("DE NOMINA", 10_000, tags = listOf("ahorro")).copy(accountId = "otra"),
            movement("HUCHA", -700, tags = listOf("ahorro")),
        )
        val byTag = GroupedSpending.report(GroupedSpending.Grouping.Tag, list, emptyList(), day(2026, 11, 1)..day(2026, 11, 30))
        assertEquals(listOf(700L), byTag.map { it.spent })
        assertEquals(listOf(0L), byTag.map { it.income })
    }

    @Test
    fun defaultAccountAndNetWorth() {
        val a = Account("a", home, "Nómina", openingMinor = 10_000)
        val b = Account("b", home, "Tarjeta", isDefault = true)
        val c = Account("c", home, "Coche", AccountKind.Savings, openingMinor = 500_000, includeInNetWorth = false)
        assertEquals("b", listOf(a, b, c).defaultAccount()?.id)
        assertEquals("a", listOf(a, b.copy(archivedAt = "2026-11-01T00:00:00Z"), c).defaultAccount()?.id)
        assertNull(emptyList<Account>().defaultAccount())
        assertEquals(10_000L, NetWorth.current(listOf(a, c), emptyMap(), day(2026, 11, 15)).net)
        assertEquals(10_000L, NetWorth.history(listOf(a, c), emptyList(), 1, YearMonth.of(2026, 11)).last().net)
    }

    @Test
    fun inMemoryKeepsOneDefaultAccountAndNewFields() = runBlocking {
        val f = InMemoryFinance()
        val first = f.createAccount(AccountDraft("Corriente"), home)
        val second = f.createAccount(AccountDraft("Ahorro"), home)
        f.updateAccount(first.copy(isDefault = true))
        f.updateAccount(second.copy(isDefault = true))
        assertEquals(listOf(second.id), f.accounts(home).filter { it.isDefault }.map { it.id })

        val draft = MovementDraft(second.id, null, day(2026, 11, 1), -1_000, "PRUEBA", excluded = true, payee = "  Tienda  ", tags = listOf("prueba"))
        val saved = f.addMovement(draft, home)
        assertTrue(saved.excluded)
        assertEquals("Tienda", saved.payee)
        assertEquals(listOf("prueba"), saved.tags)
        val updated = f.updateMovement(saved.copy(reviewedAt = Instant.now().toString(), excluded = false))
        assertTrue(updated.isReviewed)
        assertFalse(updated.excluded)
        // El excluido sigue contando en el saldo.
        assertEquals(-1_000L, f.balances(home)[second.id])
        // Y se copia al deshacer un borrado (con otro identificador: es un movimiento nuevo).
        assertEquals(draft.copy(payee = "Tienda", excluded = false), updated.toDraft().copy(importHash = null, id = draft.id))
    }

    @Test
    fun savedCsvFormat() {
        val table = CsvTable.parse("Banco de prueba\nFecha;Concepto;Cargo;Abono\n01/11/2026;CAFE;1,50;\n02/11/2026;NOMINA;;1000\n")
        val mapping = CsvMapping.detect(table)!!
        val format = CsvSavedFormat.of(table, mapping, account)
        assertEquals(mapping, format.mapping)
        val saved = CsvSavedFormat.remember(format, emptyList())
        assertEquals(account, CsvSavedFormat.match("Otro titular\nFecha;Concepto;Cargo;Abono\n05/11/2026;PAN;1;\n", saved)?.first?.accountId)
        assertNull(CsvSavedFormat.match("Date,Amount,Text\n2026-11-01,1,a\n", saved))
        // Guardar otra vez el mismo formato no lo duplica.
        assertEquals(1, CsvSavedFormat.remember(format, saved).size)
        val json = Json.encodeToString(saved)
        assertEquals(saved, Json.decodeFromString<List<CsvSavedFormat>>(json))
    }

    @Test
    fun savedCsvFormatRemembersDelimiter() {
        // Separador elegido a mano (coma): el siguiente archivo del banco se lee con él.
        val table = CsvTable.parse("Banco de prueba\nFecha,Concepto,Importe\n01/11/2026,CAFE,-1.50\n02/11/2026,NOMINA,1000\n", ',')
        val format = CsvSavedFormat.of(table, CsvMapping.detect(table)!!, account)
        assertEquals(',', format.delimiter)
        val saved = CsvSavedFormat.remember(format, emptyList())
        val sameBank = "Otro titular\nFecha,Concepto,Importe\n05/11/2026,PAN,-2.00\n"
        val (_, found) = CsvSavedFormat.match(sameBank, saved)!!
        assertEquals(',', found.delimiter)
        assertEquals(CsvTable.parse(sameBank, ',').rows, found.rows)
        // Un formato guardado sin separador (anterior a recordarlo) se lee con el detectado.
        assertEquals(CsvTable.parse(sameBank).delimiter, CsvSavedFormat.match(sameBank, listOf(format.copy(delimiter = null)))!!.second.delimiter)
    }

    @Test
    fun csvRowReview() {
        val table = CsvTable.parse("Fecha;Concepto;Importe\n01/11/2026;CAFE;-1,50\n02/11/2026;REGALO;-30\n03/11/2026;NOMINA;1000\n")
        val rows = CsvImporter.rows(table, CsvMapping.detect(table)!!, account)
        var review = CsvRowReview(
            skipped = setOf(rows[0].line), excluded = setOf(rows[1].line), categories = mapOf(rows[1].line to "regalo"),
        )
        val result = review.apply(rows)
        assertEquals(listOf("REGALO", "NOMINA"), result.map { it.draft?.description })
        assertEquals(true, result[0].draft?.excluded)
        assertEquals("regalo", result[0].draft?.categoryId)
        assertEquals(false, result[1].draft?.excluded)
        review = review.keep(setOf(rows[1].line))
        assertTrue(review.skipped.isEmpty())
        assertEquals(setOf(rows[1].line), review.excluded)
    }
}
