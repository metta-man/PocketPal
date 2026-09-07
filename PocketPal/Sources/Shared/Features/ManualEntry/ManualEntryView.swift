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

private enum ManualIncomeCategory: String, CaseIterable, Identifiable {
    case clientPayment = "客戶付款"
    case salary = "薪金"
    case refund = "退款"
    case interest = "利息"
    case other = "其他收入"

    var id: String { rawValue }
}

struct ManualEntryView: View {
    var initialExpenseType: ExpenseType? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage(AppPreferences.defaultCurrencyCodeKey)
    private var defaultCurrencyCode = AppPreferences.defaultCurrency.rawValue

    @AppStorage(AppPreferences.defaultExpenseTypeKey)
    private var defaultExpenseTypeRawValue = AppPreferences.defaultExpenseType.rawValue

    @State private var amountText = ""
    @State private var transactionDate = Date()
    @State private var merchantName = ""
    @State private var transactionKind = TransactionKind.expense
    @State private var category = ManualEntryCategory.other.rawValue
    @State private var notes = ""
    @State private var selectedCurrency = Currency.hkd
    @State private var selectedExpenseType = ExpenseType.personal
    @State private var selectedTaxCategory: TaxCategory?
    @State private var errorMessage: String?

    @Environment(\.receiptWorkspace) private var workspace
    @State private var workspaceLockID = UUID()
    var body: some View {
        Form {
            Section("金額") {
                Picker("類型", selection: $transactionKind) {
                    ForEach(TransactionKind.allCases) { kind in
                        Label(kind.localizedDisplayName, systemImage: kind.systemImage)
                            .tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                TextField("0.00", text: $amountText)
                    .receiptNumericField()

                if let amount = AmountParser.parse(amountText) {
                    Text("會記錄為 \(transactionKind == .income ? "+" : "-")\(Currency.amountString(amount, currencyCode: selectedCurrency.rawValue))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if !amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("請輸入有效金額。")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("資料") {
                DatePicker("日期", selection: $transactionDate, displayedComponents: .date)
                TextField(transactionKind == .income ? "付款人" : "商戶", text: $merchantName)

                Picker("幣種", selection: $selectedCurrency) {
                    ForEach(Currency.allCases) { currency in
                        Text(currency.pickerTitle).tag(currency)
                    }
                }

                Picker("分類", selection: $category) {
                    ForEach(categoryOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }

                if transactionKind == .expense {
                    Picker("支出用途", selection: $selectedExpenseType) {
                        ForEach(ExpenseType.allCases, id: \.self) { expenseType in
                            Label(expenseType.localizedDisplayName, systemImage: expenseType.systemImage)
                                .tag(expenseType)
                        }
                    }

                    Picker("稅務分類", selection: $selectedTaxCategory) {
                        Text("不適用").tag(nil as TaxCategory?)
                        ForEach(TaxCategory.allCases, id: \.self) { taxCategory in
                            Label(taxCategory.localizedDisplayName, systemImage: taxCategory.systemImage)
                                .tag(Optional(taxCategory))
                        }
                    }
                }
            }

            Section("備註") {
                TextField("可選備註", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        #if os(iOS)
        .scrollContentBackground(.hidden)
        .background(Color.receiptGroupedBackground)
        #endif
        .navigationTitle(transactionKind == .income ? "手動收入" : "手動支出")
        .onAppear { workspace.setLocked(true, owner: workspaceLockID) }
        .onDisappear { workspace.setLocked(false, owner: workspaceLockID) }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.receiptGroupedBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button("儲存") {
                    saveManualExpense()
                }
                .disabled(AmountParser.parse(amountText) == nil || merchantName.trimmedForEntry.isEmpty)
            }
        }
        .alert("未能儲存", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知錯誤")
        }
        .onAppear(perform: applyDefaults)
        .onChange(of: selectedExpenseType) { _, newValue in
            guard transactionKind == .expense else { return }
            if newValue.isTaxDeductible, selectedTaxCategory == nil {
                selectedTaxCategory = .deductible
            } else if !newValue.isTaxDeductible {
                selectedTaxCategory = nil
            }
        }
        .onChange(of: transactionKind) { _, newValue in
            if newValue == .income {
                category = ManualIncomeCategory.clientPayment.rawValue
                selectedTaxCategory = nil
            } else {
                category = ManualEntryCategory.other.rawValue
                selectedTaxCategory = selectedExpenseType.isTaxDeductible ? .deductible : nil
            }
        }
    }

    private var categoryOptions: [String] {
        switch transactionKind {
        case .expense:
            return ManualEntryCategory.allCases.map(\.rawValue)
        case .income:
            return ManualIncomeCategory.allCases.map(\.rawValue)
        }
    }

    private func applyDefaults() {
        selectedCurrency = Currency.from(code: defaultCurrencyCode) ?? .hkd
        selectedExpenseType = initialExpenseType ?? ExpenseType(rawValue: defaultExpenseTypeRawValue) ?? .personal
        selectedTaxCategory = selectedExpenseType.isTaxDeductible ? .deductible : nil
    }

    private func saveManualExpense() {
        guard let amount = AmountParser.parse(amountText) else {
            errorMessage = "請輸入有效金額。"
            return
        }

        let receipt = Receipt(
            importSource: .manual,
            transactionKind: transactionKind,
            processingState: .ready,
            merchantName: merchantName.trimmedForEntry,
            transactionDate: transactionDate,
            totalAmount: amount,
            currencyCode: selectedCurrency.rawValue,
            category: category,
            notes: notes.trimmedForEntry,
            expenseType: selectedExpenseType,
            taxCategory: transactionKind == .expense ? selectedTaxCategory : nil
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
