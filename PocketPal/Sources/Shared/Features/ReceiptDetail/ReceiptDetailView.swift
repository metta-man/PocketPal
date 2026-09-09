import SwiftData
import SwiftUI

// A route captures the selected list before confirmation removes its rows.
struct ReceiptReviewRoute: Identifiable, Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id = UUID()
    let receipt: Receipt
    let queue: [Receipt]
    let isReviewSession: Bool

    init(receipt: Receipt, queue: [Receipt]) {
        self.receipt = receipt
        self.queue = queue
        isReviewSession = receipt.reviewStatus != .reviewed
    }
}

struct ReceiptReviewSession {
    private(set) var current: Receipt
    private struct Entry {
        let id: UUID
        let receipt: Receipt
        let wasPersisted: Bool
    }
    private var remaining: [Entry]

    init(receipt: Receipt, queue: [Receipt]) {
        current = receipt
        var seen = Set<UUID>([receipt.id])
        remaining = queue.filter { seen.insert($0.id).inserted }.map {
            Entry(id: $0.id, receipt: $0, wasPersisted: $0.modelContext != nil)
        }
    }

    var nextReceipt: Receipt? {
        remaining.first { entry in
            let receipt = entry.receipt
            guard !entry.wasPersisted || receipt.modelContext != nil else { return false }
            return !receipt.isDeleted && receipt.reviewStatus != .reviewed && receipt.processingState == .ready
        }?.receipt
    }

    mutating func advance() -> Bool {
        guard current.reviewStatus == .reviewed, let next = nextReceipt else { return false }
        current = next
        remaining.removeAll { $0.id == next.id }
        return true
    }
}

struct ReceiptDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: ReceiptReviewSession
    private let isReviewSession: Bool

    init(receipt: Receipt, reviewQueue: [Receipt]? = nil) {
        _session = State(initialValue: ReceiptReviewSession(receipt: receipt, queue: reviewQueue ?? []))
        isReviewSession = reviewQueue != nil
    }

    @Environment(\.receiptWorkspace) private var workspace
    @State private var workspaceLockID = UUID()
    var body: some View {
        ReceiptReviewEditor(
            receipt: session.current,
            confirmationTitle: isReviewSession
                ? (session.nextReceipt == nil ? "確認並完成" : "確認並下一張")
                : "確認資料",
            onConfirmed: {
                guard isReviewSession else { return }
                if !session.advance() { dismiss() }
            }
        )
        .id(session.current.id)
        .onAppear { workspace.setLocked(true, owner: workspaceLockID) }
        .onDisappear { workspace.setLocked(false, owner: workspaceLockID) }
    }
}

