import SwiftUI
import UniformTypeIdentifiers
import STMCore
import STMUI

/// Importar un CSV del banco: elegir archivo y cuenta, revisar columnas y vista previa, importar.
/// El archivo se lee en el dispositivo; al servidor sólo van los movimientos.
struct CSVImportView: View {
    @Environment(FinanceModel.self) private var finance
    @State private var choosingFile = false
    @State private var fileName: String?
    @State private var table: CSVTable?
    @State private var mapping: CSVMapping?
    @State private var accountId: UUID?
    @State private var error: String?
    @State private var result: ImportResult?
    @State private var isImporting = false
    @State private var addingAccount = false

    /// Tamaño máximo del archivo: un extracto de varios años cabe de sobra.
    private static let maxBytes = 10 * 1024 * 1024

    /// Filas interpretadas; se recalculan sólo al cambiar archivo, columnas o cuenta.
    @State private var rows: [CSVImportRow] = []

    private func recompute() {
        guard let table, let mapping, let accountId else { rows = []; return }
        rows = CSVImporter.rows(in: table, mapping: mapping, accountId: accountId)
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

            if let table, mapping != nil {
                MappingSection(table: table, mapping: Binding($mapping)!)
            } else if table != nil {
                Section {
                    ErrorText(message: "No he reconocido las columnas de fecha, concepto e importe de este archivo.")
                }
            }

            if !rows.isEmpty {
                PreviewSection(rows: rows)
            }

            if let result {
                Section {
                    Label(resultText(result), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Palette.ink)
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
        .navigationTitle("Importar CSV")
        .fileImporter(isPresented: $choosingFile,
                      allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]) { picked in
            load(picked)
        }
        .sheet(isPresented: $addingAccount) { AccountFormView(account: nil) }
        .onAppear { if accountId == nil { accountId = finance.activeAccounts.first?.id } }
        .onChange(of: finance.activeAccounts) { _, accounts in
            if accountId == nil { accountId = accounts.first?.id }
        }
        .onChange(of: mapping) { _, _ in recompute() }
        .onChange(of: accountId) { _, _ in result = nil; recompute() }
    }

    private var validDrafts: [MovementDraft] { rows.compactMap(\.draft) }

    private var importTitle: String {
        if isImporting { return "Importando…" }
        return validDrafts.isEmpty ? "Importar" : "Importar \(validDrafts.count) movimientos"
    }

    private func resultText(_ result: ImportResult) -> String {
        var text = "\(result.inserted) movimientos importados."
        if result.duplicates > 0 { text += " \(result.duplicates) ya estaban y no se han repetido." }
        return text
    }

    private func load(_ picked: Result<URL, Error>) {
        error = nil
        result = nil
        guard case .success(let url) = picked else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize, size > Self.maxBytes {
                error = "El archivo es demasiado grande (máximo 10 MB)."
                return
            }
            let data = try Data(contentsOf: url)
            guard let text = CSVTable.decode(data) else {
                error = "No he podido leer el texto del archivo."
                return
            }
            let parsed = CSVTable.parse(text)
            fileName = url.lastPathComponent
            table = parsed
            mapping = CSVMapping.detect(in: parsed)
            recompute()
        } catch {
            self.error = "No he podido abrir el archivo."
        }
    }

    private func runImport() async {
        let drafts = validDrafts
        guard !drafts.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }
        if let imported = await finance.importMovements(drafts) {
            result = imported
        } else {
            error = finance.error
        }
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

    private var problems: [CSVImportRow] { rows.filter { $0.issue != nil } }

    var body: some View {
        Section("Vista previa") {
            ForEach(rows.filter { $0.draft != nil }.prefix(10)) { row in
                if let draft = row.draft {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft.description)
                                .font(Typography.body14)
                                .lineLimit(1)
                            Text(draft.bookedOn.shortText)
                                .font(Typography.small12)
                                .foregroundStyle(Palette.graphite)
                        }
                        Spacer()
                        Text(draft.amount.formatted())
                            .font(Typography.body14Medium)
                            .foregroundStyle(draft.amount.isNegative ? Palette.ink : Palette.ember)
                    }
                }
            }
            let valid = rows.count - problems.count
            if valid > 10 {
                Text("… y \(valid - 10) más")
                    .font(Typography.small12)
                    .foregroundStyle(Palette.graphite)
            }
        }
        if !problems.isEmpty {
            Section("Filas que no se importarán (\(problems.count))") {
                ForEach(problems.prefix(10)) { row in
                    Text("Fila \(row.line): \(row.issue ?? "")")
                        .font(Typography.small12)
                        .foregroundStyle(Palette.red)
                }
            }
        }
    }
}
