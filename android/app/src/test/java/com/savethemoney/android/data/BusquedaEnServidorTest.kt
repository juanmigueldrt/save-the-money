package com.savethemoney.android.data

import io.github.jan.supabase.annotations.SupabaseExperimental
import io.github.jan.supabase.postgrest.PropertyConversionMethod
import io.github.jan.supabase.postgrest.query.PostgrestRequestBuilder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * ORC-85: la búsqueda de la lista va al servidor como filtro `or=(…)` de PostgREST. El texto del usuario va entre comillas y
 * con los comodines de LIKE escapados, para que nada de lo que escriba se lea como sintaxis. Los resultados esperados están
 * escritos a mano a partir de la gramática de PostgREST (los mismos que BusquedaEnServidorTests de iOS).
 */
class BusquedaEnServidorTest {
    @OptIn(SupabaseExperimental::class)
    private fun params(search: String?, after: Movement? = null, categories: List<BudgetCategory> = emptyList()): Map<String, List<String>> {
        val builder = PostgrestRequestBuilder(PropertyConversionMethod.NONE)
        builder.movementPage("h1", null, search?.let { MovementSearch.of(it, categories)!! }, after)
        return builder.params
    }

    private fun texto(valor: String) = "description.ilike.$valor,notes.ilike.$valor,payee.ilike.$valor"

    @Test
    fun caracteresDeLikeYDePostgrestVanEscapados() {
        // 50 % _ a \ b " c , ( d ) . e * f : g
        // LIKE:      50\%\_a\\b"c,(d).e_f:g      (el * pasa a _: PostgREST no deja escaparlo)
        // Comillas:  cada \ pasa a \\ y cada " a \"
        val valor = """"*50\\%\\_a\\\\b\"c,(d).e_f:g*""""
        assertEquals(listOf("(${texto(valor)})"), params("""50%_a\b"c,(d).e*f:g""")["or"])
    }

    @Test
    fun soloComillasYBarras() {
        val valor = """"*\\\\\"*""""
        assertEquals(listOf("(${texto(valor)})"), params("""\"""")["or"])
    }

