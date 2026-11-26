import SwiftUI
import UniformTypeIdentifiers
import STMCore
import STMUI

/// Importar un CSV del banco: elegir archivo y cuenta, revisar columnas y vista previa, importar.
/// El archivo se lee en el dispositivo; al servidor sólo van los movimientos.
struct CSVImportView: View {
    @Environment(FinanceModel.self) private var finance
    @Environment(PlanningModel.self) private var planning
    @State private var choosingFile = false
    @State private var fileName: String?
    @State private var table: CSVTable?
    /// Texto del archivo, para volver a leerlo si el usuario cambia el separador.
    @State private var fileText: String?
    @State private var mapping: CSVMapping?
    @State private var accountId: UUID?
    @State private var error: String?
    @State private var result: ImportResult?
    @State private var createdSeries = 0
    /// Id de cada pago fijo que crea la importación, por su nombre: se fija la primera vez que se intenta guardar y se
    /// repite en cada reintento, así que repetir una importación que falló a medias no lo duplica.
    @State private var seriesIds: [String: UUID] = [:]
    /// Marcas de cada fila (por número de línea): pago fijo, suscripción o compra con tarjeta.
    @State private var marks: [Int: CSVRowMark] = [:]
    @State private var isImporting = false
    @State private var addingAccount = false
    /// Revisión fila a fila (por número de línea): no importar, categoría elegida a mano, excluir.
    @State private var review = CSVRowReview()
    /// true si las columnas salen de un formato de banco ya usado.
    @State private var usedSavedFormat = false

    /// La lectura en curso; se cancela si la hoja se cierra antes de terminar.
    @State private var loadTask: Task<Void, Never>?
    /// Mapa por defecto para el binding de las columnas: sólo se ve si hay mapeo (ver `body`).
    private static let emptyMapping = CSVMapping(headerRow: nil, date: 0, description: 0, amount: .signed(0))

    /// Filas interpretadas; se recalculan sólo al cambiar archivo, columnas o cuenta.
    @State private var rows: [CSVImportRow] = []

    private func recompute() {
        guard let table, let mapping, let accountId else { rows = []; return }
        rows = MerchantDirectory.categorize(CSVImporter.rows(in: table, mapping: mapping, accountId: accountId),
                                            with: finance.categories,
                                            learned: CategoryLearner(movements: finance.recent))
        let lines = Set(rows.map(\.line))
        marks = marks.filter { lines.contains($0.key) }
        review.keep(lines)
    }

    /// Las filas con lo decidido al revisarlas: sin las descartadas y con su categoría o «excluido».
    private var reviewedRows: [CSVImportRow] { review.apply(to: rows) }

    private var cardAccounts: [Account] {
        finance.activeAccounts.filter { $0.kind == .creditCard && $0.id != accountId }
    }

