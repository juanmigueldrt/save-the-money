import SwiftUI
import Charts
import STMCore
import STMUI

// MARK: - Presupuesto flexible

/// Un solo número para todo lo que no son pagos fijos ni ahorro.
struct FlexBudgetCard: View {
    let flex: FlexBudget

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            Eyebrow(flex.isOver ? "Gastado de más en lo flexible" : "Te queda para lo flexible")
            Text(Money(minor: abs(flex.remaining.minor)).formatted())
                .titleFont(.largeTitle)
                .foregroundStyle(flex.isOver ? Palette.negativeText : Palette.label)
                .contentTransition(.numericText())
            ProgressBar(fraction: flex.fraction)
            if let perDay = flex.perDay {
                Text("Unos \(perDay.formatted()) al día durante \(flex.daysLeft) días")
                    .font(Typography.subheadline)
                    .foregroundStyle(Palette.labelSecondary)
            }
            Divider()
            SummaryLine(title: "Ingresos previstos", amount: flex.income)
            SummaryLine(title: "Pagos fijos (de Pagos fijos)", amount: flex.fixed)
            SummaryLine(title: "Ahorro previsto", amount: flex.savings)
            SummaryLine(title: "Para lo flexible", amount: flex.flexible, highlight: true)
            SummaryLine(title: "Gastado en lo flexible", amount: flex.flexibleSpent)
            SummaryLine(title: "Gastado en pagos fijos", amount: flex.fixedSpent)
            Text("Lo flexible es todo lo que no son pagos fijos ni ahorro: compra, ocio, restaurantes… Los gastos cuyas categorías usan tus pagos fijos cuentan como fijos.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.labelSecondary)
        }
        .card()
    }
}
