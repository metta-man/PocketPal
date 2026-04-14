import SwiftData
import SwiftUI

private enum ManualEntryCategory: String, CaseIterable, Identifiable {
    case dining = "餐飲"
    case transport = "交通"
    case shopping = "購物"
    case entertainment = "娛樂"
    case housing = "住房"
    case medical = "醫療"
    case education = "教育"
    case other = "其他"

    var id: String { rawValue }
}

struct ManualEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage(AppPreferences.defaultCurrencyCodeKey)
    private var defaultCurrencyCode = AppPreferences.defaultCurrency.rawValue

    @AppStorage(AppPreferences.defaultExpenseTypeKey)
    private var defaultExpenseTypeRawValue = AppPreferences.defaultExpenseType.rawValue

    @State private var amountText = ""
    @State private var transactionDate = Date()
    @State private var merchantName = ""
    @State private var category = ManualEntryCategory.other
    @State private var notes = ""
    @State private var selectedCurrency = Currency.hkd
    @State private var selectedExpenseType = ExpenseType.personal
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Amount") {
                TextField("0.00", text: $amountText)
                    .receiptNumericField()

                if let amount = AmountParser.parse(amountText) {
                    Text("Parsed as \(Currency.amountString(amount, currencyCode: selectedCurrency.rawValue))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if !amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Enter a valid amount.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Details") {
                DatePicker("Date", selection: $transactionDate, displayedComponents: .date)
                TextField("Merchant", text: $merchantName)

                Picker("Currency", selection: $selectedCurrency) {
                    ForEach(Currency.allCases) { currency in
                        Text(currency.pickerTitle).tag(currency)
                    }
                }

                Picker("Category", selection: $category) {
                    ForEach(ManualEntryCategory.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }

                Picker("Expense Type", selection: $selectedExpenseType) {
                    ForEach(ExpenseType.allCases, id: \.self) { expenseType in
                        Label(expenseType.displayName, systemImage: expenseType.systemImage)
                            .tag(expenseType)
                    }
                }
            }

            Section("Notes") {
                TextField("Optional notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        #if os(iOS)
        .scrollContentBackground(.hidden)
        .background(Color.receiptGroupedBackground)
        #endif
        .navigationTitle("Manual Expense")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.receiptGroupedBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    saveManualExpense()
                }
                .disabled(AmountParser.parse(amountText) == nil || merchantName.trimmedForEntry.isEmpty)
            }
        }
        .alert("Could Not Save", isPresented: Binding(
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
        .onAppear(perform: applyDefaults)
    }

    private func applyDefaults() {
        selectedCurrency = Currency.from(code: defaultCurrencyCode) ?? .hkd
        selectedExpenseType = ExpenseType(rawValue: defaultExpenseTypeRawValue) ?? .personal
    }

    private func saveManualExpense() {
        guard let amount = AmountParser.parse(amountText) else {
            errorMessage = "Enter a valid amount."
            return
        }

        let receipt = Receipt(
            importSource: .manual,
            processingState: .ready,
            merchantName: merchantName.trimmedForEntry,
            transactionDate: transactionDate,
            totalAmount: amount,
            currencyCode: selectedCurrency.rawValue,
            category: category.rawValue,
            notes: notes.trimmedForEntry,
            expenseType: selectedExpenseType
        )
        receipt.rebuildSearchText()

        modelContext.insert(receipt)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
    var trimmedForEntry: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    NavigationStack {
        ManualEntryView()
    }
    .modelContainer(PreviewSampleData.makeContainer())
    .environment(\.serviceContainer, ServiceContainer())
}
