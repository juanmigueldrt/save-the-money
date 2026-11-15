import Foundation

/// Un comercio conocido: cómo se reconoce en la descripción del banco, qué categoría
/// le corresponde por defecto y de qué dominio sale su logo.
///
/// Privacidad: el reconocimiento es local. Al servicio de logos sólo se le pide el
/// dominio (p. ej. `apple.com`), nunca la descripción, el importe ni la fecha.
public struct Merchant: Hashable, Sendable {
    /// Nombre para mostrar, p. ej. "Google One".
    public let name: String
    /// Dominio del que se pide el logo. `nil` en los genéricos (Farmacia, Supermercado).
    public let domain: String?
    /// Nombre de la categoría por defecto (las 17 que crea el hogar).
    public let category: String
    /// Icono de reserva (SF Symbol) cuando no hay logo o no carga.
    public let symbol: String
    /// Palabras que lo identifican, ya normalizadas (mayúsculas, sin tildes).
    public let keywords: [String]

    public init(_ name: String, domain: String?, category: String, symbol: String, keywords: [String]) {
        self.name = name
        self.domain = domain
        self.category = category
        self.symbol = symbol
        self.keywords = keywords.map(MerchantDirectory.normalize)
    }

    /// URL del logo. Sólo viaja el dominio.
    public var logoURL: URL? {
        guard let domain else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128")
    }
}

/// Texto de los movimientos tal como se enseña: siempre en mayúsculas.
/// Lo guardado no cambia (la detección de duplicados del CSV usa el texto original).
public enum MovementText {
    public static func display(_ description: String) -> String {
        description.uppercased(with: Locale(identifier: "es_ES"))
    }
}

/// Lo que el usuario ya decidió: concepto -> categoría, sacado de sus propios gastos.
/// Se calcula en el dispositivo con los movimientos que ya tiene cargados; no sale de él.
public struct CategoryLearner: Sendable {
    public static let empty = CategoryLearner(movements: [])
    private let byKey: [String: UUID]

    /// Gana el movimiento más reciente de cada concepto (si cambias de opinión, se nota).
    public init(movements: [Movement]) {
        var chosen: [String: (day: CalendarDay, id: UUID)] = [:]
        for movement in movements where movement.isExpense {
            guard let category = movement.categoryId else { continue }
            let key = MerchantDirectory.learningKey(movement.description)
            guard !key.isEmpty else { continue }
            if let current = chosen[key], current.day > movement.bookedOn { continue }
            chosen[key] = (movement.bookedOn, category)
        }
        byKey = chosen.mapValues(\.id)
    }

    public func categoryId(for description: String) -> UUID? {
        let key = MerchantDirectory.learningKey(description)
        return key.isEmpty ? nil : byKey[key]
    }
}

public enum MerchantDirectory {
    /// Busca el comercio en la descripción. Gana la palabra clave más larga, para que
    /// "GOOGLE ONE" no se quede en "GOOGLE" ni "UBER EATS" en "UBER".
    public static func match(_ description: String) -> Merchant? {
        let text = " " + normalize(description) + " "
        var best: (merchant: Merchant, length: Int)?
        for merchant in all {
            for keyword in merchant.keywords where !keyword.isEmpty && keyword.count > (best?.length ?? 0) {
                if text.contains(" " + keyword + " ") { best = (merchant, keyword.count) }
            }
        }
        return best?.merchant
    }

    /// Categoría sugerida para un gasto. Primero lo que el usuario ya hizo con ese concepto
    /// (aprendido en el dispositivo); si no, la categoría por defecto del comercio, buscada por nombre.
    /// `nil` si no hay nada o si el usuario no tiene esa categoría.
    public static func suggestedCategory(for description: String, isExpense: Bool,
                                         in categories: [BudgetCategory],
                                         learned: CategoryLearner = .empty) -> BudgetCategory? {
        guard isExpense else { return nil }
        let expenses = categories.filter { $0.kind == .expense }
        if let id = learned.categoryId(for: description), let category = expenses.first(where: { $0.id == id }) {
            return category
        }
        guard let merchant = match(description) else { return nil }
        let wanted = normalize(merchant.category)
        return expenses.first { normalize($0.name) == wanted }
    }

    /// Pone categoría a los gastos importados que no la tienen. Nunca cambia una ya puesta.
    public static func categorize(_ rows: [CSVImportRow], with categories: [BudgetCategory],
                                  learned: CategoryLearner = .empty) -> [CSVImportRow] {
        rows.map { row in
            guard var draft = row.draft, draft.categoryId == nil,
                  let category = suggestedCategory(for: draft.description, isExpense: draft.amount.isNegative,
                                                   in: categories, learned: learned) else { return row }
            draft.categoryId = category.id
            var updated = row
            updated.draft = draft
            return updated
        }
    }

