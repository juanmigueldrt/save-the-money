package com.savethemoney.android.data

import java.text.Normalizer
import java.time.LocalDate
import java.util.Locale

/**
 * Un comercio conocido: cómo se reconoce en la descripción del banco, qué categoría le toca
 * por defecto y de qué dominio sale su logo. Igual que `Merchants.swift` en iOS y Mac.
 *
 * Privacidad: el reconocimiento es local. Al servicio de logos sólo se le pide el dominio
 * (p. ej. `apple.com`), nunca la descripción, el importe ni la fecha.
 */
class Merchant(val name: String, val domain: String?, val category: String, keywords: List<String>) {
    val keywords: List<String> = keywords.map(MerchantDirectory::normalize)

    /** URL del logo. Sólo viaja el dominio. */
    val logoUrl: String? get() = logoUrl(null)

    /** Con la clave publicable de logo.dev (`pk_…`) sale de img.logo.dev; si no, del favicon de Google. */
    fun logoUrl(logoDevToken: String?): String? {
        val d = domain ?: return null
        val token = MerchantDirectory.publishableToken(logoDevToken)
        return if (token != null) "https://img.logo.dev/$d?token=$token&size=128&format=png&retina=true"
        else "https://www.google.com/s2/favicons?domain=$d&sz=128"
    }
}

/** Texto de los movimientos tal como se enseña: siempre en mayúsculas. Lo guardado no cambia. */
object MovementText {
    private val es = Region.locale
    fun display(description: String): String = description.uppercase(es)
}

/** Lo que el usuario ya decidió: concepto -> categoría, sacado de sus propios gastos en el dispositivo. */
class CategoryLearner(movements: List<Movement>) {
    private val byKey: Map<String, String>

    init {
        val chosen = HashMap<String, Pair<LocalDate, String>>()
        for (m in movements) {
            if (!m.isExpense || m.excluded) continue
            val category = m.categoryId ?: continue
            val key = MerchantDirectory.learningKey(m.description)
            if (key.isEmpty()) continue
            val current = chosen[key]
            if (current != null && current.first > m.day) continue
            chosen[key] = m.day to category
        }
        byKey = chosen.mapValues { it.value.second }
    }

    fun categoryId(description: String): String? =
        MerchantDirectory.learningKey(description).takeIf { it.isNotEmpty() }?.let { byKey[it] }

    companion object {
        val EMPTY = CategoryLearner(emptyList())
    }
}

object MerchantDirectory {
    /** Gana la palabra clave más larga: "GOOGLE ONE" no se queda en "GOOGLE" ni "UBER EATS" en "UBER". */
    fun match(description: String): Merchant? {
        val text = " " + normalize(description) + " "
        var best: Merchant? = null
        var length = 0
        for (merchant in all) for (keyword in merchant.keywords) {
            if (keyword.isNotEmpty() && keyword.length > length && text.contains(" $keyword ")) {
                best = merchant
                length = keyword.length
            }
        }
        return best
    }

    /** Primero lo aprendido del usuario; si no, la categoría por defecto del comercio, por nombre. Sólo gastos. */
    fun suggestedCategory(
        description: String, isExpense: Boolean, categories: List<BudgetCategory>,
        learned: CategoryLearner = CategoryLearner.EMPTY,
    ): BudgetCategory? {
        if (!isExpense) return null
        val expenses = categories.filter { it.kind == CategoryKind.Expense }
        learned.categoryId(description)?.let { id -> expenses.firstOrNull { it.id == id }?.let { return it } }
        val merchant = match(description) ?: return null
        val wanted = normalize(merchant.category)
        return expenses.firstOrNull { normalize(it.name) == wanted }
    }

    /** Pone categoría a los gastos importados que no la tienen. Nunca cambia una ya puesta. */
    fun categorize(
        rows: List<CsvImportRow>, categories: List<BudgetCategory>,
        learned: CategoryLearner = CategoryLearner.EMPTY,
    ): List<CsvImportRow> = rows.map { row ->
        val d = row.draft ?: return@map row
        if (d.categoryId != null) return@map row
        val cat = suggestedCategory(d.description, d.amountMinor < 0, categories, learned) ?: return@map row
        row.copy(draft = d.copy(categoryId = cat.id))
    }

    /** El comercio si se reconoce; si no, el texto sin números y con sus cuatro primeras palabras. */
    fun learningKey(description: String): String {
        match(description)?.let { return "@" + it.name }
        return normalize(description).split(" ").filter { w -> w.isNotEmpty() && w.none(Char::isDigit) }
            .take(4).joinToString(" ")
    }

