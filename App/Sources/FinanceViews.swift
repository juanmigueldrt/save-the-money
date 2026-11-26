import SwiftUI
import Charts
import STMCore
import STMUI

/// Resumen: saldo total, cuentas y últimos movimientos.
struct SummaryView: View {
    @Environment(FinanceModel.self) private var finance
    @State private var addingAccount = false
    @State private var addingMovement = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                NavigationLink {
                    NetWorthView()
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.s8) {
                        HStack {
                            Eyebrow("Patrimonio neto")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(Typography.footnote)
                                .foregroundStyle(Palette.labelSecondary)
                        }
                        Text(finance.totalBalance.formatted())
                            .titleFont(.largeTitle)
                            .foregroundStyle(finance.totalBalance.isNegative ? Palette.negativeText : Palette.label)
                            .contentTransition(.numericText())
                        Text(netWorthChangeText)
                            .font(Typography.subheadline)
                            .foregroundStyle(Palette.labelSecondary)
                        Text("Lo que tienes menos lo que debes. Toca para ver cómo evoluciona.")
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.labelSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .card()
                }
                .buttonStyle(.plain)

                PendingChargesCard()

                SpendTodayCard()

                VStack(alignment: .leading, spacing: Spacing.s8) {
                    Eyebrow("Gastado este mes")
                    Text(MonthSummary.spent(movements: finance.recent, categories: finance.categories,
                                            monthStartDay: finance.household.monthStartDay).formatted())
                        .titleFont(.title1)
                        .foregroundStyle(Palette.label)
                        .contentTransition(.numericText())
                    Text("Sin contar traspasos entre tus cuentas.")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                .accessibilityElement(children: .combine)

                NextPaymentsCard()

                FavoriteExtraBudgetCard()

                WeeklySummaryCard()

                AdaptiveColumns {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        HStack {
                            Text("Cuentas")
                                .titleFont(.title2)
                                .foregroundStyle(Palette.label)
                            Spacer()
                            Button("Añadir", systemImage: "plus") { addingAccount = true }
                                .labelStyle(.titleAndIcon)
                                .font(Typography.subheadlineEmphasis)
                        }
                        if finance.activeAccounts.isEmpty {
                            EmptyHint(text: finance.isLoading ? "Cargando…" : "Añade tu primera cuenta para empezar a apuntar movimientos o importar un CSV del banco.")
                        }
                        ForEach(finance.activeAccounts) { account in
                            NavigationLink(value: account) {
                                AccountRow(account: account, balance: finance.balance(of: account))
                            }
                            .buttonStyle(.plain)
                        }
                        if !finance.archivedAccounts.isEmpty {
                            DisclosureGroup("Archivadas (\(finance.archivedAccounts.count))") {
                                ForEach(finance.archivedAccounts) { account in
                                    NavigationLink(value: account) {
                                        AccountRow(account: account, balance: finance.balance(of: account))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, Spacing.s8)
                                }
                            }
                            .font(Typography.subheadlineEmphasis)
                            .foregroundStyle(Palette.labelSecondary)
                        }
                    }
                    .card()
                } trailing: {
                    VStack(alignment: .leading, spacing: Spacing.s16) {
                        HStack {
                            Text("Últimos movimientos")
                                .titleFont(.title2)
                                .foregroundStyle(Palette.label)
                            Spacer()
                            NavigationLink("Ver todos") { MovementsView() }
                                .font(Typography.subheadlineEmphasis)
                        }
                        if finance.recent.isEmpty {
                            EmptyHint(text: finance.isLoading ? "Cargando…" : "Todavía no hay movimientos.")
                        }
                        ForEach(finance.recent.prefix(8)) { movement in
                            MovementRow(movement: movement, showsAccount: true)
                        }
                    }
                    .card()
                }

                ErrorText(message: finance.error)
            }
            .pageLayout()
        }
        .background(Palette.bgGrouped)
        .navigationTitle("Resumen")
        .navigationDestination(for: Account.self) { AccountDetailView(account: $0) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nuevo movimiento", systemImage: "plus") { addingMovement = true }
                    .disabled(finance.activeAccounts.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) { IncognitoButton() }
        }
        .refreshable { await finance.load() }
        .sheet(isPresented: $addingAccount) { AccountFormView(account: nil) }
        .sheet(isPresented: $addingMovement) { MovementFormView(movement: nil, accountId: nil) }
    }

    /// "+120 € este mes", como en Android.
    private var netWorthChangeText: String {
        let change = MonthSummary.netWorthChange(accounts: finance.accounts, movements: finance.recent,
                                                 monthStartDay: finance.household.monthStartDay)
        if change.minor == 0 { return "Igual que a final del mes pasado" }
        return (change.isNegative ? "−" : "+") + Money(minor: abs(change.minor)).formatted() + " este mes"
    }
}