    /// Clave con la que se recuerda un concepto: el comercio si se reconoce; si no, el texto
    /// sin números (referencias, fechas, tarjetas) y con sus cuatro primeras palabras.
    static func learningKey(_ description: String) -> String {
        if let merchant = match(description) { return "@" + merchant.name }
        let words = normalize(description).split(separator: " ")
            .filter { word in !word.contains(where: \.isNumber) }
        return words.prefix(4).joined(separator: " ")
    }

    /// Mayúsculas, sin tildes y con cualquier signo convertido en espacio:
    /// "Apple.com/bill" -> "APPLE COM BILL".
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .uppercased()
        let mapped = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// Lista de comercios. Mantener igual que `Merchants.kt` en Android.
    public static let all: [Merchant] = [
        // Genéricos (sin logo propio)
        Merchant("Farmacia", domain: nil, category: "Salud", symbol: "cross.case.fill",
                 keywords: ["FARMACIA", "PARAFARMACIA", "FCIA"]),
        Merchant("Supermercado", domain: nil, category: "Supermercado", symbol: "cart.fill",
                 keywords: ["SUPERMERCADO", "SUPERMERCADOS", "HIPERMERCADO", "SUPERMARKET"]),
        Merchant("Gasolinera", domain: nil, category: "Transporte", symbol: "fuelpump.fill",
                 keywords: ["GASOLINERA", "ESTACION DE SERVICIO"]),
        // Suscripciones y tecnología
        Merchant("Apple", domain: "apple.com", category: "Suscripciones", symbol: "apple.logo",
                 keywords: ["APPLE", "APPLE COM", "APPLE COM BILL", "ITUNES", "ICLOUD"]),
        Merchant("Apple Store", domain: "apple.com", category: "Compras", symbol: "apple.logo",
                 keywords: ["APPLE STORE", "APPLE ONLINE STORE"]),
        Merchant("Google One", domain: "one.google.com", category: "Suscripciones", symbol: "icloud.fill",
                 keywords: ["GOOGLE ONE"]),
        Merchant("Google", domain: "google.com", category: "Suscripciones", symbol: "globe",
                 keywords: ["GOOGLE", "GOOGLE PLAY"]),
        Merchant("YouTube", domain: "youtube.com", category: "Suscripciones", symbol: "play.rectangle.fill",
                 keywords: ["YOUTUBE", "YOUTUBE PREMIUM", "GOOGLE YOUTUBE"]),
        Merchant("Netflix", domain: "netflix.com", category: "Suscripciones", symbol: "tv.fill",
                 keywords: ["NETFLIX"]),
        Merchant("Spotify", domain: "spotify.com", category: "Suscripciones", symbol: "music.note",
                 keywords: ["SPOTIFY"]),
        Merchant("Disney+", domain: "disneyplus.com", category: "Suscripciones", symbol: "tv.fill",
                 keywords: ["DISNEY PLUS", "DISNEYPLUS", "DISNEY"]),
        Merchant("HBO Max", domain: "max.com", category: "Suscripciones", symbol: "tv.fill",
                 keywords: ["HBO", "HBO MAX"]),
        Merchant("Prime Video", domain: "primevideo.com", category: "Suscripciones", symbol: "tv.fill",
                 keywords: ["PRIME VIDEO", "AMAZON PRIME", "PRIME AMAZON"]),
        Merchant("Microsoft", domain: "microsoft.com", category: "Suscripciones", symbol: "desktopcomputer",
                 keywords: ["MICROSOFT", "MSFT", "XBOX"]),
        Merchant("PlayStation", domain: "playstation.com", category: "Ocio", symbol: "gamecontroller.fill",
                 keywords: ["PLAYSTATION", "SONY PLAYSTATION"]),
        Merchant("Steam", domain: "steampowered.com", category: "Ocio", symbol: "gamecontroller.fill",
                 keywords: ["STEAM", "STEAMPOWERED"]),
        Merchant("OpenAI", domain: "openai.com", category: "Suscripciones", symbol: "sparkles",
                 keywords: ["OPENAI", "CHATGPT"]),
        Merchant("Claude", domain: "claude.ai", category: "Suscripciones", symbol: "sparkles",
                 keywords: ["ANTHROPIC", "CLAUDE AI"]),
        // Supermercados
        Merchant("Mercadona", domain: "mercadona.es", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["MERCADONA"]),
        Merchant("Carrefour", domain: "carrefour.es", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["CARREFOUR"]),
        Merchant("Lidl", domain: "lidl.es", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["LIDL"]),
        Merchant("Aldi", domain: "aldi.es", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["ALDI"]),
        Merchant("Dia", domain: "dia.es", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["SUPERMERCADOS DIA", "DIA RETAIL", "DIA SUPERMERCADO"]),
        Merchant("Alcampo", domain: "alcampo.es", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["ALCAMPO"]),
        Merchant("Eroski", domain: "eroski.es", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["EROSKI"]),
        Merchant("Consum", domain: "consum.es", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["CONSUM"]),
        Merchant("Ahorramás", domain: "ahorramas.com", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["AHORRAMAS"]),
        Merchant("Hipercor", domain: "hipercor.es", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["HIPERCOR"]),
        Merchant("Caprabo", domain: "caprabo.com", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["CAPRABO"]),
        Merchant("Bonpreu", domain: "bonpreu.cat", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["BONPREU", "BON PREU"]),
        Merchant("BM Supermercados", domain: "bmsupermercados.es", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["BM SUPERMERCADOS"]),
        Merchant("Gadis", domain: "gadis.es", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["GADIS"]),
        Merchant("Froiz", domain: "froiz.com", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["FROIZ"]),
        Merchant("Covirán", domain: "coviran.es", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["COVIRAN"]),
        Merchant("Spar", domain: "spar.es", category: "Supermercado", symbol: "cart.fill",
                 keywords: ["SPAR"]),
        // Compras
        Merchant("Amazon", domain: "amazon.es", category: "Compras", symbol: "shippingbox.fill",
                 keywords: ["AMAZON", "AMZN", "AMAZON ES", "AMZN MKTP"]),
        Merchant("AliExpress", domain: "aliexpress.com", category: "Compras", symbol: "shippingbox.fill",
                 keywords: ["ALIEXPRESS"]),
        Merchant("El Corte Inglés", domain: "elcorteingles.es", category: "Compras", symbol: "bag.fill",
                 keywords: ["EL CORTE INGLES", "CORTE INGLES"]),
        Merchant("Zara", domain: "zara.com", category: "Compras", symbol: "tshirt.fill", keywords: ["ZARA"]),
        Merchant("Primark", domain: "primark.com", category: "Compras", symbol: "tshirt.fill", keywords: ["PRIMARK"]),
        Merchant("IKEA", domain: "ikea.com", category: "Compras", symbol: "sofa.fill", keywords: ["IKEA"]),
        Merchant("Decathlon", domain: "decathlon.es", category: "Compras", symbol: "figure.run",
                 keywords: ["DECATHLON"]),
        Merchant("MediaMarkt", domain: "mediamarkt.es", category: "Compras", symbol: "tv.fill",
                 keywords: ["MEDIAMARKT", "MEDIA MARKT"]),
        Merchant("Leroy Merlin", domain: "leroymerlin.es", category: "Compras", symbol: "hammer.fill",
                 keywords: ["LEROY MERLIN"]),
        // Restaurantes y comida a domicilio
        Merchant("McDonald's", domain: "mcdonalds.es", category: "Restaurantes", symbol: "fork.knife",
                 keywords: ["MCDONALDS", "MC DONALDS", "MCDONALD S"]),
        Merchant("Burger King", domain: "burgerking.es", category: "Restaurantes", symbol: "fork.knife",
                 keywords: ["BURGER KING"]),
        Merchant("Telepizza", domain: "telepizza.es", category: "Restaurantes", symbol: "fork.knife",
                 keywords: ["TELEPIZZA"]),
        Merchant("Domino's", domain: "dominospizza.es", category: "Restaurantes", symbol: "fork.knife",
                 keywords: ["DOMINOS", "DOMINO S"]),
        Merchant("Starbucks", domain: "starbucks.es", category: "Restaurantes", symbol: "cup.and.saucer.fill",
                 keywords: ["STARBUCKS"]),
        Merchant("Glovo", domain: "glovoapp.com", category: "Restaurantes", symbol: "takeoutbag.and.cup.and.straw.fill",
                 keywords: ["GLOVO"]),
        Merchant("Just Eat", domain: "just-eat.es", category: "Restaurantes", symbol: "takeoutbag.and.cup.and.straw.fill",
                 keywords: ["JUST EAT", "JUSTEAT"]),
        Merchant("Uber Eats", domain: "ubereats.com", category: "Restaurantes", symbol: "takeoutbag.and.cup.and.straw.fill",
                 keywords: ["UBER EATS", "UBEREATS"]),
        // Transporte
        Merchant("Uber", domain: "uber.com", category: "Transporte", symbol: "car.fill", keywords: ["UBER"]),
        Merchant("Cabify", domain: "cabify.com", category: "Transporte", symbol: "car.fill", keywords: ["CABIFY"]),
        Merchant("Bolt", domain: "bolt.eu", category: "Transporte", symbol: "car.fill", keywords: ["BOLT EU", "BOLT"]),
        Merchant("Renfe", domain: "renfe.com", category: "Transporte", symbol: "tram.fill", keywords: ["RENFE"]),
        Merchant("Repsol", domain: "repsol.es", category: "Transporte", symbol: "fuelpump.fill", keywords: ["REPSOL"]),
        Merchant("Cepsa", domain: "cepsa.es", category: "Transporte", symbol: "fuelpump.fill",
                 keywords: ["CEPSA", "MOEVE"]),
        Merchant("BP", domain: "bp.com", category: "Transporte", symbol: "fuelpump.fill", keywords: ["BP"]),
        Merchant("Shell", domain: "shell.es", category: "Transporte", symbol: "fuelpump.fill", keywords: ["SHELL"]),
        Merchant("Galp", domain: "galp.com", category: "Transporte", symbol: "fuelpump.fill", keywords: ["GALP"]),
        // Viajes
        Merchant("Ryanair", domain: "ryanair.com", category: "Viajes", symbol: "airplane", keywords: ["RYANAIR"]),
        Merchant("Vueling", domain: "vueling.com", category: "Viajes", symbol: "airplane", keywords: ["VUELING"]),
        Merchant("Iberia", domain: "iberia.com", category: "Viajes", symbol: "airplane", keywords: ["IBERIA"]),
        Merchant("Booking", domain: "booking.com", category: "Viajes", symbol: "bed.double.fill",
                 keywords: ["BOOKING", "BOOKING COM"]),
        Merchant("Airbnb", domain: "airbnb.es", category: "Viajes", symbol: "bed.double.fill", keywords: ["AIRBNB"]),
        // Suministros
        Merchant("Iberdrola", domain: "iberdrola.es", category: "Suministros", symbol: "bolt.fill",
                 keywords: ["IBERDROLA"]),
        Merchant("Endesa", domain: "endesa.com", category: "Suministros", symbol: "bolt.fill", keywords: ["ENDESA"]),
        Merchant("Naturgy", domain: "naturgy.es", category: "Suministros", symbol: "flame.fill", keywords: ["NATURGY"]),
        Merchant("Movistar", domain: "movistar.es", category: "Suministros", symbol: "antenna.radiowaves.left.and.right",
                 keywords: ["MOVISTAR", "TELEFONICA"]),
        Merchant("Vodafone", domain: "vodafone.es", category: "Suministros", symbol: "antenna.radiowaves.left.and.right",
                 keywords: ["VODAFONE"]),
        Merchant("Orange", domain: "orange.es", category: "Suministros", symbol: "antenna.radiowaves.left.and.right",
                 keywords: ["ORANGE"]),
        Merchant("Digi", domain: "digimobil.es", category: "Suministros", symbol: "antenna.radiowaves.left.and.right",
                 keywords: ["DIGI", "DIGI SPAIN", "DIGIMOBIL"]),
        Merchant("MásMóvil", domain: "masmovil.es", category: "Suministros", symbol: "antenna.radiowaves.left.and.right",
                 keywords: ["MASMOVIL"]),
        // Seguros
        Merchant("Mapfre", domain: "mapfre.es", category: "Seguros", symbol: "shield.fill", keywords: ["MAPFRE"]),
        Merchant("Mutua Madrileña", domain: "mutua.es", category: "Seguros", symbol: "shield.fill",
                 keywords: ["MUTUA MADRILENA"]),
        Merchant("Sanitas", domain: "sanitas.es", category: "Seguros", symbol: "shield.fill", keywords: ["SANITAS"]),
        Merchant("Adeslas", domain: "segurcaixaadeslas.es", category: "Seguros", symbol: "shield.fill",
                 keywords: ["ADESLAS"]),
        Merchant("Línea Directa", domain: "lineadirecta.com", category: "Seguros", symbol: "shield.fill",
                 keywords: ["LINEA DIRECTA"]),
    ]
}
