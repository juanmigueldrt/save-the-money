import SwiftUI
import Charts
import STMCore
import STMUI

// MARK: - Formularios

/// Crear o editar un activo.
struct HoldingFormView: View {
    let holding: Holding?

    @Environment(InvestmentModel.self) private var investments
    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = ""
    @State private var kind: InvestmentKind = .fund
    @State private var assetClass: AssetClass = .equity
    @State private var ownerId: UUID?
    @State private var accountId: UUID?
    @State private var price = ""
    @State private var feeRate = ""
    @State private var note = ""
    /// Identificador del activo nuevo, uno por formulario: reintentar el alta con el mismo no crea otro.
    @State private var newHoldingId = UUID()
    @State private var error: String?
    @State private var isWorking = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre, p. ej. Fondo indexado mundial", text: $name)
                    TextField("Ticker o ISIN (opcional)", text: $symbol)
                        .plainIdentifierInput()
                    Picker("Tipo", selection: $kind) {
                        ForEach(InvestmentKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .onChange(of: kind) { _, new in if holding == nil { assetClass = new.defaultAssetClass } }
                    Picker("Clase", selection: $assetClass) {
                        ForEach(AssetClass.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    TextField("Precio actual por participación", text: $price)
                        .decimalInput()
                    TextField("Comisión de compra en %, p. ej. 0,2", text: $feeRate)
                        .decimalInput()
                } footer: {
                    Text("El precio lo apuntas tú: búscalo en tu bróker o banco cuando quieras actualizarlo.")
                }
                Section {
                    Picker("De quién es", selection: $ownerId) {
                        Text("Compartido").tag(UUID?.none)
                        ForEach(investments.members) { Text($0.profile.name).tag(Optional($0.profile.id)) }
                    }
                    Picker("Dónde está", selection: $accountId) {
                        Text("Ninguna cuenta").tag(UUID?.none)
                        ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    TextField("Nota (opcional)", text: $note)
                } footer: {
                    Text("Todo el hogar ve las inversiones, como las cuentas.")
                }
                if let holding {
                    Section {
                        Button(holding.isArchived ? "Desarchivar" : "Archivar") { Task { await toggleArchive() } }
                        Button("Borrar activo y sus operaciones", role: .destructive) { confirmingDelete = true }
                    }
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle(holding == nil ? "Nuevo activo" : "Editar activo")
            .formToolbar(isWorking: isWorking, cancel: { dismiss() }, save: { await save() })
            .confirmationDialog("¿Borrar este activo?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Borrar activo", role: .destructive) { Task { await delete() } }
            } message: {
                Text("Se borran también sus precios, operaciones y aportaciones automáticas, para todo el hogar. No se puede deshacer.")
            }
        }
        .frame(minWidth: 380, minHeight: 520)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let holding else { return }
        name = holding.name
        symbol = holding.symbol ?? ""
        kind = holding.kind
        assetClass = holding.assetClass
        ownerId = holding.ownerId
        accountId = holding.accountId
        price = holding.price > 0 ? InvestmentText.plain(holding.price) : ""
        feeRate = holding.feeRate > 0 ? InvestmentText.plain(holding.feeRate) : ""
        note = holding.note ?? ""
    }

    private func save() async {
        let trimmedPrice = price.trimmingCharacters(in: .whitespaces)
        let trimmedFee = feeRate.trimmingCharacters(in: .whitespaces)
        guard let priceValue = trimmedPrice.isEmpty ? 0 : Decimal(parsing: trimmedPrice, maxFractionDigits: 6) else {
            error = "Escribe el precio con coma para los decimales, p. ej. 12,50."
            return
        }
        guard let feeValue = trimmedFee.isEmpty ? 0 : Decimal(parsing: trimmedFee, maxFractionDigits: 3) else {
            error = "Escribe la comisión con números, p. ej. 0,2."
            return
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var item = holding ?? Holding(id: newHoldingId, householdId: investments.household.id, name: name)
        let priceChanged = holding.map { $0.price != priceValue } ?? (priceValue > 0)
        item.name = name
        item.symbol = symbol
        item.kind = kind
        item.assetClass = assetClass
        item.ownerId = ownerId
        item.accountId = accountId
        item.feeRate = feeValue
        item.note = trimmedNote.isEmpty ? nil : trimmedNote
        if holding == nil { item.price = priceValue; item.priceOn = priceValue > 0 ? CalendarDay() : nil }
        if let issue = item.issue { error = issue.text; return }
        isWorking = true
        defer { isWorking = false }
        guard let saved = await investments.save(item) else { error = investments.error; return }
        // Un precio nuevo también queda en el histórico, para el gráfico.
        if priceChanged, priceValue > 0 {
            await investments.recordPrice(priceValue, on: CalendarDay(), for: saved)
        }
        dismiss()
    }

    private func toggleArchive() async {
        guard var item = holding else { return }
        item.archivedAt = item.isArchived ? nil : Date()
        if await investments.save(item) != nil { dismiss() } else { error = investments.error }
    }

    private func delete() async {
        guard let holding else { return }
        if await investments.delete(holding) { dismiss() } else { error = investments.error }
    }
}

/// Apuntar el precio de un día.
struct RecordPriceView: View {
    let holding: Holding

    @Environment(InvestmentModel.self) private var investments
    @Environment(\.dismiss) private var dismiss
    @State private var price = ""
    @State private var pricedOn = Date()
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Precio por participación", text: $price)
                        .decimalInput()
                    DatePicker("Fecha", selection: $pricedOn, in: ...Date(), displayedComponents: .date)
                } footer: {
                    Text("Si ya habías apuntado un precio ese día, se sustituye.")
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle("Apuntar precio")
            .formToolbar(isWorking: isWorking, cancel: { dismiss() }, save: { await save() })
        }
        .frame(minWidth: 340, minHeight: 280)
        .onAppear { if holding.price > 0 { price = InvestmentText.plain(holding.price) } }
    }

    private func save() async {
        guard let value = Decimal(parsing: price, maxFractionDigits: 6), value > 0 else {
            error = "Escribe el precio con coma para los decimales, p. ej. 12,50."
            return
        }
        isWorking = true
        defer { isWorking = false }
        if await investments.recordPrice(value, on: CalendarDay(pricedOn), for: holding) { dismiss() } else {
            error = investments.error
        }
    }
}

/// Apuntar una venta.
struct SellView: View {
    let holding: Holding