struct AccountRow: View {
    let account: Account
    let balance: Money

    var body: some View {
        HStack(spacing: Spacing.s16) {
            Image(systemName: account.kind.systemImage)
                .frame(width: 32, height: 32)
                .foregroundStyle(Palette.label)
                .background(Palette.bgGrouped, in: RoundedRectangle(cornerRadius: Radius.input))
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(Typography.headline)
                    .foregroundStyle(Palette.label)
                Text(account.isShared ? "\(account.kind.title) · compartida" : account.kind.title)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer()
            Text(balance.formatted())
                .font(Typography.headline.monospacedDigit())
                .foregroundStyle(balance.isNegative ? Palette.negativeText : Palette.label)
                .lineLimit(1)
                .fixedSize()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct MovementRow: View {
    let movement: Movement
    var showsAccount = false
    /// En la lista agrupada por día la fecha ya está en la cabecera.
    var showsDate = true

    @Environment(FinanceModel.self) private var finance

    private var subtitle: String {
        var parts = showsDate ? [movement.bookedOn.shortText] : []
        if let category = finance.category(movement.categoryId) { parts.append(category.name) }
        if showsAccount, let account = finance.account(movement.accountId) { parts.append(account.name) }
        if let counterpart = transferCounterpart { parts.append(counterpart) }
        if let payee = movement.payee { parts.append(payee) }
        if !movement.tags.isEmpty { parts.append(movement.tags.map { "#" + $0 }.joined(separator: " ")) }
        return parts.joined(separator: " · ")
    }

    /// En una pata de transferencia, la cuenta de la otra pata: «Hacia Ahorro» o «Desde Nómina». La otra pata se
    /// busca en los recientes y en las páginas cargadas de la lista; si no está en ninguno, no se pone.
    private var transferCounterpart: String? {
        guard let transferId = movement.transferId,
              let other = finance.recent.first(where: { $0.transferId == transferId && $0.id != movement.id })
                ?? finance.list.rows.first(where: { $0.transferId == transferId && $0.id != movement.id }),
              let account = finance.account(other.accountId) else { return nil }
        return (movement.isExpense ? "Hacia " : "Desde ") + account.name
    }

    @AppStorage(DisplayPreferences.plusSignKey) private var showsPlusSign = false
    @AppStorage(DisplayPreferences.colorAmountsKey) private var colorsAmounts = true

    /// Ingresos en verde y gastos en tinta; con «Colorear importes» apagado, todo en tinta.
    private var amountColor: Color {
        guard colorsAmounts else { return Palette.label }
        return movement.isExpense ? Palette.label : Palette.positiveText
    }

    var body: some View {
        HStack(spacing: Spacing.s16) {
            MerchantBadge(description: movement.description, categoryIcon: finance.category(movement.categoryId)?.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(MovementText.display(movement.description))
                    .font(Typography.body)
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(showsPlusSign ? movement.amount.signedText() : movement.amount.formatted())
                    .font(Typography.headline)
                    .foregroundStyle(movement.excluded ? Palette.labelSecondary : amountColor)
                    .strikethrough(movement.excluded)
                if movement.excluded || movement.isReviewed {
                    HStack(spacing: Spacing.s4) {
                        if movement.excluded {
                            Image(systemName: "eye.slash")
                                .accessibilityLabel("Excluido del presupuesto")
                        }
                        if movement.isReviewed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Palette.positiveText)
                                .accessibilityLabel("Revisado")
                        }
                    }
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.labelSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Texto gris para listas vacías.
struct EmptyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.subheadline)
            .foregroundStyle(Palette.labelSecondary)
    }
}

extension Money {
    /// "1250,5" -> "1250,50" sin símbolo, para rellenar un campo editable.
    var plainText: String {
        let sign = minor < 0 ? "-" : ""
        let value = abs(minor)
        return "\(sign)\(value / 100),\(String(format: "%02d", value % 100))"
    }
}

extension View {
    /// Concepto de un movimiento: se escribe en mayúsculas, como se enseña.
    func conceptInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.characters)
        #else
        self
        #endif
    }

    /// Teclado numérico con coma en iPhone.
    func decimalInput() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    /// Teclado de números enteros en iPhone.
    func numberInput() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad)
        #else
        self
        #endif
    }
}
