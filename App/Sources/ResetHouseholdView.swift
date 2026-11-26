import SwiftUI
import STMCore
import STMUI

// MARK: - Empezar de cero

struct ResetHouseholdView: View {
    let household: Household

    @Environment(FinanceModel.self) private var finance
    @Environment(PlanningModel.self) private var planning
    @Environment(InvestmentModel.self) private var investments
    @Environment(BudgetModel.self) private var budgets
    @Environment(CreditCardModel.self) private var cards
    @Environment(TrackingModel.self) private var tracking
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var error: String?

    static let word = "BORRAR"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s24) {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        Eyebrow("Empezar de cero")
                        Text("Se borrará lo que creaste en «\(household.name)»")
                            .titleFont(.title2)
                            .foregroundStyle(Palette.label)
                        Text("Cuentas, tarjetas, movimientos, categorías propias, presupuestos, pagos fijos, metas e inversiones que creaste tú. Lo que crearon otros miembros se queda, salvo lo que cuelga de algo tuyo. Las categorías de partida vuelven a estar. Los miembros y las invitaciones se quedan.")
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.labelSecondary)
                        Text("No se puede deshacer. Si quieres guardar una copia, exporta antes el CSV.")
                            .font(Typography.subheadlineEmphasis)
                            .foregroundStyle(Palette.negativeText)
                    }
                    .card()

                    LabeledField(label: "Escribe \(Self.word) para confirmar") {
                        TextField(Self.word, text: $confirmation)
                            .plainIdentifierInput()
                    }

                    ErrorText(message: error)

                    Button {
                        Task { await reset() }
                    } label: {
                        if isWorking { ProgressView().tint(Palette.onAccent) } else { Text("Borrar todo") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!isConfirmed || isWorking)
                }
                .padding(Spacing.s16)
            }
            .background(Palette.bgGrouped)
            .navigationTitle("Borrar datos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }

    private var isConfirmed: Bool {
        confirmation.trimmingCharacters(in: .whitespaces).uppercased() == Self.word
    }

    private func reset() async {
        isWorking = true
        defer { isWorking = false }
        error = nil
        guard await finance.resetHousehold() else {
            error = finance.error
            return
        }
        // Lo mismo que ⌘R: el presupuesto y el resto se recargan aunque no hubiera movimientos que cambiaran.
        await HouseholdReload(finance: finance, budgets: budgets, planning: planning, investments: investments,
                              cards: cards, tracking: tracking).reload()
        dismiss()
    }
}
