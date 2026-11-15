import Foundation

// MARK: - Etiquetas

/// Etiquetas de un movimiento: palabras sueltas en minúsculas, sin «#» (p. ej. "viaje", "boda-ana").
public enum MovementTags {
    public static let maxCount = 10
    public static let maxLength = 30

    /// Lo que el usuario escribe ("#Viaje, cumple  boda") en etiquetas limpias y sin repetir.
    public static func normalize(_ text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for piece in text.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace }) {
            let tag = clean(String(piece))
            guard !tag.isEmpty, seen.insert(tag).inserted else { continue }
            result.append(tag)
        }
        return result
    }

    /// Una etiqueta escrita a mano, limpia: sin «#», en minúsculas, sólo letras, números, "-" y "_".
    public static func clean(_ text: String) -> String {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
        return String(lower.unicodeScalars.filter { allowed.contains($0) }.map(Character.init))
    }

    /// Texto para el campo de edición: "viaje, cumple".
    public static func text(_ tags: [String]) -> String { tags.joined(separator: ", ") }

    /// Problema con las etiquetas, o nil si valen (las mismas reglas que la base de datos).
    public static func issue(_ tags: [String]) -> String? {
        if tags.count > maxCount { return "Como mucho \(maxCount) etiquetas por movimiento." }
        for tag in tags {
            if tag.isEmpty || tag.count > maxLength {
                return "Cada etiqueta debe tener entre 1 y \(maxLength) caracteres."
            }
            if tag != tag.lowercased() || !tag.unicodeScalars.allSatisfy(allowed.contains) {
                return "Las etiquetas sólo pueden tener letras, números, «-» y «_»."
            }
        }
        return nil
    }

    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-_")
        return set
    }()

    /// Todas las etiquetas usadas, de la más usada a la menos.
    public static func all(in movements: [Movement]) -> [String] {
        var counts: [String: Int] = [:]
        for movement in movements { for tag in movement.tags { counts[tag, default: 0] += 1 } }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }
}

// MARK: - Beneficiario

public enum Payee {
    /// Beneficiario limpio para guardar: sin espacios de más, nil si queda vacío.
    public static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : String(collapsed.prefix(80))
    }

    /// Beneficiarios usados, del más usado al menos (para sugerir al escribir).
    public static func all(in movements: [Movement]) -> [String] {
        var counts: [String: (name: String, count: Int)] = [:]
        for movement in movements {
            guard let payee = clean(movement.payee) else { continue }
            let key = CSVMapping.normalize(payee)
            counts[key, default: (payee, 0)].count += 1
        }
        return counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }.map(\.name)
    }
}

// MARK: - Edición de varios movimientos a la vez

/// Cambios que se aplican a todos los movimientos elegidos. Lo que es nil no se toca.
public struct MovementBulkEdit: Hashable, Sendable {
    public var bookedOn: CalendarDay?
    /// `.some(nil)` quita la categoría.
    public var categoryId: UUID??
    public var accountId: UUID?
    public var excluded: Bool?
    public var reviewed: Bool?
    public var payee: String??
    public var addTags: [String]
    public var removeTags: [String]

    public init(bookedOn: CalendarDay? = nil, categoryId: UUID?? = nil, accountId: UUID? = nil,
                excluded: Bool? = nil, reviewed: Bool? = nil, payee: String?? = nil,
                addTags: [String] = [], removeTags: [String] = []) {
        self.bookedOn = bookedOn
        self.categoryId = categoryId
        self.accountId = accountId
        self.excluded = excluded
        self.reviewed = reviewed
        self.payee = payee
        self.addTags = addTags
        self.removeTags = removeTags
    }

    public var isEmpty: Bool {
        bookedOn == nil && categoryId == nil && accountId == nil && excluded == nil && reviewed == nil
            && payee == nil && addTags.isEmpty && removeTags.isEmpty
    }