    var body: some View {
        Form {
            Section {
                Button(fileName == nil ? "Elegir archivo CSV" : "Elegir otro archivo", systemImage: "doc") {
                    choosingFile = true
                }
                if let fileName {
                    LabeledContent("Archivo", value: fileName)
                }
                Picker("Cuenta", selection: $accountId) {
                    Text("Elige una cuenta").tag(UUID?.none)
                    ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                }
                if finance.activeAccounts.isEmpty {
                    Button("Crear una cuenta", systemImage: "plus") { addingAccount = true }
                }
            } footer: {
                Text("Descarga los movimientos desde la web o la app de tu banco en formato CSV. El archivo no se sube: sólo se guardan los movimientos.")
            }

            if usedSavedFormat {
                Section {
                    Label("Columnas como la última vez con este banco.", systemImage: "clock.arrow.circlepath")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                }
            }
            if let table {
                Section {
                    Picker("Separador", selection: Binding { table.delimiter } set: { changeDelimiter($0) }) {
                        Text("Punto y coma (;)").tag(Character(";"))
                        Text("Tabulador").tag(Character("\t"))
                        Text("Coma (,)").tag(Character(","))
                    }
                } footer: {
                    Text("Si las columnas salen mal, prueba con otro separador.")
                }
            }
            if let table, mapping != nil {
                MappingSection(table: table, mapping: Binding(get: { mapping ?? Self.emptyMapping }, set: { mapping = $0 }))
            } else if table != nil {
                Section {
                    ErrorText(message: "No he reconocido las columnas de fecha, concepto e importe de este archivo.")
                }
            }

            if !rows.isEmpty {
                PreviewSection(rows: rows, marks: $marks, review: $review, cards: cardAccounts,
                               categories: finance.categories)
            }

            if let result {
                Section {
                    Label(resultText(result), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Palette.label)
                }
            }

            if let error {
                Section { ErrorText(message: error) }
            }

            Section {
                Button(importTitle) { Task { await runImport() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(validDrafts.isEmpty || isImporting)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        }
        .formStyle(.grouped)
        .brandBackground()
        .navigationTitle("Importar CSV")
        .fileImporter(isPresented: $choosingFile,
                      allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]) { picked in
            load(picked)
        }
        .sheet(isPresented: $addingAccount) { AccountFormView(account: nil) }
        .onAppear { if accountId == nil { accountId = finance.defaultAccount?.id } }
        .onChange(of: finance.activeAccounts) { _, accounts in
            if accountId == nil { accountId = accounts.first?.id }
        }
        .onChange(of: mapping) { _, _ in recompute() }
        .onChange(of: accountId) { _, _ in result = nil; recompute() }
        .onDisappear { loadTask?.cancel() }
    }

    private var validDrafts: [MovementDraft] { reviewedRows.compactMap(\.draft) }

    private var importPlan: CSVImportPlan {
        CSVImportPlan.make(rows: reviewedRows, marks: marks, householdId: finance.household.id, existing: planning.series)
    }

    private var importTitle: String {
        if isImporting { return "Importando…" }
        return Self.buttonTitle(validCount: validDrafts.count)
    }

    /// Las series con el id ya fijado para su nombre, o con el suyo (que queda fijado). `CSVImportPlan.make` les da uno
    /// nuevo cada vez y no repite un nombre dentro del plan.
    static func pinned(_ series: [RecurringSeries], ids: inout [String: UUID]) -> [RecurringSeries] {
        series.map { item in
            let id = ids[item.name] ?? item.id
            ids[item.name] = id
            return RecurringSeries(id: id, householdId: item.householdId, name: item.name, kind: item.kind, amount: item.amount,
                                   accountId: item.accountId, categoryId: item.categoryId, recurrence: item.recurrence,
                                   startsOn: item.startsOn, endsOn: item.endsOn, remindDaysBefore: item.remindDaysBefore,
                                   archivedAt: item.archivedAt, introAmount: item.introAmount, introCharges: item.introCharges,
                                   createsPending: item.createsPending, pendingFrom: item.pendingFrom, updatedAt: item.updatedAt)
        }
    }

    /// "Importar", "Importar 1 movimiento", "Importar 2 movimientos".
    static func buttonTitle(validCount: Int) -> String {
        switch validCount {
        case 0: "Importar"
        case 1: "Importar 1 movimiento"
        default: "Importar \(validCount) movimientos"
        }
    }

    private func resultText(_ result: ImportResult) -> String {
        var text = "\(result.inserted) movimientos importados."
        if result.duplicates > 0 { text += " \(result.duplicates) ya estaban y no se han repetido." }
        if createdSeries > 0 { text += createdSeries == 1 ? " 1 pago recurrente creado." : " \(createdSeries) pagos recurrentes creados." }
        return text
    }

    private func load(_ picked: Result<URL, Error>) {
        error = nil
        result = nil
        createdSeries = 0
        guard case .success(let url) = picked else { return }
        loadTask?.cancel()
        loadTask = Task { await open(url) }
    }

    /// Lee y analiza el archivo fuera del hilo principal; si se cierra la hoja antes de acabar, se cancela.
    private func open(_ url: URL) async {
        let reading = Task.detached(priority: .userInitiated) {
            try CSVFileReader.read(url, savedFormats: SavedCSVFormats.load())
        }
        do {
            let file = try await withTaskCancellationHandler {
                try await reading.value
            } onCancel: {
                reading.cancel()
            }
            guard !Task.isCancelled else { return }
            apply(file)
        } catch let failure as CSVOpenFailure {
            guard !Task.isCancelled else { return }
            error = failure.message
        } catch {
            // Cancelada: la hoja se ha cerrado y nadie debe ver nada.
        }
    }

    /// Pone en pantalla lo leído. La cuenta del formato guardado sólo se usa si todavía existe.
    private func apply(_ file: CSVLoadedFile) {
        fileText = file.text
        fileName = file.fileName
        marks = [:]
        review = CSVRowReview()
        table = file.table
        mapping = file.mapping
        usedSavedFormat = file.usedSavedFormat
        if let account = file.savedAccount, finance.activeAccounts.contains(where: { $0.id == account }) {
            accountId = account
        }
        recompute()
    }

    /// Vuelve a leer el archivo con el separador elegido y a detectar las columnas.
    private func changeDelimiter(_ delimiter: Character) {
        guard let fileText, delimiter != table?.delimiter else { return }
        let parsed = CSVTable.parse(fileText, delimiter: delimiter)
        result = nil
        marks = [:]
        review = CSVRowReview()
        table = parsed
        mapping = CSVMapping.detect(in: parsed)
        usedSavedFormat = false
        recompute()
    }

    private func runImport() async {
        let plan = importPlan
        guard !plan.drafts.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }
        error = nil
        createdSeries = 0
        guard let imported = await finance.importMovements(plan.drafts) else {
            error = finance.error
            return
        }
        // Los pagos fijos se crean después, para no dejarlos a medias si falla la importación.
        for series in Self.pinned(plan.newSeries, ids: &seriesIds) {
            if await planning.save(series) { createdSeries += 1 } else { error = planning.error }
        }
        result = imported
        if let table, let mapping {
            SavedCSVFormats.remember(CSVSavedFormat(table: table, mapping: mapping, accountId: accountId))
        }
    }
}

/// Lo que se saca de un archivo CSV, listo para la pantalla.
struct CSVLoadedFile: Sendable {
    let fileName: String
    let text: String
    let table: CSVTable
    let mapping: CSVMapping?
    /// true si las columnas salen de un formato de banco ya usado.
    let usedSavedFormat: Bool
    /// Cuenta que guardaba el formato, si lo hay.
    let savedAccount: UUID?
}

/// Por qué no se puede abrir el archivo. El mensaje es el que ve el usuario.
enum CSVOpenFailure: Error, Sendable {
    case tooLarge
    case unreadableText
    case cannotOpen

