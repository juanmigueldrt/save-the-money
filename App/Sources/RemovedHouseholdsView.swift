import SwiftUI
import STMCore
import STMUI

/// Hogares de los que te han quitado (ORC-56): hasta cuándo se guardan tus datos y cómo llevártelos.
/// No pinta nada si no hay ninguno.
struct RemovedHouseholdRows: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        ForEach(session.removedHouseholds) { removed in
            RemovedHouseholdRow(removed: removed)
        }
    }
}

private struct RemovedHouseholdRow: View {
    let removed: RemovedHousehold

    @Environment(SessionModel.self) private var session
    @State private var csvFile: URL?
    @State private var isExporting = false
    @State private var error: String?

    private var untilText: String {
        removed.exportUntil.formatted(.dateTime.day().month(.wide).year().locale(AppRegion.locale))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            Text("Ya no estás en \(removed.name)")
                .font(Typography.headline)
                .foregroundStyle(Palette.label)
            Text("Lo que apuntaste allí se guarda hasta el \(untilText) y después se borra. Hasta entonces puedes exportar tus movimientos.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
            if let csvFile {
                ShareLink(item: csvFile) {
                    Label("Compartir \(csvFile.lastPathComponent)", systemImage: "square.and.arrow.up")
                }
            } else {
                Button {
                    Task { await export() }
                } label: {
                    HStack {
                        Label("Exportar mis movimientos (CSV)", systemImage: "tablecells")
                        if isExporting { ProgressView() }
                    }
                }
                .disabled(isExporting)
            }
            ErrorText(message: error)
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        error = nil
        do {
            let export = try await session.services.households.removedHouseholdExport(removed.householdId)
            let data = MovementsCSV.data(export.movements, accounts: export.accounts, categories: export.categories)
            csvFile = try ExportFiles.write(data, named: MovementsCSV.fileName())
        } catch let appError as AppError {
            error = appError.text ?? String(localized: "No se han podido exportar los movimientos.")
        } catch {
            self.error = String(localized: "No se ha podido crear el fichero.")
        }
    }
}