    /// El movimiento con los cambios puestos. `now` es la hora de "revisado".
    public func applied(to movement: Movement, now: Date = Date()) -> Movement {
        var copy = movement
        if let bookedOn { copy.bookedOn = bookedOn }
        if let categoryId { copy.categoryId = categoryId }
        if let accountId { copy.accountId = accountId }
        if let excluded { copy.excluded = excluded }
        if let reviewed { copy.reviewedAt = reviewed ? (movement.reviewedAt ?? now) : nil }
        if let payee { copy.payee = Payee.clean(payee) }
        if !addTags.isEmpty || !removeTags.isEmpty {
            var tags = copy.tags.filter { !removeTags.contains($0) }
            for tag in addTags where !tags.contains(tag) { tags.append(tag) }
            copy.tags = Array(tags.prefix(MovementTags.maxCount))
        }
        return copy
    }

    /// Sólo los movimientos que cambian de verdad, ya cambiados.
    public func changes(for movements: [Movement], now: Date = Date()) -> [Movement] {
        movements.compactMap { movement in
            let changed = applied(to: movement, now: now)
            return changed == movement ? nil : changed
        }
    }
}

// MARK: - Cambiar los parecidos

public enum SimilarMovements {
    /// Clave para reconocer el mismo concepto: sin acentos, mayúsculas, números ni signos sueltos
    /// ("COMPRA MERCADONA 1234 TARJ. 5678" y "Compra Mercadona 99" coinciden).
    public static func key(_ description: String) -> String {
        let folded = CSVMapping.normalize(description)
        let words = folded.split { !$0.isLetter }.filter { $0.count > 1 }.map(String.init)
        return words.joined(separator: " ")
    }

    /// Otros movimientos con el mismo concepto que `movement` que se verían afectados
    /// si se les pone la misma categoría (los que ya la tienen se dejan fuera).
    public static func matches(for movement: Movement, in movements: [Movement],
                               categoryId: UUID?) -> [Movement] {
        let target = key(movement.description)
        guard !target.isEmpty else { return [] }
        return movements.filter {
            $0.id != movement.id && $0.categoryId != categoryId && key($0.description) == target
                && $0.amount.isNegative == movement.amount.isNegative
        }
    }
}

// MARK: - Informes por etiqueta y por beneficiario

public struct GroupedSpending: Hashable, Sendable, Identifiable {
    public var title: String
    /// Gastos en positivo (una devolución lo resta).
    public var spent: Money
    public var income: Money
    public var count: Int

    public var id: String { title }

    public enum Grouping: String, CaseIterable, Sendable, Identifiable {
        case tag, payee
        public var id: String { rawValue }
        public var title: String { self == .tag ? "Por etiqueta" : "Por beneficiario" }
    }

    /// Gasto e ingreso por etiqueta o por beneficiario en el periodo. Sin transferencias ni excluidos.
    /// Un movimiento con dos etiquetas cuenta en las dos.
    public static func report(_ grouping: Grouping, movements: [Movement], categories: [BudgetCategory],
                              range: ClosedRange<CalendarDay>) -> [GroupedSpending] {
        let transfers = Set(categories.filter { $0.kind == .transfer }.map(\.id))
        var rows: [String: GroupedSpending] = [:]
        for movement in movements where !movement.excluded && range.contains(movement.bookedOn) {
            if let category = movement.categoryId, transfers.contains(category) { continue }
            let keys: [String]
            switch grouping {
            case .tag: keys = movement.tags
            case .payee: keys = Payee.clean(movement.payee).map { [$0] } ?? []
            }
            for key in keys {
                var row = rows[key] ?? GroupedSpending(title: key, spent: .zero, income: .zero, count: 0)
                if movement.amount.isNegative {
                    row.spent = row.spent + Money(minor: -movement.amount.minor)
                } else {
                    row.income = row.income + movement.amount
                }
                row.count += 1
                rows[key] = row
            }
        }
        return rows.values.sorted {
            $0.spent.minor != $1.spent.minor ? $0.spent.minor > $1.spent.minor : $0.title < $1.title
        }
    }
}

// MARK: - Cuenta predeterminada

extension Array where Element == Account {
    /// La cuenta que sale elegida al apuntar un movimiento: la marcada, o la primera activa.
    public var defaultAccount: Account? {
        let active = filter { !$0.isArchived }
        return active.first(where: \.isDefault) ?? active.first
    }
}