    var message: String {
        switch self {
        case .tooLarge: "El archivo es demasiado grande (máximo 10 MB)."
        case .unreadableText: "No he podido leer el texto del archivo."
        case .cannotOpen: "No he podido abrir el archivo."
        }
    }
}

/// Lectura y primer análisis del archivo elegido. No toca la pantalla: puede correr fuera del hilo principal.
enum CSVFileReader {
    /// Tamaño máximo del archivo: un extracto de varios años cabe de sobra.
    static let maxBytes = 10 * 1024 * 1024

    static func read(_ url: URL, savedFormats: [CSVSavedFormat]) throws -> CSVLoadedFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size: Int?
        do {
            size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        } catch {
            throw CSVOpenFailure.cannotOpen
        }
        if let size, size > maxBytes { throw CSVOpenFailure.tooLarge }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CSVOpenFailure.cannotOpen
        }
        try Task.checkCancellation()
        guard let text = CSVTable.decode(data) else { throw CSVOpenFailure.unreadableText }
        try Task.checkCancellation()
        let saved = CSVSavedFormat.match(text: text, in: savedFormats)
        let table = saved?.table ?? CSVTable.parse(text)
        if let saved, let known = saved.format.mapping {
            return CSVLoadedFile(fileName: url.lastPathComponent, text: text, table: table, mapping: known,
                                 usedSavedFormat: true, savedAccount: saved.format.accountId)
        }
        return CSVLoadedFile(fileName: url.lastPathComponent, text: text, table: table,
                             mapping: CSVMapping.detect(in: table), usedSavedFormat: false, savedAccount: nil)
    }
}