    @Environment(InvestmentModel.self) private var investments
    @Environment(FinanceModel.self) private var finance
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = ""
    @State private var price = ""
    @State private var fee = ""
    @State private var soldOn = Date()
    @State private var accountId: UUID?
    /// Uno por formulario: reintentar tras un fallo no duplica la venta.
    @State private var tradeId = UUID()
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        let held = investments.position(of: holding).quantity
        NavigationStack {
            Form {
                Section {
                    TextField("Participaciones (tienes \(InvestmentText.quantity(held)))", text: $quantity)
                        .decimalInput()
                    TextField("Precio por participación", text: $price)
                        .decimalInput()
                    TextField("Comisión en € (opcional)", text: $fee)
                        .decimalInput()
                    DatePicker("Fecha", selection: $soldOn, in: ...Date(), displayedComponents: .date)
                }
                Section {
                    Picker("Ingresar en", selection: $accountId) {
                        Text("No apuntar en ninguna cuenta").tag(UUID?.none)
                        ForEach(finance.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                } footer: {
                    Text("Si eliges una cuenta, se apunta allí lo que recibes.")
                }
                if let error {
                    Section { ErrorText(message: error) }
                }
            }
            .formStyle(.grouped)
            .brandBackground()
            .navigationTitle("Vender")
            .formToolbar(isWorking: isWorking, cancel: { dismiss() }, save: { await save() })
        }
        .frame(minWidth: 360, minHeight: 380)
        .onAppear {
            price = InvestmentText.plain(holding.price)
            accountId = holding.accountId
        }
    }

    private func save() async {
        guard let amount = Decimal(parsing: quantity), let priceValue = Decimal(parsing: price, maxFractionDigits: 6) else {
            error = "Escribe las participaciones y el precio con coma para los decimales, p. ej. 0,125."
            return
        }
        let trimmedFee = fee.trimmingCharacters(in: .whitespaces)
        guard let feeValue = trimmedFee.isEmpty ? Money.zero : Money(entered: trimmedFee) else {
            error = "Escribe la comisión con números."
            return
        }
        let day = CalendarDay(soldOn)
        let trade = InvestmentTrade(id: tradeId, householdId: holding.householdId, holdingId: holding.id, tradedOn: day,
                                    side: .sell, quantity: amount, price: priceValue, fee: feeValue)
        isWorking = true
        defer { isWorking = false }
        guard await investments.sell(trade, of: holding, into: accountId, finance: finance) else {
            error = investments.error
            return
        }
        dismiss()
    }
}
