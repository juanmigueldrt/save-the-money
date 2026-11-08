package com.savethemoney.android.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

class FinanceTest {
    private val csv = "Titular;Ana\nFecha Operación;Fecha Valor;Concepto;Importe;Saldo\n" +
        "28/10/2026;29/10/2026;\"Café; Ñandú\";-1.234,56;10,00\n28/10/2026;29/10/2026;Otro;-1234,56;\n" +
        "mal;;x;1;\n31/02/2026;;y;1;\n01/11/2026;;;2150;\r\n"

    @Test
    fun csvDetectsHeaderAndParsesRows() {
        val table = CsvTable.parse(csv)
        assertEquals(';', table.delimiter)
        val mapping = CsvMapping.detect(table)!!
        assertEquals(1, mapping.headerRow)
        assertEquals(0, mapping.date)
        assertEquals(2, mapping.description)
        assertEquals(AmountColumns.Signed(3), mapping.amount)
        val rows = CsvImporter.rows(table, mapping, "a")
        assertEquals("Café; Ñandú", rows[0].draft!!.description)
        assertEquals(-123456L, rows[0].draft!!.amountMinor)
        assertEquals("Fecha no reconocida: «mal»", rows[2].issue)
        assertEquals("Fecha no reconocida: «31/02/2026»", rows[3].issue)
        assertEquals("Sin concepto", rows[4].draft!!.description)
    }

    @Test
    fun hashMatchesIosForRepeatedRows() {
        val table = CsvTable(listOf(listOf("28/10/2026", "Café Ñandú", "-1,50"), listOf("28/10/2026", "CAFE  nandu", "-1,50")), ';')
        val rows = CsvImporter.rows(table, CsvMapping(null, 0, 1, AmountColumns.Signed(2)), "a")
        // SHA-256 calculado aparte en Swift para "2026-10-28|-150|cafe nandu|0" y "…|1".
        assertEquals("2c091b8e832c97f4400c357099be8163fa8bd727eb978258c5d84d826ad23206", rows[0].draft!!.importHash)
        assertEquals("cee82ebb5c6e51f05cb7c6d1ef700b1c28c60567be97ba206fd3d025583195bf", rows[1].draft!!.importHash)
    }

    @Test
    fun splitColumnsAndWindowsEncoding() {
        val table = CsvTable.parse("Fecha,Descripción,Cargo,Abono\n2026-10-28,Luz,\"12,50\",\n2026-10-29,Bizum,,\"3,00\"\n")
        val mapping = CsvMapping.detect(table)!!
        assertEquals(AmountColumns.Split(2, 3), mapping.amount)
        assertEquals(listOf(-1250L, 300L), CsvImporter.rows(table, mapping, "a").map { it.draft!!.amountMinor })
        assertEquals("Nómina", CsvTable.decode(byteArrayOf(0x4E, 0xF3.toByte(), 0x6D, 0x69, 0x6E, 0x61)))
    }

    @Test
    fun dateOrders() {
        assertEquals(LocalDate.of(2026, 10, 28), DateOrder.DayMonthYear.parse("28-10-26 10:00"))
        assertEquals(LocalDate.of(2026, 10, 28), DateOrder.DayMonthYear.parse("2026.10.28"))
        assertEquals(LocalDate.of(2026, 10, 28), DateOrder.MonthDayYear.parse("10/28/2026"))
        assertNull(DateOrder.DayMonthYear.parse("10/28/2026"))
    }

    @Test
    fun drafts() {
        val day = LocalDate.of(2026, 1, 1)
        assertEquals("Escribe un concepto.", MovementDraft("a", null, day, 1, " ").issue)
        assertEquals("El importe no puede ser cero.", MovementDraft("a", null, day, 0, "x").issue)
        assertEquals("Ponle un nombre a la cuenta.", AccountDraft("  ").issue)
        val other = BudgetCategory("2", "h", "Ocio")
        assertEquals("Ya hay una categoría de gasto con ese nombre.", BudgetCategory("1", "h", " ocio ").issue(listOf(other)))
    }

    @Test
    fun monthEndBalancesUndoLaterMovements() {
        fun m(day: String, amount: Long) = Movement("i", "h", "a", null, day, amount, "x")
        val series = monthEndBalances(1000, listOf(m("2026-11-02", 300), m("2026-10-15", -100)), LocalDate.of(2026, 11, 5), 3)
        assertEquals(listOf(800L, 700L, 1000L), series)
    }

    @Test
    fun inMemoryRulesMatchServer() = runBlocking {
        val f = InMemoryFinance()
        val cat = f.categories("h").first { it.name == "Ocio" }
        val a = f.createAccount(AccountDraft("A", openingMinor = 1000), "h")
        val d = MovementDraft(a.id, cat.id, LocalDate.of(2026, 1, 1), -100, "x", importHash = "e".repeat(64))
        assertEquals(ImportResult(1, 1), f.importMovements(listOf(d, d), "h"))
        assertEquals(900L, f.balances("h")[a.id])
        f.deleteCategory(cat.id)
        assertNull(f.movements("h", null, 10).single().categoryId)
        f.deleteAccount(a.id)
        assertEquals(0, f.movements("h", null, 10).size)
    }
}
