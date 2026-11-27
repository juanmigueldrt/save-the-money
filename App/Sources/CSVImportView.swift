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
                    ErrorText(message: String(localized: "No he reconocido las columnas de fecha, concepto e importe de este archivo."))
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
        if isImporting { return String(localized: "Importando…") }
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
        case 0: String(localized: "Importar")
        default: String(localized: "Importar \(validCount) movimientos")
        }
    }

    private func resultText(_ result: ImportResult) -> String {
        var text = String(localized: "\(result.inserted) movimientos importados.")
        if result.duplicates > 0 { text += String(localized: " \(result.duplicates) ya estaban y no se han repetido.") }
        if createdSeries > 0 { text += String(localized: " \(createdSeries) pagos recurrentes creados.") }
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
