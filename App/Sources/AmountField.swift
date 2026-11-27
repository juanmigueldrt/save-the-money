import SwiftUI
import STMCore
import STMUI

/// Campo de importe que también hace cuentas: "12,50+3×2".
/// En iPhone añade + − × ÷ encima del teclado numérico (que no los trae) y,
/// si hay una operación, enseña el resultado debajo.
struct AmountField: View {
    let title: String
    @Binding var text: String

    @FocusState private var focused: Bool

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    private var result: Money? {
        AmountExpression.hasOperation(text) ? AmountExpression.evaluate(text) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            TextField(title, text: $text)
                .decimalInput()
                .focused($focused)
            if AmountExpression.hasOperation(text) {
                Text(result.map { "= " + $0.formatted(options: .standard) } ?? String(localized: "La cuenta no está completa"))
                    .font(Typography.footnote)
                    .foregroundStyle(result == nil ? Palette.negativeText : Palette.labelSecondary)
                    .accessibilityLabel(result.map { String(localized: "Resultado: ") + $0.formatted(options: .standard) } ?? String(localized: "La cuenta no está completa"))
            }
        }
        #if os(iOS)
        .toolbar {
            if focused {
                ToolbarItemGroup(placement: .keyboard) {
                    ForEach(["+", "−", "×", "÷"], id: \.self) { symbol in
                        Button(symbol) { text += symbol }
                            .font(Typography.headline)
                            .accessibilityLabel(Self.spoken(symbol))
                    }
                    Spacer()
                    if let result {
                        Button("=") { text = result.plainText }
                            .font(Typography.headline)
                            .accessibilityLabel("Calcular")
                    }
                }
            }
        }
        #endif
    }

    private static func spoken(_ symbol: String) -> String {
        switch symbol {
        case "+": String(localized: "Más")
        case "−": String(localized: "Menos")
        case "×": String(localized: "Por")
        default: String(localized: "Entre")
        }
    }
}