/// Formatos de banco recordados en este dispositivo (sólo columnas, nunca datos del archivo).
enum SavedCSVFormats {
    private static let key = "stm.csv.formats"

    static func load() -> [CSVSavedFormat] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CSVSavedFormat].self, from: data)) ?? []
    }

    static func remember(_ format: CSVSavedFormat) {
        let list = CSVSavedFormat.remember(format, in: load())
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Columnas detectadas, para corregirlas si el banco usa nombres raros.
private struct MappingSection: View {
    let table: CSVTable
    @Binding var mapping: CSVMapping

    private var headers: [String] {
        let width = table.rows.map(\.count).max() ?? 0
        let names = mapping.headerRow.map { table.rows[$0] } ?? []
        return (0..<width).map { index in
            let name = names.indices.contains(index) ? names[index] : ""
            return name.isEmpty ? "Columna \(index + 1)" : name
        }
    }

    private var usesSplitAmount: Binding<Bool> {
        Binding {
            if case .split = mapping.amount { return true }
            return false
        } set: { split in
            switch (mapping.amount, split) {
            case (.signed(let column), true): mapping.amount = .split(debit: column, credit: column)
            case (.split(let debit, _), false): mapping.amount = .signed(debit)
            default: break
            }
        }
    }

    var body: some View {
        Section("Columnas") {
            columnPicker("Fecha", selection: $mapping.date)
            Picker("Formato de fecha", selection: $mapping.dateOrder) {
                ForEach(DateOrder.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            columnPicker("Concepto", selection: $mapping.description)
            Toggle("Cargos y abonos en columnas separadas", isOn: usesSplitAmount)
            switch mapping.amount {
            case .signed(let column):
                columnPicker("Importe", selection: Binding { column } set: { mapping.amount = .signed($0) })
            case .split(let debit, let credit):
                columnPicker("Cargos (gastos)", selection: Binding { debit } set: { mapping.amount = .split(debit: $0, credit: credit) })
                columnPicker("Abonos (ingresos)", selection: Binding { credit } set: { mapping.amount = .split(debit: debit, credit: $0) })
            }
        }
    }

    private func columnPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Array(headers.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) }
        }
    }
}

/// Primeras filas tal como se van a guardar, y las que tienen problemas.
private struct PreviewSection: View {
    let rows: [CSVImportRow]
    @Binding var marks: [Int: CSVRowMark]
    @Binding var review: CSVRowReview
    let cards: [Account]
    let categories: [BudgetCategory]

    /// Al principio se ven 10; el resto, al pedirlo, para poder marcarlas todas.
    @State private var showsAll = false

    private var problems: [CSVImportRow] { rows.filter { $0.issue != nil } }

    var body: some View {
        let valid = rows.filter { $0.draft != nil }
        Section {
            ForEach(showsAll ? valid : Array(valid.prefix(10))) { row in
                if let draft = row.draft {
                    PreviewRow(draft: review.apply(to: draft, line: row.line), line: row.line,
                               mark: binding(for: row.line), review: $review, cards: cards, categories: categories)
                }
            }
            if valid.count > 10 && !showsAll {
                Button("Ver las \(valid.count) filas") { showsAll = true }
                    .font(Typography.subheadlineEmphasis)
            }
        } header: {
            HStack {
                Text("Revisa fila a fila")
                Spacer()
                if review.skipped.count > 0 {
                    Text("\(review.skipped.count) sin importar")
                }
            }
        } footer: {
            Text("Toca una fila para no importarla, cambiar su categoría o excluirla del presupuesto. En un gasto también puedes marcarlo como recurrente o suscripción (se crea un pago mensual desde esa fecha, que puedes ajustar en Pagos fijos) o como compra con tarjeta de crédito (se apunta en la tarjeta).")
        }
        if !problems.isEmpty {
            Section("Filas que no se importarán (\(problems.count))") {
                ForEach(problems.prefix(10)) { row in
                    Text("Fila \(row.line): \(row.issue ?? "")")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.negativeText)
                }
            }
        }
    }

    private func binding(for line: Int) -> Binding<CSVRowMark> {
        Binding { marks[line] ?? .none } set: { marks[line] = $0 == .none ? nil : $0 }
    }
}

