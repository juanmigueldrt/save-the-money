package com.savethemoney.android.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/** Mismos casos que MerchantTests.swift, con descripciones inventadas. */
class MerchantTest {
    private val hogar = "h1"
    private fun cat(id: String, name: String, kind: CategoryKind = CategoryKind.Expense) = BudgetCategory(id, hogar, name, kind)

    @Test
    fun displayIsAlwaysUppercase() {
        assertEquals("COMPRA EN FARMACIA ÑANDÚ", MovementText.display("Compra en farmacia ñandú"))
    }

    @Test
    fun recognisesTheExamplesJeanGave() {
        assertEquals("Farmacia", MerchantDirectory.match("COMPRA TARJ. FARMACIA LDO PEREZ")?.name)
        assertEquals("Apple", MerchantDirectory.match("Apple.com/bill ITUNES.COM")?.name)
        assertEquals("Google One", MerchantDirectory.match("GOOGLE *Google One")?.name)
        assertEquals("Supermercado", MerchantDirectory.match("Supermercado La Esquina")?.name)
        assertEquals("Mercadona", MerchantDirectory.match("PAGO MOVIL EN MERCADONA, MADRID")?.name)
    }

    @Test
    fun longestKeywordWinsAndWholeWordsOnly() {
        assertEquals("Uber Eats", MerchantDirectory.match("UBER EATS PEDIDO")?.name)
        assertEquals("Uber", MerchantDirectory.match("UBER TRIP")?.name)
        assertEquals("Apple Store", MerchantDirectory.match("APPLE STORE GRAN VIA")?.name)
        assertNull(MerchantDirectory.match("PINEAPPLE JUICE BAR"))
        assertNull(MerchantDirectory.match(""))
    }

    @Test
    fun logoOnlyCarriesTheDomain() {
        assertEquals("https://www.google.com/s2/favicons?domain=apple.com&sz=128", MerchantDirectory.match("APPLE.COM/BILL")?.logoUrl)
        assertNull(MerchantDirectory.match("FARMACIA CENTRAL")?.logoUrl)
        val apple = MerchantDirectory.match("APPLE.COM/BILL")!!
        val fake = "pk_" + "ejemplo" // inventada; partida para que gitleaks no la tome por real
        assertEquals("https://img.logo.dev/apple.com?token=$fake&size=128&format=png&retina=true", apple.logoUrl(" $fake "))
        assertEquals(apple.logoUrl, apple.logoUrl("sk_secreta"))
        assertEquals(apple.logoUrl, apple.logoUrl(""))
        val defaults = setOf("Vivienda", "Supermercado", "Suministros", "Transporte", "Salud", "Seguros", "Restaurantes", "Ocio", "Compras", "Viajes", "Suscripciones")
        MerchantDirectory.all.forEach { assertTrue(it.name, it.category in defaults); assertFalse(it.name, it.keywords.isEmpty()) }
    }

    @Test
    fun suggestsAndLearnsOnlyForExpenses() {
        val salud = cat("salud", "Salud")
        val ocio = cat("ocio", "Ocio")
        val categorias = listOf(cat("ing", "Salud", CategoryKind.Income), salud, ocio)
        assertEquals(salud, MerchantDirectory.suggestedCategory("Farmacia", true, categorias))
        assertNull(MerchantDirectory.suggestedCategory("Farmacia", false, categorias))
        fun mov(texto: String, categoria: String?, dia: Int) =
            Movement("m$dia", hogar, "a", categoria, "2026-10-%02d".format(dia), -3000, texto)
        val learner = CategoryLearner(listOf(
            mov("RECIBO GIMNASIO BARRIO 0012345", "salud", 1),
            mov("RECIBO GIMNASIO BARRIO 0067890", "ocio", 5),
            mov("FARMACIA CENTRAL", "ocio", 2),
        ))
        assertEquals(ocio, MerchantDirectory.suggestedCategory("Recibo gimnasio barrio 0099999", true, categorias, learner))
        assertEquals(ocio, MerchantDirectory.suggestedCategory("FARMACIA LA PLAZA", true, categorias, learner))
        assertNull(learner.categoryId("12345 67890"))
    }

    @Test
    fun categorizeKeepsChosenCategories() {
        val super_ = cat("s", "Supermercado")
        val dia = LocalDate.of(2026, 10, 3)
        val filas = listOf(
            CsvImportRow(2, MovementDraft("a", null, dia, -2350, "Lidl Avda Sol", importHash = "x")),
            CsvImportRow(3, MovementDraft("a", "otra", dia, -900, "Lidl")),
            CsvImportRow(4, issue = "Importe vacío o no válido"),
        )
        val r = MerchantDirectory.categorize(filas, listOf(super_))
        assertEquals("s", r[0].draft?.categoryId)
        assertEquals("x", r[0].draft?.importHash)
        assertEquals("otra", r[1].draft?.categoryId)
        assertNull(r[2].draft)
    }
}
