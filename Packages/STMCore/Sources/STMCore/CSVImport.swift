import Foundation

/// Tabla leída de un CSV. Entiende comillas, saltos de línea dentro de comillas,
/// BOM, CRLF y los separadores habituales de los bancos (";", "," y tabulador).
public struct CSVTable: Hashable, Sendable {
    public var rows: [[String]]
    public var delimiter: Character

    public init(rows: [[String]], delimiter: Character) {
        self.rows = rows
        self.delimiter = delimiter
    }

    /// Texto del archivo: UTF-8 si lo es; si no, Windows-1252, que es lo que exportan
    /// muchos bancos españoles.
    public static func decode(_ data: Data) -> String? {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        if let text = String(data: bytes, encoding: .utf8) { return text }
        return String(data: bytes, encoding: .windowsCP1252) ?? String(data: bytes, encoding: .isoLatin1)
    }

    public static func parse(_ text: String, delimiter: Character? = nil) -> CSVTable {
        var text = text
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let sep = delimiter ?? guessDelimiter(text)

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func endField() { row.append(field.trimmingCharacters(in: .whitespaces)); field = "" }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let ch = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if ch == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else if ch == "\"" && field.trimmingCharacters(in: .whitespaces).isEmpty {
                field = ""
                inQuotes = true
            } else if ch == sep {
                endField()
            } else if ch == "\n" || ch == "\r\n" || ch == "\r" {
                endRow()
            } else {
                field.append(ch)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return CSVTable(rows: rows, delimiter: sep)
    }

    /// El separador que más se repite fuera de comillas en las primeras líneas.
    static func guessDelimiter(_ text: String) -> Character {
        let candidates: [Character] = [";", ",", "\t"]
        var counts: [Character: Int] = [:]
        var inQuotes = false
        var lines = 0
        for ch in text {
            if ch == "\"" { inQuotes.toggle() }
            else if !inQuotes, candidates.contains(ch) { counts[ch, default: 0] += 1 }
            else if !inQuotes, ch == "\n" || ch == "\r\n" { lines += 1; if lines >= 20 { break } }
        }
        return candidates.max { counts[$0, default: 0] < counts[$1, default: 0] } ?? ";"
    }
}

/// Orden de día, mes y año en las fechas del archivo.
public enum DateOrder: String, CaseIterable, Hashable, Sendable {
    case dayMonthYear, yearMonthDay, monthDayYear

    public var title: String {
        switch self {
        case .dayMonthYear: "Día/mes/año"
        case .yearMonthDay: "Año-mes-día"
        case .monthDayYear: "Mes/día/año"
        }
    }

    /// Lee "28/10/2026", "28-10-26", "2026-10-28" o "28.10.2026"; ignora la hora si la hay.
    public func parse(_ text: String) -> CalendarDay? {
        let datePart = text.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let parts = datePart.split(whereSeparator: { "/-.".contains($0) }).map(String.init)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        // Un primer bloque de 4 cifras siempre es el año.
        let order: DateOrder = parts[0].count == 4 ? .yearMonthDay : self
        var (y, m, d): (Int, Int, Int)
        switch order {
        case .dayMonthYear: (d, m, y) = (numbers[0], numbers[1], numbers[2])
        case .yearMonthDay: (y, m, d) = (numbers[0], numbers[1], numbers[2])
        case .monthDayYear: (m, d, y) = (numbers[0], numbers[1], numbers[2])
        }
        if y < 100 { y += 2000 }
        return CalendarDay(year: y, month: m, day: d)
    }
}

/// Qué columna es cada cosa. Los índices empiezan en 0.
public struct CSVMapping: Hashable, Sendable {
    public enum AmountColumns: Hashable, Sendable {
        /// Una columna con signo: negativo gasto, positivo ingreso.
        case signed(Int)
        /// Dos columnas: cargos (gastos) y abonos (ingresos).
        case split(debit: Int, credit: Int)
    }

    /// Fila de cabecera; los datos empiezan en la siguiente. nil si el archivo no tiene cabecera.
    public var headerRow: Int?
    public var date: Int
    public var description: Int
    public var amount: AmountColumns
    public var dateOrder: DateOrder

    public init(headerRow: Int?, date: Int, description: Int, amount: AmountColumns, dateOrder: DateOrder = .dayMonthYear) {
        self.headerRow = headerRow
        self.date = date
        self.description = description
        self.amount = amount
        self.dateOrder = dateOrder
    }

    public var firstDataRow: Int { (headerRow ?? -1) + 1 }

    /// Busca la cabecera en las primeras filas (muchos bancos ponen antes el titular,
    /// el IBAN o el periodo) y reconoce los nombres de columna habituales.
    public static func detect(in table: CSVTable) -> CSVMapping? {
        for (index, row) in table.rows.prefix(30).enumerated() {
            let names = row.map(normalize)
            guard let date = bestColumn(names, matching: ["fecha operacion", "fecha de operacion", "f. operacion",
                                                         "fecha contable", "fecha", "date"],
                                        excluding: ["valor"]) ?? bestColumn(names, matching: ["fecha", "date"], excluding: []),
                  let description = bestColumn(names, matching: ["concepto", "descripcion", "movimiento", "detalle",
                                                                 "description", "comercio", "beneficiario"],
                                               excluding: ["fecha"]) else { continue }
            let excluded = ["saldo", "balance", "disponible", "divisa", "moneda"]
            if let signed = bestColumn(names, matching: ["importe", "cantidad", "amount", "monto"], excluding: excluded) {
                return CSVMapping(headerRow: index, date: date, description: description,
                                  amount: .signed(signed), dateOrder: guessDateOrder(table, column: date, from: index + 1))
            }
            if let debit = bestColumn(names, matching: ["cargo", "debe", "gasto", "debit", "salida"], excluding: excluded),
               let credit = bestColumn(names, matching: ["abono", "haber", "ingreso", "credit", "entrada"], excluding: excluded) {
                return CSVMapping(headerRow: index, date: date, description: description,
                                  amount: .split(debit: debit, credit: credit),
                                  dateOrder: guessDateOrder(table, column: date, from: index + 1))
            }
        }
        return detectWithoutHeader(in: table)
    }

