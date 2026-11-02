import SwiftUI
import STMCore
import STMUI

/// Cuentas a pagar del mes según los pagos fijos, con vista previa y PDF para compartir o imprimir.
struct BillsReportView: View {
    @Environment(FinanceModel.self) private var finance
    @Environment(PlanningModel.self) private var planning
    @State private var monthOffset = 0
    @State private var pdf: URL?
    @State private var error: String?

    private var month: MonthKey { MonthKey(CalendarDay()).adding(months: monthOffset) }
    private var bills: MonthlyBills { MonthlyBills(series: planning.series, month: month, accounts: finance.accounts) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                Picker("Mes", selection: $monthOffset) {
                    Text("Este mes").tag(0)
                    Text("El mes que viene").tag(1)
                }
                .pickerStyle(.segmented)

                BillsSummary(bills: bills, today: CalendarDay())
                    .card()

                if let pdf {
                    ShareLink(item: pdf) {
                        Label("Compartir o imprimir el PDF", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Crear PDF") { makePDF() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(bills.lines.isEmpty)
                }
                ErrorText(message: error)
                Text("Salen los cargos de suscripciones y gastos esenciales que tienes en Pagos fijos. El PDF se crea en este dispositivo.")
                    .font(Typography.small12)
                    .foregroundStyle(Palette.graphite)
            }
            .padding(Spacing.s16)
        }
        .background(Palette.linen)
        .navigationTitle("Pagos del mes")
        .onChange(of: monthOffset) { _, _ in pdf = nil }
        .onChange(of: planning.series) { _, _ in pdf = nil }
    }

    private func makePDF() {
        error = nil
        do {
            pdf = try BillsPDF.render(bills, householdName: finance.household.name, today: CalendarDay())
        } catch {
            self.error = "No se ha podido crear el PDF."
        }
    }
}

/// Resumen en pantalla de lo que hay que pagar.
struct BillsSummary: View {
    let bills: MonthlyBills
    let today: CalendarDay

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Eyebrow("Pagos de \(bills.month.title.lowercased())")
            Text(bills.total.formatted())
                .titleFont(.title36)
                .foregroundStyle(Palette.ink)
            if MonthKey(today) == bills.month {
                Text("Quedan \(bills.pending(from: today).formatted()) por pagar")
                    .font(Typography.body14)
                    .foregroundStyle(Palette.graphite)
            }
            if bills.lines.isEmpty {
                EmptyHint(text: "No hay pagos fijos este mes. Añádelos en Pagos fijos.")
            }
            ForEach(bills.lines) { line in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Spacing.s8) {
                        Text(line.name)
                            .font(Typography.body16Medium)
                            .foregroundStyle(Palette.ink)
                        Text([line.due.longTitle, line.accountName].compactMap { $0 }.joined(separator: " · "))
                            .font(Typography.small12)
                            .foregroundStyle(Palette.graphite)
                    }
                    Spacer()
                    Text(line.amount.formatted())
                        .font(Typography.body14Medium)
                        .foregroundStyle(line.due < today ? Palette.graphite : Palette.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// La hoja A4 del PDF. Siempre en claro, para imprimir.
struct BillsPDFPage: View {
    let bills: MonthlyBills
    let householdName: String
    let today: CalendarDay

    static let width: CGFloat = 595 // A4 en puntos
    static let minHeight: CGFloat = 842

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s24) {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                Eyebrow(householdName)
                Text("Pagos de \(bills.month.title.lowercased())")
                    .titleFont(.title32)
                    .foregroundStyle(Palette.ink)
                Text("Total: \(bills.total.formatted())")
                    .font(Typography.body16Medium)
                    .foregroundStyle(Palette.ink)
            }

            VStack(spacing: 0) {
                row(day: "Día", name: "Concepto", account: "Cuenta", amount: "Importe", paid: "Pagado", header: true)
                ForEach(bills.lines) { line in
                    Divider().overlay(Palette.stone)
                    row(day: line.due.longTitle, name: line.name, account: line.accountName ?? "",
                        amount: line.amount.formatted(), paid: "☐", header: false)
                }
            }

            HStack {
                ForEach([RecurringKind.subscription, .essential], id: \.self) { kind in
                    VStack(alignment: .leading, spacing: Spacing.s8) {
                        Text(kind.pluralTitle)
                            .font(Typography.small12)
                            .foregroundStyle(Palette.graphite)
                        Text(bills.total(of: kind).formatted())
                            .font(Typography.body14Medium)
                            .foregroundStyle(Palette.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)
            Text("Creado con Save the Money el \(today.longTitle) de \(String(today.year)).")
                .font(Typography.small12)
                .foregroundStyle(Palette.graphite)
        }
        .padding(Spacing.s40)
        .frame(width: Self.width, alignment: .topLeading)
        .frame(minHeight: Self.minHeight, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func row(day: String, name: String, account: String, amount: String, paid: String, header: Bool) -> some View {
        HStack(spacing: Spacing.s8) {
            Text(day).frame(width: 96, alignment: .leading)
            Text(name).frame(maxWidth: .infinity, alignment: .leading)
            Text(account).frame(width: 110, alignment: .leading)
            Text(amount).frame(width: 84, alignment: .trailing)
            Text(paid).frame(width: 48, alignment: .center)
        }
        .font(header ? Typography.small12.weight(.medium) : Typography.body14)
        .foregroundStyle(header ? Palette.graphite : Palette.ink)
        .lineLimit(2)
        .padding(.vertical, Spacing.s8)
    }
}

enum BillsPDF {
    enum Failure: Error { case render }

    @MainActor
    static func render(_ bills: MonthlyBills, householdName: String, today: CalendarDay) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("exportar", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(bills.fileName)
        try? FileManager.default.removeItem(at: url)

        let renderer = ImageRenderer(content: BillsPDFPage(bills: bills, householdName: householdName, today: today))
        renderer.proposedSize = ProposedViewSize(width: BillsPDFPage.width, height: nil)
        var written = false
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: BillsPDFPage.width, height: max(BillsPDFPage.minHeight, size.height))
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            context.translateBy(x: 0, y: box.height - size.height)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            written = true
        }
        guard written else { throw Failure.render }
        return url
    }
}
