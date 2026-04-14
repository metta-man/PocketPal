import SwiftData
import SwiftUI

struct ReceiptDetailView: View {
    @Environment(\.modelContext) private var modelContext
    private let categoryClassifier = ReceiptCategoryClassifier()

    @State private var merchantName = ""
    @State private var itemDescription = ""
    @State private var hasTransactionDate = false
    @State private var transactionDate = Date()
    @State private var totalAmount = ""
    @State private var selectedCurrency = Currency.hkd
    @State private var taxAmount = ""
    @State private var category = ""
    @State private var notes = ""
    @State private var expenseType = ExpenseType.personal
    @State private var isReviewed = false
    @State private var errorMessage: String?

    let receipt: Receipt

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ReceiptAssetPreview(asset: receipt.asset)
                    .frame(minHeight: 320)

                summaryCard
                editableFieldsCard
                if receipt.asset != nil || receipt.ocrResult != nil {
                    ocrCard
                }
            }
            .padding()
        }
        .background(Color.receiptGroupedBackground)
        .navigationTitle(receipt.displayMerchantName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    saveChanges()
                }
            }
        }
        .alert("Save Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onAppear(perform: populateState)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Receipt Summary")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    statusChip(title: receipt.processingStatusLabel, tint: statusTint, systemImage: statusIcon)
                    statusChip(title: receipt.importSource.rawValue.capitalized, tint: .receiptAccentBlue, systemImage: "square.and.arrow.down")
                    if let confidence = receipt.extractionConfidence {
                        statusChip(title: "Confidence \(Int(confidence * 100))%", tint: .receiptAccentOrange, systemImage: "brain")
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label(receipt.asset?.originalFilename ?? "Manual expense", systemImage: receipt.asset == nil ? "square.and.pencil" : "doc")
                if let processingErrorMessage = receipt.processingErrorMessage, !processingErrorMessage.isEmpty {
                    Label(processingErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.receiptAccentRed)
                }
                if let totalAmount = receipt.totalAmount {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Original: \(Currency.amountString(totalAmount, currencyCode: receipt.resolvedCurrency.rawValue))")
                        Text("HKD: \(Currency.amountString(receipt.amountInHKD ?? totalAmount, currencyCode: Currency.hkd.rawValue))")
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
    }

    private func populateState() {
        merchantName = receipt.merchantName ?? ""
        itemDescription = receipt.itemDescription ?? ""
        hasTransactionDate = receipt.transactionDate != nil
        transactionDate = receipt.transactionDate ?? receipt.importedAt
        totalAmount = receipt.totalAmount.map(numberString) ?? ""
        selectedCurrency = receipt.resolvedCurrency
        taxAmount = receipt.taxAmount.map(numberString) ?? ""
        category = receipt.category ?? ""
        notes = receipt.notes ?? ""
        expenseType = receipt.expenseType
        isReviewed = receipt.reviewStatus == .reviewed
    }

    private var editableFieldsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review & Edit")
                .font(.headline)

            fieldStack(title: "Merchant") {
                TextField("Merchant Name", text: $merchantName)
                TextField("Item", text: $itemDescription)
            }

            fieldStack(title: "Transaction Date") {
                Toggle("Has Date", isOn: $hasTransactionDate)
                if hasTransactionDate {
                    DatePicker("Date", selection: $transactionDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }

            fieldStack(title: "Amounts") {
                TextField("Total Amount", text: $totalAmount)
                    .receiptNumericField()
                TextField("Tax Amount", text: $taxAmount)
                    .receiptNumericField()

                Picker("Currency", selection: $selectedCurrency) {
                    ForEach(Currency.allCases) { currency in
                        Text("\(currency.flag) \(currency.rawValue)").tag(currency)
                    }
                }

                if let parsedAmount = AmountParser.parse(totalAmount) {
                    Text("HKD Equivalent: \(Currency.amountString(ExchangeRateTable.convertToHKD(amount: parsedAmount, from: selectedCurrency), currencyCode: Currency.hkd.rawValue))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            fieldStack(title: "Classification") {
                Picker("Expense Type", selection: $expenseType) {
                    ForEach(ExpenseType.allCases, id: \.self) { option in
                        Label(option.displayName, systemImage: option.systemImage)
                            .tag(option)
                    }
                }
                TextField("Category", text: $category)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ReceiptCategory.allCases.filter { $0 != .uncategorized }, id: \.self) { suggestedCategory in
                            Button(suggestedCategory.rawValue) {
                                category = suggestedCategory.rawValue
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            Toggle("Mark as reviewed", isOn: $isReviewed)
                .toggleStyle(.switch)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
    }

    private var ocrCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("OCR Raw Text")
                .font(.headline)

            if let rawText = receipt.ocrResult?.rawText, !rawText.isEmpty {
                Text(rawText)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.receiptSecondaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if receipt.processingState.isActive {
                Label("OCR is still running for this receipt.", systemImage: "text.viewfinder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No OCR text saved yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
    }

    private func saveChanges() {
        receipt.merchantName = merchantName.nilIfBlank
        receipt.itemDescription = itemDescription.nilIfBlank
        receipt.transactionDate = hasTransactionDate ? transactionDate : nil
        receipt.totalAmount = AmountParser.parse(totalAmount)
        receipt.currencyCode = selectedCurrency.rawValue
        receipt.taxAmount = AmountParser.parse(taxAmount)
        receipt.category = category.nilIfBlank ?? inferredCategory
        receipt.notes = notes.nilIfBlank
        receipt.expenseType = expenseType
        receipt.reviewStatus = isReviewed ? .reviewed : .inbox
        receipt.reviewedAt = isReviewed ? (receipt.reviewedAt ?? .now) : nil
        receipt.touch()
        receipt.rebuildSearchText()

        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func numberString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func fieldStack<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private func statusChip(title: String, tint: Color, systemImage: String) -> some View {
        ReceiptStatusPill(title: title, tint: tint, systemImage: systemImage)
    }

    private var inferredCategory: String? {
        categoryClassifier
            .category(forMerchant: merchantName.nilIfBlank, rawText: [
                merchantName.nilIfBlank,
                notes.nilIfBlank,
                receipt.ocrResult?.rawText
            ]
            .compactMap { $0 }
            .joined(separator: "\n"))?
            .rawValue
    }

    private var statusTint: Color {
        switch receipt.processingState {
        case .queued, .runningOCR:
            return .receiptAccentOrange
        case .ready:
            return receipt.reviewStatus == .reviewed ? .receiptAccentGreen : .receiptAccentBlue
        case .failed:
            return .receiptAccentRed
        }
    }

    private var statusIcon: String {
        switch receipt.processingState {
        case .queued:
            return "clock"
        case .runningOCR:
            return "text.viewfinder"
        case .ready:
            return receipt.reviewStatus == .reviewed ? "checkmark.seal.fill" : "sparkles"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}

private extension View {
    @ViewBuilder
    func receiptNumericField() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    NavigationStack {
        PreviewSampleData.detailPreview()
    }
    .modelContainer(PreviewSampleData.makeContainer())
    .environment(\.serviceContainer, ServiceContainer())
}