    @Test
    fun parentesisYComasNoCierranElFiltro() {
        assertEquals(listOf("(${texto("\"*a),or(id.neq.0*\"")})"), params("a),or(id.neq.0")["or"])
    }

    @Test
    fun espaciosAlosLadosNoSeBuscan() {
        assertEquals(listOf("(${texto("\"*pan*\"")},tags.cs.{pan})"), params("   pan \n")["or"])
    }

    @Test
    fun etiquetaCategoriaEImporte() {
        val comida = BudgetCategory("0000000A-0000-0000-0000-0000000000C1", "h1", "Comida")
        assertEquals(listOf("(${texto("\"*#Viaje*\"")},tags.cs.{viaje})"), params("#Viaje", categories = listOf(comida))["or"])
        assertEquals(
            listOf("(${texto("\"*comi*\"")},tags.cs.{comi},category_id.in.(0000000a-0000-0000-0000-0000000000c1))"),
            params("comi", categories = listOf(comida))["or"],
        )
        assertEquals(listOf("(${texto("\"*12,50*\"")},amount_minor.in.(1250,-1250))"), params("12,50")["or"])
        assertEquals(listOf("(${texto("\"*-12,50*\"")},amount_minor.eq.-1250)"), params("-12,50")["or"])
    }

    /** ORC-146: las mismas cadenas que el CI manda al Supabase local (supabase/tests/api/filtros_postgrest.py). */
    @Test
    fun filtrosCompartidosConIosYConElServidor() {
        // Gradle corre las pruebas desde `android/app`.
        val file = Json.parseToJsonElement(File("../../testdata/vectors/postgrest_filters.json").readText()).jsonObject
        val search = file["search"]!!.jsonArray
        val movements = file["movements"]!!.jsonArray
        assertFalse(search.isEmpty())
        assertFalse(movements.isEmpty())
        fun JsonElement.str(key: String) = jsonObject[key]!!.jsonPrimitive.content
        for (v in search) {
            assertEquals(v.str("name"), v.str("filter"), movementSearchFilter(MovementSearch.of(v.str("input"), emptyList())!!))
        }
        for (m in movements) {
            val movement = Movement(m.str("id"), "h1", "a1", null, m.str("bookedOn"), -1, "x")
            assertEquals(m.str("key"), m.str("cursor"), movementAfterFilter(movement))
        }
    }

    @Test
    fun cursorEsDiaAnteriorOMismoDiaYMenorIdJuntoALaBusqueda() {
        val ultimo = Movement("ABCDEF00-0000-0000-0000-000000000001", "h1", "a1", null, "2021-03-05", -1, "x")
        val filtros = params("pan", ultimo)
        assertEquals(listOf("eq.h1"), filtros["household_id"])
        assertEquals(
            "la búsqueda y el cursor van en dos or=(…), que PostgREST junta con AND",
            listOf(
                "(${texto("\"*pan*\"")},tags.cs.{pan})",
                "(booked_on.lt.2021-03-05,and(booked_on.eq.2021-03-05,id.lt.abcdef00-0000-0000-0000-000000000001))",
            ),
            filtros["or"],
        )
    }

    /** ORC-70: la descarga por fechas va con el día descendente y el id ascendente; el día máximo viaja aparte, como `booked_on=lte.`. */
    @Test
    fun cursorDeLaDescargaPorFechasEsDiaAnteriorOMayorId() {
        val ultimo = Movement("ABCDEF00-0000-0000-0000-000000000001", "h1", "a1", null, "2021-03-05", -1, "x")
        assertEquals("booked_on.lt.2021-03-05,id.gt.abcdef00-0000-0000-0000-000000000001", movementDownloadAfterFilter(ultimo))
    }

    @Test
    fun busquedaQuitaEspaciosYControlesYSeRecortaA100() {
        assertNull(MovementSearch.of("   \n\t ", emptyList()))
        assertNull(MovementSearch.of("\u0000\u0007", emptyList()))
        assertEquals("café", MovementSearch.of("  \u0000café\n ", emptyList())?.text)
        assertEquals("a".repeat(100), MovementSearch.of("a".repeat(150), emptyList())?.text)
        // Se cuentan caracteres Unicode, no unidades UTF-16: no se parte ningún emoji.
        val emoji = "😀".repeat(120)
        assertEquals(100, MovementSearch.of(emoji, emptyList())?.text?.let { it.codePointCount(0, it.length) })
    }

    @Test
    fun busquedaEncuentraPorTextoEtiquetaCategoriaEImporte() {
        val comida = BudgetCategory("c1", "h1", "Comida")
        fun mov(description: String, minor: Long = -100, payee: String? = null, notes: String? = null, tags: List<String> = emptyList(), categoryId: String? = null) =
            Movement("m", "h1", "a1", categoryId, "2026-01-01", minor, description, notes, payee = payee, tags = tags)
        fun buscar(text: String) = MovementSearch.of(text, listOf(comida))!!

        assertTrue(buscar("50%").matches(mov("Descuento 50% hoy")))
        assertFalse("el % es un carácter, no un comodín", buscar("50%").matches(mov("Descuento 500 hoy")))
        assertTrue(buscar("mercado").matches(mov("x", payee = "Mercado central")))
        assertTrue(buscar("regalo").matches(mov("x", notes = "Regalo de cumple")))
        assertTrue(buscar("#viaje").matches(mov("x", tags = listOf("viaje"))))
        assertFalse("la etiqueta tiene que ser esa entera", buscar("#via").matches(mov("x", tags = listOf("viaje"))))
        assertTrue(buscar("comida").matches(mov("x", categoryId = "c1")))
        assertTrue(buscar("12,50").matches(mov("x", minor = 1_250)))
        assertTrue(buscar("12,50").matches(mov("x", minor = -1_250)))
        assertFalse("con signo, sólo gastos", buscar("-12,50").matches(mov("x", minor = 1_250)))
    }
}
