import SwiftData
import SwiftUI

struct ReceiptDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var merchantName = ""
    @State private var hasTransactionDate = false
    @State private var transactionDate = Date()
    @State private var totalAmount = ""
    @State private var currencyCode = ""
    @State private var taxAmount = ""
    @State private var category = ""
    @State private var notes = ""
    @State private var isReviewed = false
    @State private var errorMessage: String?

    let receipt: Receipt

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ReceiptAssetPreview(asset: receipt.asset)

                receiptSummary

                Form {
                    Section("Editable Fields") {
                        TextField("Merchant Name", text: $merchantName)
                        Toggle("Has Transaction Date", isOn: $hasTransactionDate)
                        if hasTransactionDate {
                            DatePicker("Transaction Date", selection: $transactionDate, displayedComponents: .date)
                        }
                        TextField("Total Amount", text: $totalAmount)
                        TextField("Currency Code", text: $currencyCode)
                        TextField("Tax Amount", text: $taxAmount)
                        TextField("Category", text: $category)
                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                        Toggle("Reviewed", isOn: $isReviewed)
                    }

                    Section("OCR") {
                        if let rawText = receipt.ocrResult?.rawText, !rawText.isEmpty {
                            Text(rawText)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        } else {
                            Text("No OCR text saved yet.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minHeight: 420)
            }
            .padding()
        }
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

    private var receiptSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(receipt.importSource.rawValue.capitalized, systemImage: "square.and.arrow.down")
            Label(receipt.asset?.originalFilename ?? "No file", systemImage: "doc")
            if let confidence = receipt.extractionConfidence {
                Label("Extraction confidence \(Int(confidence * 100))%", systemImage: "brain")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func populateState() {
        merchantName = receipt.merchantName ?? ""
        hasTransactionDate = receipt.transactionDate != nil
        transactionDate = receipt.transactionDate ?? receipt.importedAt
        totalAmount = receipt.totalAmount.map(numberString) ?? ""
        currencyCode = receipt.currencyCode ?? ""
        taxAmount = receipt.taxAmount.map(numberString) ?? ""
        category = receipt.category ?? ""
        notes = receipt.notes ?? ""
        isReviewed = receipt.reviewStatus == .reviewed
    }

    private func saveChanges() {
        receipt.merchantName = merchantName.nilIfBlank
        receipt.transactionDate = hasTransactionDate ? transactionDate : nil
        receipt.totalAmount = AmountParser.parse(totalAmount)
        receipt.currencyCode = currencyCode.nilIfBlank?.uppercased()
        receipt.taxAmount = AmountParser.parse(taxAmount)
        receipt.category = category.nilIfBlank
        receipt.notes = notes.nilIfBlank
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