    /** Sólo se acepta la clave publicable de logo.dev; una secreta (`sk_…`) nunca se usa en la app. */
    fun publishableToken(token: String?): String? {
        val t = token?.trim() ?: return null
        return t.takeIf { it.startsWith("pk_") && it.length > 3 && it.all { c -> c.isLetterOrDigit() || c == '_' || c == '-' } }
    }

    /** Mayúsculas, sin tildes y cualquier signo como espacio: "Apple.com/bill" -> "APPLE COM BILL". */
    fun normalize(text: String): String {
        val folded = Normalizer.normalize(text, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "")
            .uppercase(Locale.ROOT)
        return folded.map { if (it.isLetterOrDigit()) it else ' ' }.joinToString("")
            .split(" ").filter { it.isNotEmpty() }.joinToString(" ")
    }

    /** Lista de comercios. Mantener igual que `Merchants.swift`. */
    val all: List<Merchant> = listOf(
        Merchant("Farmacia", null, "Salud", listOf("FARMACIA", "PARAFARMACIA", "FCIA")),
        Merchant("Supermercado", null, "Supermercado", listOf("SUPERMERCADO", "SUPERMERCADOS", "HIPERMERCADO", "SUPERMARKET")),
        Merchant("Gasolinera", null, "Transporte", listOf("GASOLINERA", "ESTACION DE SERVICIO")),
        Merchant("Apple", "apple.com", "Suscripciones", listOf("APPLE", "APPLE COM", "APPLE COM BILL", "ITUNES", "ICLOUD")),
        Merchant("Apple Store", "apple.com", "Compras", listOf("APPLE STORE", "APPLE ONLINE STORE")),
        Merchant("Google One", "one.google.com", "Suscripciones", listOf("GOOGLE ONE")),
        Merchant("Google", "google.com", "Suscripciones", listOf("GOOGLE", "GOOGLE PLAY")),
        Merchant("YouTube", "youtube.com", "Suscripciones", listOf("YOUTUBE", "YOUTUBE PREMIUM", "GOOGLE YOUTUBE")),
        Merchant("Netflix", "netflix.com", "Suscripciones", listOf("NETFLIX")),
        Merchant("Spotify", "spotify.com", "Suscripciones", listOf("SPOTIFY")),
        Merchant("Disney+", "disneyplus.com", "Suscripciones", listOf("DISNEY PLUS", "DISNEYPLUS", "DISNEY")),
        Merchant("HBO Max", "max.com", "Suscripciones", listOf("HBO", "HBO MAX")),
        Merchant("Prime Video", "primevideo.com", "Suscripciones", listOf("PRIME VIDEO", "AMAZON PRIME", "PRIME AMAZON")),
        Merchant("Microsoft", "microsoft.com", "Suscripciones", listOf("MICROSOFT", "MSFT", "XBOX")),
        Merchant("PlayStation", "playstation.com", "Ocio", listOf("PLAYSTATION", "SONY PLAYSTATION")),
        Merchant("Steam", "steampowered.com", "Ocio", listOf("STEAM", "STEAMPOWERED")),
        Merchant("OpenAI", "openai.com", "Suscripciones", listOf("OPENAI", "CHATGPT")),
        Merchant("Claude", "claude.ai", "Suscripciones", listOf("ANTHROPIC", "CLAUDE AI")),
        Merchant("Mercadona", "mercadona.es", "Supermercado", listOf("MERCADONA")),
        Merchant("Carrefour", "carrefour.es", "Supermercado", listOf("CARREFOUR")),
        Merchant("Lidl", "lidl.es", "Supermercado", listOf("LIDL")),
        Merchant("Aldi", "aldi.es", "Supermercado", listOf("ALDI")),
        Merchant("Dia", "dia.es", "Supermercado", listOf("SUPERMERCADOS DIA", "DIA RETAIL", "DIA SUPERMERCADO")),
        Merchant("Alcampo", "alcampo.es", "Supermercado", listOf("ALCAMPO")),
        Merchant("Eroski", "eroski.es", "Supermercado", listOf("EROSKI")),
        Merchant("Consum", "consum.es", "Supermercado", listOf("CONSUM")),
        Merchant("Ahorramás", "ahorramas.com", "Supermercado", listOf("AHORRAMAS")),
        Merchant("Hipercor", "hipercor.es", "Supermercado", listOf("HIPERCOR")),
        Merchant("Caprabo", "caprabo.com", "Supermercado", listOf("CAPRABO")),
        Merchant("Bonpreu", "bonpreu.cat", "Supermercado", listOf("BONPREU", "BON PREU")),
        Merchant("BM Supermercados", "bmsupermercados.es", "Supermercado", listOf("BM SUPERMERCADOS")),
        Merchant("Gadis", "gadis.es", "Supermercado", listOf("GADIS")),
        Merchant("Froiz", "froiz.com", "Supermercado", listOf("FROIZ")),
        Merchant("Covirán", "coviran.es", "Supermercado", listOf("COVIRAN")),
        Merchant("Spar", "spar.es", "Supermercado", listOf("SPAR")),
        Merchant("Amazon", "amazon.es", "Compras", listOf("AMAZON", "AMZN", "AMAZON ES", "AMZN MKTP")),
        Merchant("AliExpress", "aliexpress.com", "Compras", listOf("ALIEXPRESS")),
        Merchant("El Corte Inglés", "elcorteingles.es", "Compras", listOf("EL CORTE INGLES", "CORTE INGLES")),
        Merchant("Zara", "zara.com", "Compras", listOf("ZARA")),
        Merchant("Primark", "primark.com", "Compras", listOf("PRIMARK")),
        Merchant("IKEA", "ikea.com", "Compras", listOf("IKEA")),
        Merchant("Decathlon", "decathlon.es", "Compras", listOf("DECATHLON")),
        Merchant("MediaMarkt", "mediamarkt.es", "Compras", listOf("MEDIAMARKT", "MEDIA MARKT")),
        Merchant("Leroy Merlin", "leroymerlin.es", "Compras", listOf("LEROY MERLIN")),
        Merchant("McDonald's", "mcdonalds.es", "Restaurantes", listOf("MCDONALDS", "MC DONALDS", "MCDONALD S")),
        Merchant("Burger King", "burgerking.es", "Restaurantes", listOf("BURGER KING")),
        Merchant("Telepizza", "telepizza.es", "Restaurantes", listOf("TELEPIZZA")),
        Merchant("Domino's", "dominospizza.es", "Restaurantes", listOf("DOMINOS", "DOMINO S")),
        Merchant("Starbucks", "starbucks.es", "Restaurantes", listOf("STARBUCKS")),
        Merchant("Glovo", "glovoapp.com", "Restaurantes", listOf("GLOVO")),
        Merchant("Just Eat", "just-eat.es", "Restaurantes", listOf("JUST EAT", "JUSTEAT")),
        Merchant("Uber Eats", "ubereats.com", "Restaurantes", listOf("UBER EATS", "UBEREATS")),
        Merchant("Uber", "uber.com", "Transporte", listOf("UBER")),
        Merchant("Cabify", "cabify.com", "Transporte", listOf("CABIFY")),
        Merchant("Bolt", "bolt.eu", "Transporte", listOf("BOLT EU", "BOLT")),
        Merchant("Renfe", "renfe.com", "Transporte", listOf("RENFE")),
        Merchant("Repsol", "repsol.es", "Transporte", listOf("REPSOL")),
        Merchant("Cepsa", "cepsa.es", "Transporte", listOf("CEPSA", "MOEVE")),
        Merchant("BP", "bp.com", "Transporte", listOf("BP")),
        Merchant("Shell", "shell.es", "Transporte", listOf("SHELL")),
        Merchant("Galp", "galp.com", "Transporte", listOf("GALP")),
        Merchant("Ryanair", "ryanair.com", "Viajes", listOf("RYANAIR")),
        Merchant("Vueling", "vueling.com", "Viajes", listOf("VUELING")),
        Merchant("Iberia", "iberia.com", "Viajes", listOf("IBERIA")),
        Merchant("Booking", "booking.com", "Viajes", listOf("BOOKING", "BOOKING COM")),
        Merchant("Airbnb", "airbnb.es", "Viajes", listOf("AIRBNB")),
        Merchant("Iberdrola", "iberdrola.es", "Suministros", listOf("IBERDROLA")),
        Merchant("Endesa", "endesa.com", "Suministros", listOf("ENDESA")),
        Merchant("Naturgy", "naturgy.es", "Suministros", listOf("NATURGY")),
        Merchant("Movistar", "movistar.es", "Suministros", listOf("MOVISTAR", "TELEFONICA")),
        Merchant("Vodafone", "vodafone.es", "Suministros", listOf("VODAFONE")),
        Merchant("Orange", "orange.es", "Suministros", listOf("ORANGE")),
        Merchant("Digi", "digimobil.es", "Suministros", listOf("DIGI", "DIGI SPAIN", "DIGIMOBIL")),
        Merchant("MásMóvil", "masmovil.es", "Suministros", listOf("MASMOVIL")),
        Merchant("Mapfre", "mapfre.es", "Seguros", listOf("MAPFRE")),
        Merchant("Mutua Madrileña", "mutua.es", "Seguros", listOf("MUTUA MADRILENA")),
        Merchant("Sanitas", "sanitas.es", "Seguros", listOf("SANITAS")),
        Merchant("Adeslas", "segurcaixaadeslas.es", "Seguros", listOf("ADESLAS")),
        Merchant("Línea Directa", "lineadirecta.com", "Seguros", listOf("LINEA DIRECTA")),
    )
}