// MARK: - Formatos de banco recordados (CSV)

/// Formato de un CSV ya importado, para no tener que elegir columnas la próxima vez.
/// Se reconoce por la fila de cabecera (o por el número de columnas si no hay).
public struct CSVSavedFormat: Codable, Hashable, Sendable {
    public var fingerprint: String
    public var headerRow: Int?
    public var date: Int
    public var description: Int
    public var signedAmount: Int?
    public var debit: Int?
    public var credit: Int?
    public var monthFirst: Bool
    /// Cuenta a la que se importó la última vez.
    public var accountId: UUID?

    public init(table: CSVTable, mapping: CSVMapping, accountId: UUID?) {
        fingerprint = Self.fingerprint(of: table, headerRow: mapping.headerRow)
        headerRow = mapping.headerRow
        date = mapping.date
        description = mapping.description
        switch mapping.amount {
        case .signed(let column): signedAmount = column
        case .split(let d, let c): debit = d; credit = c
        }
        monthFirst = mapping.dateOrder == .monthDayYear
        self.accountId = accountId
    }

    public var mapping: CSVMapping? {
        let amount: CSVMapping.AmountColumns
        if let signedAmount {
            amount = .signed(signedAmount)
        } else if let debit, let credit {
            amount = .split(debit: debit, credit: credit)
        } else {
            return nil
        }
        return CSVMapping(headerRow: headerRow, date: date, description: description, amount: amount,
                          dateOrder: monthFirst ? .monthDayYear : .dayMonthYear)
    }

    /// Huella de la cabecera: sus nombres normalizados. Sin cabecera, el número de columnas.
    public static func fingerprint(of table: CSVTable, headerRow: Int?) -> String {
        if let headerRow, table.rows.indices.contains(headerRow) {
            return "h:" + table.rows[headerRow].map(CSVMapping.normalize).joined(separator: "|")
        }
        let width = table.rows.prefix(20).map(\.count).max() ?? 0
        return "n:\(width)"
    }

    /// El formato guardado que encaja con este archivo, si hay alguno.
    public static func match(_ table: CSVTable, in saved: [CSVSavedFormat]) -> CSVSavedFormat? {
        for format in saved {
            if fingerprint(of: table, headerRow: format.headerRow) == format.fingerprint { return format }
        }
        return nil
    }

    /// Añade o sustituye (por huella) y deja como mucho 20, el más reciente primero.
    public static func remember(_ format: CSVSavedFormat, in saved: [CSVSavedFormat]) -> [CSVSavedFormat] {
        Array(([format] + saved.filter { $0.fingerprint != format.fingerprint }).prefix(20))
    }
}

// MARK: - Revisar un CSV fila a fila

/// Lo decidido para cada fila de un CSV antes de importarlo, por número de línea.
public struct CSVRowReview: Hashable, Sendable {
    /// Filas que no se importan.
    public var skipped: Set<Int> = []
    /// Filas que se importan como excluidas del presupuesto.
    public var excluded: Set<Int> = []
    /// Categoría elegida a mano (`.some(nil)` = sin categoría).
    public var categories: [Int: UUID?] = [:]

    public init() {}

    /// El borrador de una fila con lo decidido.
    public func apply(to draft: MovementDraft, line: Int) -> MovementDraft {
        var copy = draft
        if let category = categories[line] { copy.categoryId = category }
        if excluded.contains(line) { copy.excluded = true }
        return copy
    }

    /// Las filas que se van a importar, ya con sus cambios. Las de problema se dejan como están.
    public func apply(to rows: [CSVImportRow]) -> [CSVImportRow] {
        rows.compactMap { row in
            guard let draft = row.draft else { return row }
            if skipped.contains(row.line) { return nil }
            var copy = row
            copy.draft = apply(to: draft, line: row.line)
            return copy
        }
    }

    /// Olvida lo decidido para filas que ya no están (otro archivo u otras columnas).
    public mutating func keep(_ lines: Set<Int>) {
        skipped.formIntersection(lines)
        excluded.formIntersection(lines)
        categories = categories.filter { lines.contains($0.key) }
    }
}
