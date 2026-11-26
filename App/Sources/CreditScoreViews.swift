import SwiftUI
import Charts
import STMCore
import STMUI

// MARK: - Score crediticio

struct CreditScoreView: View {
    @Environment(TrackingModel.self) private var tracking
    @State private var adding = false
    @State private var deleting: CreditScore?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                if let latest = tracking.latestScore {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Eyebrow("Tu score crediticio")
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                            Text("\(latest.score)")
                                .titleFont(.largeTitle)
                                .foregroundStyle(Palette.label)
                            Text("de \(latest.maxScore)")
                                .font(Typography.subheadline)
                                .foregroundStyle(Palette.labelSecondary)
                            Spacer()
                            Text(latest.rating.title)
                                .font(Typography.subheadlineEmphasis)
                                .foregroundStyle(Palette.onAccent)
                                .padding(.horizontal, Spacing.s16)
                                .padding(.vertical, Spacing.s8)
                                .background(Palette.accent, in: Capsule())
                        }
                        ProgressBar(fraction: latest.fraction)
                        Text([latest.trimmedProvider, latest.recordedOn.longTitle + " de " + String(latest.recordedOn.year)]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.labelSecondary)
                    }
                    .card()
                    .accessibilityElement(children: .combine)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Eyebrow("Tu score crediticio")
                        Text("Apunta el score que te da tu banco o tu proveedor para ver cómo evoluciona.")
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.labelSecondary)
                        Button("Apuntar mi score") { adding = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .card()
                }

                if tracking.creditScores.count >= 2 {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text("Evolución")
                            .titleFont(.title2)
                            .foregroundStyle(Palette.label)
                        Chart(tracking.creditScores.reversed()) { item in
                            LineMark(x: .value("Fecha", item.recordedOn.date()), y: .value("Score", item.score))
                                .foregroundStyle(Palette.accent)
                            PointMark(x: .value("Fecha", item.recordedOn.date()), y: .value("Score", item.score))
                                .foregroundStyle(Palette.accent)
                        }
                        .chartHeight(180)
                        .accessibilityLabel("Gráfico de la evolución del score")
                    }
                    .card()
                }

                if !tracking.creditScores.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Text("Historial")
                            .titleFont(.title2)
                            .foregroundStyle(Palette.label)
                        ForEach(tracking.creditScores) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: Spacing.s8) {
                                    Text("\(item.score) de \(item.maxScore) · \(item.rating.title)")
                                        .font(Typography.headline)
                                        .foregroundStyle(Palette.label)
                                    Text([item.recordedOn.shortText, item.trimmedProvider, item.note].compactMap { $0 }
                                        .joined(separator: " · "))
                                        .font(Typography.footnote)
                                        .foregroundStyle(Palette.labelSecondary)
                                }
                                Spacer()
                                Button("Borrar", systemImage: "trash") { deleting = item }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Palette.labelSecondary)
                            }
                        }
                    }
                    .card()
                }

                Text("Sólo lo ves tú: no se comparte con el resto del hogar. Los tramos son orientativos.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                ErrorText(message: tracking.error)
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Score crediticio")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Apuntar score", systemImage: "plus") { adding = true }
            }
        }
        .task { await tracking.loadScores() }
        .refreshable { await tracking.loadScores() }
        .sheet(isPresented: $adding) { CreditScoreFormView(last: tracking.latestScore) }
        .confirmationDialog("¿Borrar este score?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                if let deleting { Task { await tracking.delete(deleting) } }
            }
        }
    }
}

struct CreditScoreFormView: View {
    let last: CreditScore?

    @Environment(TrackingModel.self) private var tracking
    @Environment(\.dismiss) private var dismiss
    @State private var score = ""
    @State private var maxScore = 850
    @State private var provider = ""
    @State private var recordedOn = Date()
    @State private var note = ""
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Score, p. ej. 720", text: $score)
                        .numberInput()
                    Picker("Escala", selection: $maxScore) {
                        ForEach([850, 900, 999, 1000, 100], id: \.self) { Text("Sobre \($0)").tag($0) }
                    }
                    TextField("Proveedor (opcional)", text: $provider)
                    DatePicker("Fecha", selection: $recordedOn, in: ...Date(), displayedComponents: .date)
                    TextField("Nota (opcional)", text: $note)
                } footer: {
                    Text("Sólo lo ves tú. No se comparte con el hogar.")
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle("Apuntar score")
            .formToolbar(isWorking: isWorking, cancel: { dismiss() }, save: { await save() })
        }
        .frame(minWidth: 360, minHeight: 420)
        .onAppear {
            if let last {
                maxScore = last.maxScore
                provider = last.trimmedProvider ?? ""
            }
        }
    }

    private func save() async {
        guard let value = Int(score.trimmingCharacters(in: .whitespaces)) else {
            error = "Escribe el score con números."
            return
        }
        let item = CreditScore(score: value, maxScore: maxScore, provider: provider, recordedOn: CalendarDay(recordedOn),
                               note: note)
        if let issue = item.issue { error = issue; return }
        isWorking = true
        defer { isWorking = false }
        if await tracking.add(item) { dismiss() } else { error = tracking.error }
    }
}
