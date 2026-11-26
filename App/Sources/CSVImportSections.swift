import SwiftUI
import UniformTypeIdentifiers
import STMCore
import STMUI

/// Columnas detectadas, para corregirlas si el banco usa nombres raros.
struct MappingSection: View {
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
struct PreviewSection: View {
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
struct PreviewRow: View {
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