/// Una fila de la vista previa, con su marca si es un gasto.
private struct PreviewRow: View {
    let draft: MovementDraft
    let line: Int
    @Binding var mark: CSVRowMark
    @Binding var review: CSVRowReview
    let cards: [Account]
    let categories: [BudgetCategory]

    private var isSkipped: Bool { review.skipped.contains(line) }

    private var kind: CategoryKind { draft.amount.isNegative ? .expense : .income }

    var body: some View {
        Menu {
            Toggle("Importar esta fila", isOn: Binding {
                !review.skipped.contains(line)
            } set: { keep in
                if keep { review.skipped.remove(line) } else { review.skipped.insert(line) }
            })
            Toggle("Excluir del presupuesto", isOn: Binding {
                review.excluded.contains(line)
            } set: { on in
                if on { review.excluded.insert(line) } else { review.excluded.remove(line) }
            })
            Picker("Categoría", selection: Binding<UUID?> {
                draft.categoryId
            } set: { review.categories[line] = .some($0) }) {
                Text("Sin categoría").tag(UUID?.none)
                ForEach(categories.filter { $0.kind == kind || $0.kind == .transfer }) {
                    Text($0.name).tag(Optional($0.id))
                }
            }
            .pickerStyle(.menu)
            if draft.amount.isNegative {
                Divider()
                Picker("Marcar como", selection: $mark) {
                    Label("Sin marcar", systemImage: "circle").tag(CSVRowMark.none)
                    Label("Recurrente", systemImage: "repeat").tag(CSVRowMark.recurring)
                    Label("Suscripción", systemImage: RecurringKind.subscription.systemImage).tag(CSVRowMark.subscription)
                    ForEach(cards) { card in
                        Label(cards.count == 1 ? "Compra con tarjeta" : "Compra con \(card.name)", systemImage: "creditcard")
                            .tag(CSVRowMark.creditCard(accountId: card.id))
                    }
                }
                .pickerStyle(.inline)
                if cards.isEmpty {
                    Text("Añade una tarjeta de crédito en Cuentas para marcar compras con tarjeta.")
                }
            }
        } label: {
            content
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        HStack {
            MerchantBadge(description: draft.description, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(MovementText.display(draft.description))
                    .font(Typography.subheadline)
                    .foregroundStyle(isSkipped ? Palette.labelTertiary : Palette.label)
                    .strikethrough(isSkipped)
                    .lineLimit(1)
                Text(detail)
                    .font(Typography.footnote)
                    .foregroundStyle(mark == .none ? Palette.labelSecondary : Palette.accentText)
            }
            Spacer()
            Text(draft.amount.formatted())
                .font(Typography.subheadlineEmphasis)
                .foregroundStyle(draft.amount.isNegative ? Palette.label : Palette.positiveText)
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        if isSkipped { return "\(draft.bookedOn.shortText) · No se importará" }
        var base = draft.bookedOn.shortText
        if let name = categories.first(where: { $0.id == draft.categoryId })?.name { base += " · " + name }
        if draft.excluded { base += " · Excluido" }
        return base + markText
    }

    private var markText: String {
        switch mark {
        case .none: return ""
        case .creditCard(let id):
            let name = cards.first { $0.id == id }?.name ?? "tarjeta"
            return " · Compra con \(name)"
        default: return " · \(mark.title), cada mes"
        }
    }
}