private struct ReceiptReviewEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.serviceContainer) private var services
    private let categoryClassifier = ReceiptCategoryClassifier()

    @State private var merchantName = ""
    @State private var itemDescription = ""
    @State private var hasTransactionDate = false
    @State private var transactionDate = Date()
    @State private var totalAmount = ""
    @State private var selectedCurrency = Currency.hkd
    @State private var taxAmount = ""
    @State private var category = ""
    @State private var isEditingCategory = false
    @State private var notes = ""
    @State private var transactionKind = TransactionKind.expense
    @State private var expenseType = ExpenseType.personal
    @State private var selectedTaxCategory: TaxCategory?
    @State private var isShowingMore = false
    @State private var hasLoaded = false
    @State private var loadedInputs: [String] = []
    @State private var savedValues: ReceiptReviewValues?
    @State private var isShowingOCRText = false
    @State private var isImprovingWithCloud = false
    @State private var isConfirmingCloudEnhancement = false
    @State private var hasSavedGeminiAPIKey = false
    @State private var errorMessage: String?

    let receipt: Receipt
    let confirmationTitle: String
    let onConfirmed: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader
                NavigationLink("付款、附件、項目及審批") { FinanceRecordView(receipt: receipt) }
                if receipt.asset != nil || isTaxExportCandidate { evidenceCard }
                if receipt.asset != nil { geminiActionCard }
                editableFieldsCard
                    .disabled(isImprovingWithCloud || receipt.processingState.isActive)
                if !currentReviewIssues.isEmpty {
                    ReviewIssueList(
                        issues: currentReviewIssues,
                        readyTitle: "資料已齊",
                        readyMessage: "核對後即可確認。"
                    )
                }
                if receipt.asset != nil || receipt.ocrResult != nil {
                    ocrCard
                }
            }
            .padding()
        }
        .background(Color.receiptGroupedBackground)
        .safeAreaInset(edge: .bottom) { reviewCompletionCard }
        .navigationTitle(receipt.displayMerchantName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("儲存草稿") {
                    saveChanges(confirmed: false)
                }
                .disabled(isImprovingWithCloud || !hasLoaded)
            }
        }
        .alert("儲存失敗", isPresented: Binding(
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
        .confirmationDialog("用 Gemini 重新抽取？", isPresented: $isConfirmingCloudEnhancement, titleVisibility: .visible) {
            Button("上傳並抽取") {
                Task {
                    await improveWithCloud()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(cloudEnhancementConfirmationMessage)
        }
        .onAppear {
            loadGeminiKeyState()
            guard !hasLoaded else { return }
            populateState()
            hasLoaded = true
        }
        .onChange(of: receipt.processingState) { oldValue, newValue in
            if oldValue.isActive && !newValue.isActive && !isImprovingWithCloud && currentInputs == loadedInputs {
                populateState()
            }
        }
        .onChange(of: transactionKind) { _, newValue in
            if newValue == .income {
                selectedTaxCategory = nil
            } else if expenseType.isTaxDeductible, selectedTaxCategory == nil {
                selectedTaxCategory = .deductible
            }
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(receipt.processingState == .ready ? currentReadinessLabel : receipt.localizedProcessingStatusLabel,
                  systemImage: hasConfirmedValues ? "checkmark.seal.fill" : "checklist")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(hasConfirmedValues ? Color.receiptAccentGreen : Color.receiptAccentBlue)
            if let message = receipt.processingErrorMessage, !message.isEmpty {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.receiptAccentRed)
            }
            if let message = receipt.cloudExtractionErrorMessage, !message.isEmpty {
                Label(message, systemImage: "icloud.slash")
                    .font(.caption).foregroundStyle(.receiptAccentRed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func populateState() {
        merchantName = receipt.merchantName ?? ""
        itemDescription = receipt.itemDescription ?? ""
        hasTransactionDate = receipt.transactionDate != nil
        transactionDate = receipt.transactionDate ?? receipt.importedAt
        totalAmount = receipt.totalAmount.map(numberString) ?? ""
        selectedCurrency = receipt.resolvedCurrency
        taxAmount = receipt.taxAmount.map(numberString) ?? ""
        category = receipt.category?.nilIfBlank ?? categoryClassifier.category(
            forMerchant: receipt.merchantName,
            rawText: [receipt.itemDescription, receipt.ocrResult?.rawText].compactMap { $0 }.joined(separator: "\n")
        )?.rawValue ?? ""
        notes = receipt.notes ?? ""
        transactionKind = receipt.transactionKind
        expenseType = receipt.expenseType
        selectedTaxCategory = receipt.taxCategory
        savedValues = currentValues
        loadedInputs = currentInputs
    }

    private var evidenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("原始收據")
                    .font(.headline)
                ReceiptStatusPill(
                    title: receipt.asset == nil ? "沒有附件" : "已保留",
                    tint: receipt.asset == nil ? .receiptAccentOrange : .receiptAccentGreen,
                    systemImage: receipt.asset == nil ? "doc.badge.plus" : "doc"
                )
            }

            if receipt.asset == nil {
                Text("這是手動記錄。業務或報銷支出需要收據附件才可以確認及匯出。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ReceiptAssetPreview(asset: receipt.asset)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var reviewCompletionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(completionTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { performPrimaryAction() } label: {
                Label(primaryActionTitle, systemImage: primaryActionIcon)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.receiptAccentBlue)
            .disabled(!canMarkReviewedFromCurrentState || isImprovingWithCloud || !hasLoaded)
            .accessibilityIdentifier("review.confirm")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.receiptCardBackground)
    }

    private var editableFieldsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("核對資料").font(.headline)
            fieldStack(title: "商戶") {
                TextField("商戶名稱", text: $merchantName)
                    .accessibilityIdentifier("review.merchant")
            }
            fieldStack(title: "交易日期") {
                if hasTransactionDate {
                    DatePicker("日期", selection: $transactionDate, displayedComponents: .date)
                } else {
                    Button("填上日期") { hasTransactionDate = true }
                }
            }
            if receipt.extractionProvider == .gemini && receipt.currencyCode == nil {
                Text("Gemini 未能判斷幣種，請核對下方選擇後再確認。")
                    .font(.caption).foregroundStyle(.receiptAccentOrange)
            }
            fieldStack(title: "金額") {
                TextField("總額", text: $totalAmount)
                    .receiptNumericField()
                    .accessibilityIdentifier("review.amount")
                Picker("幣種", selection: $selectedCurrency) {
                    ForEach(Currency.allCases) { currency in
                        Text("\(currency.flag) \(currency.rawValue)").tag(currency)
                    }
                }
            }
            if transactionKind == .expense {
                Picker("支出用途", selection: $expenseType) {
                    ForEach(ExpenseType.allCases, id: \.self) { option in
                        Text(option.localizedDisplayName).tag(option)
                    }
                }
            }
            fieldStack(title: "分類") {
                if let value = effectiveCategory {
                    HStack {
                        Text(ReceiptCategory(rawValue: value).map(localizedCategoryName) ?? value)
                        Spacer()
                        Button(isEditingCategory ? "完成修改" : "更改") { isEditingCategory.toggle() }
                            .buttonStyle(.borderless)
                    }
                    Text("已填入分類，請核對後確認。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("暫時未能判斷分類，請補上。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if isEditingCategory || effectiveCategory == nil { categoryFields }
            }
            if isTaxExportCandidate {
                fieldStack(title: "業務 / 報銷資料") {
                    Picker("稅務分類", selection: $selectedTaxCategory) {
                        Text("請選擇").tag(nil as TaxCategory?)
                        ForEach(TaxCategory.allCases, id: \.self) { option in
                            Text(option.localizedDisplayName).tag(Optional(option))
                        }
                    }
                    Button("使用建議稅務分類") { selectedTaxCategory = suggestedTaxCategory }
                        .buttonStyle(.bordered)
                }
            }
            DisclosureGroup("更多資料", isExpanded: $isShowingMore) {
                VStack(alignment: .leading, spacing: 16) {
                    fieldStack(title: "項目 / 用途") {
                        TextField("項目 / 用途", text: $itemDescription)
                    }
                    fieldStack(title: "稅項") {
                        TextField("稅項", text: $taxAmount).receiptNumericField()
                    }
                    Picker("收支類型", selection: $transactionKind) {
                        ForEach(TransactionKind.allCases) { kind in
                            Text(kind.localizedDisplayName).tag(kind)
                        }
                    }
                    Toggle("有日期", isOn: $hasTransactionDate)
                    fieldStack(title: "備註") {
                        TextField("備註", text: $notes, axis: .vertical).lineLimit(3...6)
                    }
                }
                .padding(.top, 12)
            }
            .accessibilityIdentifier("review.more")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var categoryFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("分類", text: $category)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReceiptCategory.allCases.filter { $0 != .uncategorized }, id: \.self) { suggested in
                        Button(localizedCategoryName(suggested)) { category = suggested.rawValue }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var ocrCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            DisclosureGroup(isExpanded: $isShowingOCRText) {
                VStack(alignment: .leading, spacing: 12) {
                    if let confidence = receipt.extractionConfidence {
                        Text("抽取參考分數：\(Int(confidence * 100))%；請以原始收據為準。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let rawText = receipt.ocrResult?.rawText, !rawText.isEmpty {
                        Text(rawText)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color.receiptSecondaryFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else if receipt.processingState.isActive {
                        Label("OCR 正在讀取這張收據。", systemImage: "text.viewfinder")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("暫時未有 OCR 文字。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            } label: {
                Label("OCR 原文", systemImage: "text.viewfinder")
                    .font(.headline)
            }

        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var geminiActionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gemini 收據抽取", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.receiptAccentBlue)

            Text(geminiActionMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                isConfirmingCloudEnhancement = true
            } label: {
                Label(isImprovingWithCloud ? "Gemini 正在抽取…" : "用 Gemini 重新抽取", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.receiptAccentBlue)
            .disabled(!canImproveWithCloud || !hasSavedGeminiAPIKey || currentValues != savedValues)
            .accessibilityIdentifier("review.gemini.reextract")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var geminiActionMessage: String {
        if isImprovingWithCloud { return "完成後會顯示新結果，再由你核對及確認。" }
        if !hasSavedGeminiAPIKey { return "先到「設定」儲存 Gemini API key，再回來重新抽取。" }
        if currentValues != savedValues { return "先儲存目前修改，才可以重新抽取。" }
        if receipt.reviewStatus == .reviewed {
            return "會重新讀取原始收據，更新商戶、日期、金額等欄位，然後交回你核對。"
        }
        return "重新讀取原始收據並改善商戶、日期、金額等欄位，完成後由你核對。"
    }

    private var cloudEnhancementConfirmationMessage: String {
        let reviewNotice = receipt.reviewStatus == .reviewed ? "現有確認狀態會改回待核對。" : ""
        return "PocketPal 會把原始收據及辨識文字傳送到 Google Gemini，並更新抽取欄位。\(reviewNotice) 原始附件、備註、支出用途和稅務分類會保留。"
    }

    private func loadGeminiKeyState() {
        do {
            let savedKey = try services.keychainService.retrieveSecureString(key: AppPreferences.geminiAPIKeyKey)
            hasSavedGeminiAPIKey = savedKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        } catch {
            hasSavedGeminiAPIKey = false
        }
    }

    private func performPrimaryAction() {
        guard canMarkReviewedFromCurrentState, !isImprovingWithCloud else { return }
        if saveChanges(confirmed: true) { onConfirmed() }
    }

    // Raw UI values distinguish actual edits from new OCR/Gemini data arriving in the model.
    private var currentInputs: [String] {
        [merchantName, itemDescription, String(hasTransactionDate), String(transactionDate.timeIntervalSince1970),
         totalAmount, selectedCurrency.rawValue, taxAmount, category, notes, transactionKind.rawValue,
         expenseType.rawValue, selectedTaxCategory?.rawValue ?? ""]
    }

    private var currentValues: ReceiptReviewValues {
        var values = ReceiptReviewValues(receipt: receipt)
        values.merchantName = merchantName.nilIfBlank
        values.itemDescription = itemDescription.nilIfBlank
        values.transactionDate = hasTransactionDate ? transactionDate : nil
        values.totalAmount = AmountParser.parse(totalAmount)
        values.currencyCode = selectedCurrency.rawValue
        values.taxAmount = AmountParser.parse(taxAmount)
        values.category = effectiveCategory
        values.notes = notes.nilIfBlank
        values.transactionKindRawValue = transactionKind.rawValue
        values.expenseTypeRawValue = expenseType.rawValue
        values.taxCategoryRawValue = transactionKind == .expense ? selectedTaxCategory?.rawValue : nil
        return values
    }

    @discardableResult
    private func saveChanges(confirmed: Bool) -> Bool {
        do {
            try ReceiptReviewPersistence.save(receipt: receipt, values: currentValues, confirmed: confirmed) {
                try modelContext.save()
            }
            savedValues = currentValues
            loadedInputs = currentInputs
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    private func improveWithCloud() async {
        guard !isImprovingWithCloud else { return }
        isImprovingWithCloud = true
        defer { isImprovingWithCloud = false }

        do {
            try await services.importReceiptUseCase.enhanceWithCloud(
                for: receipt,
                modelContext: modelContext,
                uploadConsentGranted: true,
                allowReplacingConfirmedReceipt: receipt.reviewStatus == .reviewed
            )
            populateState()
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

    private var primaryActionTitle: String { confirmationTitle }
    private var primaryActionIcon: String { "checkmark.circle.fill" }
    private var hasConfirmedValues: Bool {
        receipt.reviewStatus == .reviewed && currentValues == ReceiptReviewValues(receipt: receipt) && currentReviewIssues.isEmpty
    }
    private var currentReadinessLabel: String {
        hasConfirmedValues ? "已確認" : "待確認"
    }
    private var canMarkReviewedFromCurrentState: Bool { currentReviewIssues.isEmpty }
    private var completionTitle: String {
        if hasConfirmedValues { return isTaxExportCandidate ? "已確認，可以匯出" : "已確認" }
        return canMarkReviewedFromCurrentState ? "資料已齊，請核對" : "已保存原始記錄，仍需補齊資料"
    }
    private var currentReviewIssues: [ReceiptReadinessIssue] {
        var requirements = ReceiptReviewRequirements(receipt: receipt)
        requirements.merchantName = merchantName.nilIfBlank
        requirements.transactionDate = hasTransactionDate ? transactionDate : nil
        requirements.totalAmount = AmountParser.parse(totalAmount)
        requirements.category = effectiveCategory
        requirements.isTaxExportCandidate = isTaxExportCandidate
        requirements.taxCategory = selectedTaxCategory
        return requirements.issues
    }

    private var isTaxExportCandidate: Bool {
        transactionKind == .expense && expenseType.isTaxDeductible
    }

    private func localizedCategoryName(_ category: ReceiptCategory) -> String {
        switch category {
        case .groceries:
            return "雜貨"
        case .meals:
            return "餐飲"
        case .travel:
            return "差旅"
        case .transport:
            return "交通"
        case .office:
            return "辦公"
        case .shopping:
            return "購物"
        case .utilities:
            return "水電 / 網絡"
        case .entertainment:
            return "娛樂"
        case .health:
            return "醫療"
        case .lodging:
            return "住宿"
        case .uncategorized:
            return "未分類"
        }
    }

    private var inferredCategory: String? {
        categoryClassifier
            .category(forMerchant: merchantName.nilIfBlank, rawText: [
                merchantName.nilIfBlank,
                itemDescription.nilIfBlank,
                notes.nilIfBlank,
                receipt.ocrResult?.rawText
            ]
            .compactMap { $0 }
            .joined(separator: "\n"))?
            .rawValue
    }

    private var effectiveCategory: String? {
        category.nilIfBlank ?? inferredCategory
    }

    private var suggestedTaxCategory: TaxCategory {
        let normalizedCategory = category.lowercased()
        if normalizedCategory.contains("meal") || normalizedCategory.contains("dining") || normalizedCategory.contains("餐") {
            return .meals
        }
        if normalizedCategory.contains("travel") || normalizedCategory.contains("transport") || normalizedCategory.contains("lodging") || normalizedCategory.contains("交通") {
            return .travel
        }
        if normalizedCategory.contains("office") || normalizedCategory.contains("stationery") {
            return .office
        }
        if normalizedCategory.contains("equipment") {
            return .equipment
        }
        if normalizedCategory.contains("utilit") {
            return .utilities
        }
        if expenseType.isTaxDeductible {
            return .deductible
        }
        return .nonDeductible
    }

    private var canImproveWithCloud: Bool {
        services.importReceiptUseCase.canManuallyExtract(receipt) && !isImprovingWithCloud
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