    /// Sin cabecera: la columna con fechas, la de importes y la de texto más largo.
    static func detectWithoutHeader(in table: CSVTable) -> CSVMapping? {
        let sample = Array(table.rows.prefix(20))
        guard let width = sample.map(\.count).max(), width >= 3 else { return nil }
        func share(_ column: Int, _ test: (String) -> Bool) -> Double {
            let values = sample.compactMap { $0.indices.contains(column) ? $0[column] : nil }.filter { !$0.isEmpty }
            guard !values.isEmpty else { return 0 }
            return Double(values.filter(test).count) / Double(values.count)
        }
        let columns = Array(0..<width)
        guard let date = columns.first(where: { share($0) { DateOrder.dayMonthYear.parse($0) != nil } > 0.8 }),
              let amount = columns.first(where: { $0 != date && share($0) { Money(parsing: $0) != nil } > 0.8 }) else { return nil }
        let textColumns = columns.filter { $0 != date && $0 != amount }
        guard let description = textColumns.max(by: { averageLength(sample, $0) < averageLength(sample, $1) }) else { return nil }
        return CSVMapping(headerRow: nil, date: date, description: description, amount: .signed(amount),
                          dateOrder: guessDateOrder(table, column: date, from: 0))
    }

    /// Día/mes salvo que algún valor sólo tenga sentido como mes/día (p. ej. "10/28/2026").
    static func guessDateOrder(_ table: CSVTable, column: Int, from start: Int) -> DateOrder {
        let values = table.rows.dropFirst(start).prefix(200).compactMap { $0.indices.contains(column) ? $0[column] : nil }
        let dmy = values.filter { DateOrder.dayMonthYear.parse($0) != nil }.count
        let mdy = values.filter { DateOrder.monthDayYear.parse($0) != nil }.count
        return mdy > dmy ? .monthDayYear : .dayMonthYear
    }

    private static func averageLength(_ rows: [[String]], _ column: Int) -> Double {
        let values = rows.compactMap { $0.indices.contains(column) ? $0[column] : nil }
        guard !values.isEmpty else { return 0 }
        return Double(values.map(\.count).reduce(0, +)) / Double(values.count)
    }

    /// La primera palabra clave de la lista que aparece en alguna columna gana.
    private static func bestColumn(_ names: [String], matching keys: [String], excluding: [String]) -> Int? {
        for key in keys {
            if let index = names.firstIndex(where: { name in
                name.contains(key) && !excluding.contains(where: name.contains)
            }) { return index }
        }
        return nil
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Una fila del CSV ya interpretada, lista para enseñar en la vista previa.
public struct CSVImportRow: Hashable, Sendable, Identifiable {
    /// Número de fila del archivo (sin contar las vacías), empezando en 1.
    public var line: Int
    public var draft: MovementDraft?
    public var issue: String?

    public var id: Int { line }
}

public enum CSVImporter {
    /// Convierte las filas de datos en movimientos de la cuenta dada.
    /// Las filas vacías o de totales sin fecha se saltan; las que tienen fecha
    /// pero algo mal se devuelven con `issue` para que el usuario lo vea.
    public static func rows(in table: CSVTable, mapping: CSVMapping, accountId: UUID) -> [CSVImportRow] {
        var seen: [String: Int] = [:]
        var result: [CSVImportRow] = []

        for index in table.rows.indices where index >= mapping.firstDataRow {
            let row = table.rows[index]
            func cell(_ column: Int) -> String { row.indices.contains(column) ? row[column] : "" }

            let rawDate = cell(mapping.date)
            if rawDate.isEmpty || row.allSatisfy(\.isEmpty) { continue }
            let line = index + 1
            guard let day = mapping.dateOrder.parse(rawDate) else {
                result.append(CSVImportRow(line: line, draft: nil, issue: "Fecha no reconocida: «\(rawDate.prefix(20))»"))
                continue
            }

            let amount: Money?
            switch mapping.amount {
            case .signed(let column):
                amount = Money(parsing: cell(column))
            case .split(let debit, let credit):
                let out = Money(parsing: cell(debit)).map { Money(minor: -abs($0.minor)) }
                let into = Money(parsing: cell(credit)).map { Money(minor: abs($0.minor)) }
                amount = [out, into].compactMap { $0 }.first { $0.minor != 0 } ?? out ?? into
            }
            guard let amount, amount.minor != 0 else {
                result.append(CSVImportRow(line: line, draft: nil, issue: "Importe vacío o no válido"))
                continue
            }

            let description = collapseSpaces(cell(mapping.description))
            let text = description.isEmpty ? "Sin concepto" : String(description.prefix(200))
            let key = "\(day.iso)|\(amount.minor)|\(CSVMapping.normalize(text))"
            let occurrence = seen[key, default: 0]
            seen[key] = occurrence + 1

            let draft = MovementDraft(accountId: accountId, bookedOn: day, amount: amount, description: text,
                                      importHash: SHA256.hex("\(key)|\(occurrence)"))
            result.append(CSVImportRow(line: line, draft: draft, issue: nil))
        }
        return result
    }

    private static func collapseSpaces(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
