import SwiftUI
import STMCore
import STMUI

/// Más opciones. En iPhone también da paso a lo que no cabe en la barra inferior.
struct MoreView: View {
    let profile: Profile
    let household: Household

    @Environment(SessionModel.self) private var session
    @Environment(FinanceModel.self) private var finance
    @Environment(PlanningModel.self) private var planning
    @Environment(InvestmentModel.self) private var investments
    @Environment(CreditCardModel.self) private var cards
    @AppStorage(LocalReminders.enabledKey) private var remindersEnabled = true
    @AppStorage(LocalBudgetAlerts.enabledKey) private var budgetAlertsEnabled = true
    @AppStorage(HabitSettings.logReminderKey) private var logReminder: HabitSettings.LogReminder = .off
    @AppStorage(HabitSettings.logHourKey) private var logHour = 21
    @AppStorage(HabitSettings.weeklySummaryKey) private var weeklySummary = true
    @State private var themeError: String?
    @State private var csvFile: URL?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var resetting = false

    var body: some View {
        List {
            #if os(iOS)
            Section {
                NavigationLink {
                    HouseholdView(profile: profile, household: household)
                } label: {
                    Label("Hogar: \(household.name)", systemImage: AppSection.household.systemImage)
                }
                NavigationLink {
                    CreditCardsView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppSection.creditCards.title)
                            Text("Próximo cargo, límite y compras a plazos")
                                .font(Typography.footnote)
                                .foregroundStyle(Palette.labelSecondary)
                        }
                    } icon: {
                        Image(systemName: AppSection.creditCards.systemImage)
                    }
                }
                NavigationLink {
                    RecurringView()
                } label: {
                    Label(AppSection.subscriptions.title, systemImage: AppSection.subscriptions.systemImage)
                }
                NavigationLink {
                    InvestmentsView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppSection.investments.title)
                            Text("Cartera y aportaciones automáticas")
                                .font(Typography.footnote)
                                .foregroundStyle(Palette.labelSecondary)
                        }
                    } icon: {
                        Image(systemName: AppSection.investments.systemImage)
                    }
                }
            }
            Section("Seguimiento") {
                ForEach([AppSection.netWorth, .reports, .creditScore]) { section in
                    NavigationLink {
                        switch section {
                        case .netWorth: NetWorthView()
                        case .reports: ReportsView()
                        default: CreditScoreView()
                        }
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }
            }
            #endif

            Section {
                Picker("Tema", selection: themeBinding) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                ErrorText(message: themeError)
            } header: {
                Text("Apariencia")
            } footer: {
                Text("Se guarda en tu perfil. «Automático» sigue el modo claro u oscuro del dispositivo.")
            }

            DisplayOptionsSection()

            AppLockSection()

            ChangePasswordSection()

            if !session.removedHouseholds.isEmpty {
                Section("Hogares anteriores") { RemovedHouseholdRows() }
            }

            Section {
                Toggle("Avisos de pagos fijos", isOn: $remindersEnabled)
                    .onChange(of: remindersEnabled) { _, _ in
                        // Apaga (o vuelve a encender) todos: pagos fijos, tarjetas y aportaciones.
                        Task {
                            await planning.reschedule()
                            await investments.reschedule()
                            await cards.reschedule()
                        }
                    }
                Toggle("Avisos de límites del presupuesto", isOn: $budgetAlertsEnabled)
            } header: {
                Text("Avisos")
            } footer: {
                Text("Los lanza este dispositivo: antes de cada pago fijo, cargo de tarjeta o aportación, y cuando una categoría o grupo del presupuesto llega al 80 % o se pasa.")
            }

            Section {
                Picker("Recordarme apuntar gastos", selection: $logReminder) {
                    ForEach(HabitSettings.LogReminder.allCases) { Text($0.title).tag($0) }
                }
                if logReminder != .off {
                    Stepper("A las \(logHour):00", value: $logHour, in: 6...23)
                }
                Toggle("Resumen semanal los lunes", isOn: $weeklySummary)
            } header: {
                Text("Recordatorios")
            } footer: {
                Text("Un aviso para no olvidar apuntar lo gastado y, cada lunes a las 9:00, otro con el resumen de la semana anterior.")
            }
            .onChange(of: logReminder) { _, _ in Task { await planning.rescheduleHabits() } }
            .onChange(of: logHour) { _, _ in Task { await planning.rescheduleHabits() } }
            .onChange(of: weeklySummary) { _, _ in Task { await planning.rescheduleHabits() } }

            Section("Categorías") {
                NavigationLink {
                    CategoriesView()
                } label: {
                    Label("Categorías del hogar", systemImage: "tag")
                }
            }

            Section {
                NavigationLink {
                    CSVImportView()
                } label: {
                    Label("Importar CSV del banco", systemImage: "square.and.arrow.down")
                }
                exportRow
                NavigationLink {
                    BillsReportView()
                } label: {
                    Label("PDF de pagos del mes", systemImage: "doc.richtext")
                }
                ErrorText(message: exportError)
            } header: {
                Text("Datos")
            } footer: {
                Text("Los ficheros se crean en este dispositivo y sólo salen de él si tú los compartes.")
            }

            Section {
                Button(role: .destructive) { resetting = true } label: {
                    Label("Borrar datos y empezar de cero", systemImage: "trash")
                        .foregroundStyle(Palette.negativeText)
                }
            } footer: {
                Text("Borra lo que creaste tú: cuentas, tarjetas, movimientos, presupuestos, pagos fijos, metas e inversiones. Lo que crearon otros miembros se queda, salvo lo que cuelga de algo tuyo.")
            }

            Section {
                Button { Task { await session.signOut() } } label: {
                    Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text("Sesión iniciada como \(profile.name).")
            }

            DeleteAccountSection()
        }
        .brandBackground()
        .navigationTitle("Más opciones")
        .sheet(isPresented: $resetting) { ResetHouseholdView(household: household) }
    }

    private var themeBinding: Binding<AppTheme> {
        Binding(get: { session.theme }, set: { newTheme in
            Task {
                do {
                    themeError = nil
                    try await session.setTheme(newTheme)
                } catch {
                    themeError = (error as? AppError)?.text ?? AppError.unknown("").errorDescription
                }
            }
        })
    }

    @ViewBuilder
    private var exportRow: some View {
        if let csvFile {
            ShareLink(item: csvFile) {
                Label("Compartir \(csvFile.lastPathComponent)", systemImage: "square.and.arrow.up")
            }
        } else {
            Button {
                Task { await exportCSV() }
            } label: {
                HStack {
                    Label("Exportar CSV para Excel", systemImage: "tablecells")
                    Spacer()
                    if isExporting { ProgressView() }
                }
            }
            .disabled(isExporting)
        }
    }

    private func exportCSV() async {
        isExporting = true
        defer { isExporting = false }
        exportError = nil
        guard let data = await finance.exportCSV() else {
            exportError = finance.error
            return
        }
        do {
            csvFile = try ExportFiles.write(data, named: MovementsCSV.fileName())
        } catch {
            exportError = "No se ha podido crear el fichero."
        }
    }
}

/// Ficheros exportados: van a la carpeta temporal de la app. La carpeta se vacía al arrancar, al cerrar
/// sesión y antes de cada exportación, así no quedan datos de una exportación anterior.
enum ExportFiles {
    static var folder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("exportar", isDirectory: true) }

    static func clear() {
        try? FileManager.default.removeItem(at: folder)
    }

    static func write(_ data: Data, named name: String) throws -> URL {
        clear()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        // En macOS escribir con protección completa falla (EPERM); allí sólo queda el borrado de la carpeta.
        #if os(iOS)
        let options: Data.WritingOptions = [.atomic, .completeFileProtection]
        #else
        let options: Data.WritingOptions = [.atomic]
        #endif
        try data.write(to: url, options: options)
        return url
    }
}
