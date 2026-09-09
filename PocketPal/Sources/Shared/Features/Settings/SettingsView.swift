import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsExportFormat: Identifiable {
    case csv
    case json
    case folder

    var id: String {
        switch self {
        case .csv:
            return "csv"
        case .json:
            return "json"
        case .folder:
            return "folder"
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.serviceContainer) private var services

    @Query(sort: [SortDescriptor(\Receipt.importedAt, order: .reverse)])
    private var receipts: [Receipt]

    @AppStorage(OCRPreferences.selectedLanguageCodesKey)
    private var storedLanguageCodes = OCRPreferences.defaultLanguageCodes.joined(separator: ",")

    @AppStorage(AppPreferences.defaultCurrencyCodeKey)
    private var defaultCurrencyCode = AppPreferences.defaultCurrency.rawValue

    @AppStorage(AppPreferences.defaultExpenseTypeKey)
    private var defaultExpenseTypeRawValue = AppPreferences.defaultExpenseType.rawValue

    @AppStorage(AppPreferences.taxYearStartMonthKey)
    private var taxYearStartMonth = AppPreferences.taxYearStartMonth

    @State private var deliveryExportPending = false
    @State private var showingDelivery = false
    @State private var deliveryLedger: ReceiptLedger = .personal
    @State private var deliveryStart = ReceiptDeliveryPackage.calendar.date(from: ReceiptDeliveryPackage.calendar.dateComponents([.year, .month], from: .now)) ?? .now
    @State private var deliveryEnd = Date.now
    @State private var includeUndated = false
    @State private var confirmedOnly = false
    @State private var exportDocument: PocketPalExportDocument?
    @State private var isShowingExporter = false
    @State private var exportFilename = "PocketPal-Export"
    @State private var exportContentType: UTType = .json
    @State private var clearReceiptDataConfirmation = false
    @State private var transferCandidates: [Receipt] = []
    @State private var transferConfirmation = false
    @State private var transferredCount: Int?
    @State private var errorMessage: String?

    private var selectedLanguageCodes: [String] {
        OCRPreferences.selectedRecognitionLanguages()
    }

    private var monthSymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_HK")
        return formatter.monthSymbols
    }

    var body: some View {
        settingsContent
            .sheet(isPresented: $showingDelivery, onDismiss: {
                if deliveryExportPending {
                    deliveryExportPending = false
                    isShowingExporter = true
                }
            }) { deliverySheet }
            .fileExporter(
                isPresented: $isShowingExporter,
                document: exportDocument,
                contentType: exportContentType,
                defaultFilename: exportFilename
            ) { result in
                if case .failure(let error) = result {
                    errorMessage = error.localizedDescription
                }
            }
            .alert("將個人記錄轉移至業務？", isPresented: $transferConfirmation) {
                Button("轉移 \(transferCandidates.count) 筆記錄") { transferPersonalReceipts() }
                Button("取消", role: .cancel) { transferCandidates = [] }
            } message: {
                Text("將轉移所選批次的 \(transferCandidates.count) 筆個人收據及手動記錄，包括已封存記錄。原有相片、OCR、金額及備註會保留，記錄會改為待確認，並從個人空間移至業務空間。日後新增記錄的預設用途不變。")
            }
            .alert("轉移完成", isPresented: Binding(
                get: { transferredCount != nil },
                set: { if !$0 { transferredCount = nil } }
            )) {
                Button("好", role: .cancel) { transferredCount = nil }
            } message: {
                Text("已將 \(transferredCount ?? 0) 筆記錄轉移至業務空間，請核對用途及稅務分類。")
            }
            .alert("清除收據資料？", isPresented: $clearReceiptDataConfirmation) {
                Button("清除收據", role: .destructive) {
                    clearReceiptData()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("這會永久刪除這部裝置內的所有收據資料和收據檔案。設定和 experimental accounting records 不受影響。")
            }
            .alert("設定錯誤", isPresented: Binding(
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
    }

    @ViewBuilder
    private var settingsContent: some View {
        #if os(macOS)
        settingsForm
            .formStyle(.grouped)
            .frame(width: 560)
            .frame(minHeight: 540)
            .scenePadding()
        #else
        NavigationStack {
            settingsForm
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .safeAreaPadding(.bottom, 72)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 82)
            }
            .background(Color.receiptGroupedBackground)
            .toolbarBackground(Color.receiptGroupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.receiptGroupedBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        }
        #endif
    }

    private var settingsForm: some View {
        Form {
            defaultsSection
            taxYearSection
            ocrLanguagesSection
            AdvancedCloudAISettingsSection()
            dataManagementSection
            aboutSection
        }
    }

    private var defaultsSection: some View {
        Section("預設值") {
            Picker("預設幣種", selection: $defaultCurrencyCode) {
                ForEach(Currency.allCases) { currency in
                    Text("\(currency.flag) \(currency.localizedDisplayName)").tag(currency.rawValue)
                }
            }

            Picker("支出用途", selection: $defaultExpenseTypeRawValue) {
                ForEach(ExpenseType.allCases, id: \.self) { expenseType in
                    Label(expenseType.localizedDisplayName, systemImage: expenseType.systemImage)
                        .tag(expenseType.rawValue)
                }
            }
        }
    }

    private var taxYearSection: some View {
        Section("課稅年度") {
            Picker("開始月份", selection: $taxYearStartMonth) {
                ForEach(Array(monthSymbols.enumerated()), id: \.offset) { index, month in
                    Text(month).tag(index + 1)
                }
            }

            Text(AppPreferences.localizedTaxYearDescription())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var ocrLanguagesSection: some View {
        Section {
            ForEach(OCRLanguageOption.allCases) { option in
                Toggle(isOn: binding(for: option)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.displayName)
                        Text(option.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("OCR 語言")
        } footer: {
            Text("PocketPal 下次 OCR 會使用這些語言。香港收據通常用繁體中文加英文最穩陣。")
        }
    }

    private var personalReceipts: [Receipt] {
        receipts.filter { $0.expenseType == .personal }
    }

    private var dataManagementSection: some View {
        Section {
            Button {
                transferCandidates = personalReceipts
                transferConfirmation = true
            } label: {
                SettingsActionRow(
                    title: "全部個人記錄轉移至業務",
                    subtitle: "共 \(personalReceipts.count) 筆，包括收據及手動記錄；轉移前會再次確認。",
                    systemImage: "arrow.right.arrow.left"
                )
            }
            .disabled(personalReceipts.isEmpty)
            .accessibilityIdentifier("settings.transferPersonalToBusiness")

            Button {
                prepareExport(.csv)
            } label: {
                SettingsActionRow(
                    title: "匯出 CSV / Excel",
                    subtitle: "適合 Excel、Numbers 或 Google Sheets 的表格資料。",
                    systemImage: "tablecells"
                )
            }

            Button {
                showingDelivery = true
            } label: {
                SettingsActionRow(
                    title: "整理及匯出收支紀錄包",
                    subtitle: "選期間、檢查缺件，連原始圖片及 PDF 一次匯出。",
                    systemImage: "folder.badge.plus"
                )
            }

            Button {
                prepareExport(.json)
            } label: {
                SettingsActionRow(
                    title: "匯出基本收據 JSON",
                    subtitle: "不含附件及收支追蹤；完整備份請使用收支管理內的備份功能。",
                    systemImage: "curlybraces"
                )
            }

            Button(role: .destructive) {
                clearReceiptDataConfirmation = true
            } label: {
                SettingsActionRow(
                    title: "清除收據資料",
                    subtitle: "刪除這部裝置內的收據和檔案。",
                    systemImage: "trash"
                )
            }
        } header: {
            Text("資料管理")
        } footer: {
            Text("本機儲存了 \(receipts.count) 張收據。")
        }
    }

    private var aboutSection: some View {
        Section("關於") {
            LabeledContent("版本", value: appVersion)
            LabeledContent("Build", value: appBuild)
            Text("PocketPal 幫香港用戶保存收據、整理支出，並準備報稅或報銷所需紀錄。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private func binding(for option: OCRLanguageOption) -> Binding<Bool> {
        Binding(
            get: {
                selectedLanguageCodes.contains(option.rawValue)
            },
            set: { isEnabled in
                var updatedCodes = selectedLanguageCodes

                if isEnabled {
                    updatedCodes.append(option.rawValue)
                } else {
                    updatedCodes.removeAll { $0 == option.rawValue }
                }

                OCRPreferences.updateSelectedRecognitionLanguages(updatedCodes)
                storedLanguageCodes = OCRPreferences.selectedRecognitionLanguages().joined(separator: ",")
            }
        )
    }

    private var deliveryReceipts: [Receipt] {
        ReceiptDeliveryPackage.select(receipts, ledger: deliveryLedger, start: deliveryStart, end: deliveryEnd,
                                      includeUndated: includeUndated, confirmedOnly: confirmedOnly)
    }

    private var deliveryTotals: [String] {
        var totals: [String: (income: Decimal, expense: Decimal)] = [:]
        for receipt in deliveryReceipts {
            guard receipt.totalAmount?.isFinite == true else { continue }
            let code = receipt.currencyCode ?? receipt.resolvedCurrency.rawValue
            var total = totals[code] ?? (0, 0)
            for entry in receipt.cashEntries(start: deliveryStart, end: deliveryEnd) {
                total.income += entry.income; total.expense += entry.expense
            }
            totals[code] = total
        }
        return totals.keys.sorted().map { code in
            let total = totals[code]!
            return "\(code) 收入 \(total.income.formatted()) · 支出 \(total.expense.formatted()) · 淨收支 \((total.income - total.expense).formatted())"
        }
    }

    private var deliverySheet: some View {
        NavigationStack {
            Form {
                Section("選擇紀錄") {
                    Picker("空間", selection: $deliveryLedger) {
                        ForEach(ReceiptLedger.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("開始日期", selection: $deliveryStart, displayedComponents: .date)
                    DatePicker("結束日期", selection: $deliveryEnd, displayedComponents: .date)
                    Toggle("包含無日期紀錄", isOn: $includeUndated)
                    Text("此空間有 \(receipts.filter { deliveryLedger.includes($0) && $0.transactionDate == nil }.count) 筆無日期紀錄，無法判斷所屬期間。")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("只匯出已確認紀錄", isOn: $confirmedOnly)
                }
                Section("匯出預覽") {
                    Text("匯出 \(deliveryReceipts.count) 筆；此空間排除 \(receipts.filter { deliveryLedger.includes($0) }.count - deliveryReceipts.count) 筆")
                    Text("包括月度摘要、收支明細、原幣合計、圖片、PDF 及缺件清單。")
                    Text("範圍為收支紀錄；已匯入收支管理的人工及發票會一併包含；未匯入的獨立會計資料不包含。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(deliveryTotals, id: \.self) { Text($0).font(.subheadline) }
                    Text("未確認或缺件的紀錄會清楚標示；欠金額不當作零。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(deliveryReceipts.filter { !deliveryIssues($0).isEmpty }) { receipt in
                        VStack(alignment: .leading) {
                            Text(receipt.displayMerchantName)
                            Text(deliveryIssues(receipt).joined(separator: "；"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if ReceiptDeliveryPackage.calendar.startOfDay(for: deliveryStart) > ReceiptDeliveryPackage.calendar.startOfDay(for: deliveryEnd) { Text("開始日期不可遲於結束日期。").foregroundStyle(.red) }
                }
                Section {
                    Button("匯出這 \(deliveryReceipts.count) 筆紀錄") { prepareDelivery() }
                        .disabled(deliveryReceipts.isEmpty || ReceiptDeliveryPackage.calendar.startOfDay(for: deliveryStart) > ReceiptDeliveryPackage.calendar.startOfDay(for: deliveryEnd))
                        .accessibilityIdentifier("settings.exportDeliveryPackage")
                }
            }
            .environment(\.timeZone, ReceiptDeliveryPackage.calendar.timeZone)
            .navigationTitle("整理收支紀錄")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showingDelivery = false } } }
        }
        .frame(minWidth: 320, minHeight: 460)
    }

    private func deliveryIssues(_ receipt: Receipt) -> [String] {
        ReceiptDeliveryPackage.issues(for: receipt) { services.fileStorageService.fileURL(forRelativePath: $0) }
    }

    private func prepareDelivery() {
        do {
            let selected = deliveryReceipts
            let formatter = DateFormatter()
            formatter.timeZone = ReceiptDeliveryPackage.calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            let scope = "\(deliveryLedger.title)空間；\(formatter.string(from: deliveryStart)) 至 \(formatter.string(from: deliveryEnd))；\(confirmedOnly ? "只匯出已確認" : "包含未確認")；\(includeUndated ? "包含無日期紀錄" : "排除無日期紀錄")"
            let wrapper = try ReceiptDeliveryPackage.make(receipts: selected, scope: scope,
                excludedCount: receipts.filter { deliveryLedger.includes($0) }.count - selected.count, start: deliveryStart, end: deliveryEnd) {
                    services.fileStorageService.fileURL(forRelativePath: $0)
                }
            exportDocument = PocketPalExportDocument(fileWrapper: wrapper, contentType: .folder)
            exportFilename = "PocketPal-Records-\(exportDateStamp)"
            exportContentType = .folder
            deliveryExportPending = true
            showingDelivery = false
        } catch { errorMessage = error.localizedDescription }
    }

    private func prepareExport(_ format: SettingsExportFormat) {
        do {
            switch format {
            case .csv:
                exportDocument = PocketPalExportDocument(data: makeCSVData(), contentType: .commaSeparatedText)
                exportFilename = "PocketPal-Entries-\(exportDateStamp).csv"
                exportContentType = .commaSeparatedText
            case .json:
                exportDocument = PocketPalExportDocument(data: try makeJSONData(), contentType: .json)
                exportFilename = "PocketPal-Backup-\(exportDateStamp).json"
                exportContentType = .json
            case .folder:
                exportDocument = PocketPalExportDocument(
                    fileWrapper: try makeExportFolderWrapper(),
                    contentType: .folder
                )
                exportFilename = "PocketPal-Export-\(exportDateStamp)"
                exportContentType = .folder
            }

            isShowingExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeJSONData() throws -> Data {
        let payload = SettingsExportPayload(
            exportedAt: .now,
            defaults: .init(
                currencyCode: defaultCurrencyCode,
                expenseTypeRawValue: defaultExpenseTypeRawValue,
                taxYearStartMonth: taxYearStartMonth,
                ocrLanguages: selectedLanguageCodes
            ),
            receipts: receipts.map(ReceiptExport.init)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(payload)
    }

    private func makeCSVData() -> Data {
        let rows = [
            ReceiptCSVRow.header
        ] + receipts.filter { !$0.finance.isTemplate }.map { ReceiptCSVRow(receipt: $0, photoFilename: exportPhotoFilename(for: $0)) }
            .map(\.fields)

        let csv = "\u{FEFF}" + rows
            .map { $0.map(Self.csvEscapedField).joined(separator: ",") }
            .joined(separator: "\n")

        return Data(csv.utf8)
    }

    private func makeExportFolderWrapper() throws -> FileWrapper {
        var rootFiles: [String: FileWrapper] = [
            "receipts.csv": FileWrapper(regularFileWithContents: makeCSVData())
        ]

        var photoFiles: [String: FileWrapper] = [:]
        var usedFilenames = Set<String>()

        for receipt in receipts {
            guard receipt.asset?.kind == .image,
                  let relativePath = receipt.asset?.storageRelativePath else {
                continue
            }

            let sourceURL = services.fileStorageService.fileURL(forRelativePath: relativePath)
            guard FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) else {
                continue
            }

            var filename = exportPhotoFilename(for: receipt)
            filename = uniqueFilename(filename, usedFilenames: &usedFilenames)
            let wrapper = FileWrapper(regularFileWithContents: try Data(contentsOf: sourceURL))
            wrapper.preferredFilename = filename
            photoFiles[filename] = wrapper
        }

        let photosWrapper = FileWrapper(directoryWithFileWrappers: photoFiles)
        photosWrapper.preferredFilename = "Receipt Photos"
        rootFiles["Receipt Photos"] = photosWrapper

        let rootWrapper = FileWrapper(directoryWithFileWrappers: rootFiles)
        rootWrapper.preferredFilename = exportFilename
        return rootWrapper
    }

    private func exportPhotoFilename(for receipt: Receipt) -> String {
        guard receipt.asset?.kind == .image else {
            return ""
        }

        let date = compactDateFormatter.string(from: receipt.transactionDate ?? receipt.importedAt)
        let merchant = sanitizedFilenameComponent(receipt.displayMerchantName)
        let suffix = String(receipt.id.uuidString.prefix(8))

        // Images are always transcoded and stored as JPEG by ReceiptFileStorageService.
        // Derive the extension from the stored content type, not the original
        // filename, so the exported extension matches the actual file bytes.
        let fileExtension: String
        if let contentTypeIdentifier = receipt.asset?.contentTypeIdentifier,
           let storedType = UTType(contentTypeIdentifier),
           let preferredExtension = storedType.preferredFilenameExtension {
            fileExtension = preferredExtension
        } else {
            fileExtension = "jpg"
        }

        return "\(date)-\(merchant)-\(suffix).\(fileExtension)"
    }

    private static func csvEscapedField(_ value: String) -> String {
        let leading = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let isNumber = value.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil
        let safe = !isNumber && leading.map { "=+-@".contains($0) } == true ? "'" + value : value
        let escaped = safe.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }

        return escaped
    }

    private func uniqueFilename(_ filename: String, usedFilenames: inout Set<String>) -> String {
        guard !filename.isEmpty else {
            return filename
        }

        var candidate = filename
        var counter = 2
        let baseURL = URL(filePath: filename)
        let stem = baseURL.deletingPathExtension().lastPathComponent
        let fileExtension = baseURL.pathExtension

        while usedFilenames.contains(candidate) {
            candidate = "\(stem)-\(counter).\(fileExtension)"
            counter += 1
        }

        usedFilenames.insert(candidate)
        return candidate
    }

    private func sanitizedFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let cleaned = String(scalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")

        return cleaned.isEmpty ? "Receipt" : String(cleaned.prefix(48))
    }

    private var compactDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }

    private func clearReceiptData() {
        // Delete stored files first. If this fails, do not stage any SwiftData
        // deletions — leaving the context clean avoids data-loss on a later
        // autosave.
        do {
            try services.fileStorageService.removeAllStoredFiles()
        } catch {
            errorMessage = "未能刪除所有收據檔案：\(error.localizedDescription)。收據未被移除，請重試或重新開啟 app。"
            return
        }

        // Files are cleaned. Now stage and commit SwiftData deletions.
        for receipt in receipts {
            modelContext.delete(receipt)
        }

        do {
            try modelContext.save()
        } catch {
            errorMessage = "收據檔案已刪除，但移除紀錄時儲存失敗：\(error.localizedDescription)。請重新開啟 app 重新同步。"
            return
        }
    }

    private func transferPersonalReceipts() {
        do {
            transferredCount = try ReceiptBusinessTransfer.move(transferCandidates) {
                try modelContext.save()
            }
        } catch {
            errorMessage = "轉移未完成，記錄已保留原有用途。\n\(error.localizedDescription)"
        }
        transferCandidates = []
    }

    private var exportDateStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }
}

private struct AdvancedCloudAISettingsSection: View {
    @Environment(\.serviceContainer) private var services

    @AppStorage(AppPreferences.cloudReceiptEnhancementEnabledKey)
    private var cloudReceiptEnhancementEnabled = AppPreferences.cloudReceiptEnhancementEnabled

    @AppStorage(AppPreferences.cloudReceiptUploadConsentKey)
    private var cloudReceiptUploadConsentGranted = AppPreferences.cloudReceiptUploadConsentGranted

    @State private var isExpanded = false
    @State private var didLoadKeyState = false
    @State private var isManagingKey = false
    @State private var geminiAPIKey = ""
    @State private var hasSavedGeminiAPIKey = false
    @State private var isCheckingConnection = false
    @State private var connectionMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Label("API key", systemImage: hasSavedGeminiAPIKey ? "checkmark.circle.fill" : "exclamationmark.circle")
                        Spacer()
                        Text(hasSavedGeminiAPIKey ? "已儲存" : "未設定")
                            .foregroundStyle(hasSavedGeminiAPIKey ? Color.receiptAccentGreen : .secondary)
                    }

                    Toggle(isOn: $cloudReceiptEnhancementEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("新收據自動用 Gemini")
                            Text("掃描或匯入後自動抽取；現有收據可在收據頁重新處理。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!hasSavedGeminiAPIKey)
                    .onChange(of: cloudReceiptEnhancementEnabled) { _, isEnabled in
                        cloudReceiptUploadConsentGranted = isEnabled
                    }

                    Button(isCheckingConnection ? "正在測試…" : "測試 Gemini 連線") {
                        verifyGeminiConnection()
                    }
                    .disabled(!hasSavedGeminiAPIKey || isCheckingConnection)

                    if let connectionMessage {
                        Label(connectionMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.receiptAccentGreen)
                    }

                    if hasSavedGeminiAPIKey {
                        DisclosureGroup("管理 API key", isExpanded: $isManagingKey) {
                            keyEditor
                                .padding(.top, 8)
                        }
                    } else {
                        keyEditor
                    }
                }
                .padding(.top, 10)
            } label: {
                Label("Gemini 收據抽取", systemImage: "sparkles")
            }
        } footer: {
            Text("使用 Gemini 3.5 Flash-Lite。API key 只儲存在這部裝置的 Keychain。每次重新處理現有收據前，PocketPal 都會先詢問。")
        }
        .onChange(of: isExpanded) { _, expanded in
            guard expanded, !didLoadKeyState else { return }
            didLoadKeyState = true
            loadGeminiKeyState()
        }
        .alert("Cloud AI 設定錯誤", isPresented: Binding(
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
    }

    private var keyEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField(hasSavedGeminiAPIKey ? "輸入新的 Gemini API key" : "Gemini API key", text: $geminiAPIKey)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif

            HStack {
                Button(hasSavedGeminiAPIKey ? "更新 Key" : "儲存 API Key") {
                    saveGeminiAPIKey()
                }
                .disabled(geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                if hasSavedGeminiAPIKey {
                    Button("刪除 Key", role: .destructive) {
                        deleteGeminiAPIKey()
                    }
                } else {
                    Link("取得 API key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                }
            }
        }
    }

    private func verifyGeminiConnection() {
        Task {
            isCheckingConnection = true
            connectionMessage = nil
            defer { isCheckingConnection = false }
            do {
                try await GeminiReceiptExtractionService(keychainService: services.keychainService).verifyConfiguration()
                connectionMessage = "連線成功，可以開始抽取。"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadGeminiKeyState() {
        do {
            let savedKey = try services.keychainService.retrieveSecureString(key: AppPreferences.geminiAPIKeyKey)
            hasSavedGeminiAPIKey = savedKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            geminiAPIKey = ""
        } catch {
            hasSavedGeminiAPIKey = false
            errorMessage = error.localizedDescription
        }
    }

    private func saveGeminiAPIKey() {
        connectionMessage = nil
        let trimmedKey = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        do {
            try services.keychainService.storeSecureString(key: AppPreferences.geminiAPIKeyKey, value: trimmedKey)
            hasSavedGeminiAPIKey = true
            geminiAPIKey = ""
            isManagingKey = false
            connectionMessage = "API key 已儲存。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteGeminiAPIKey() {
        connectionMessage = nil
        do {
            try services.keychainService.delete(key: AppPreferences.geminiAPIKeyKey)
            hasSavedGeminiAPIKey = false
            geminiAPIKey = ""
            cloudReceiptEnhancementEnabled = false
            cloudReceiptUploadConsentGranted = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SettingsActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.receiptAccentBlue)
                .frame(width: 34, height: 34)
                .background(Color.receiptAccentBlue.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ReceiptCSVRow {
    static let header = [
        "ID",
        "Imported At",
        "Updated At",
        "Type",
        "Merchant",
        "Description",
        "Transaction Date",
        "Amount",
        "Currency",
        "Amount HKD",
        "Tax Amount",
        "Category",
        "Expense Type",
        "Tax Category",
        "Review Status",
        "Import Source",
        "Processing State",
        "Notes",
        "Receipt Photo Filename"
    ]

    let fields: [String]

    init(receipt: Receipt, photoFilename: String) {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

        fields = [
            receipt.id.uuidString,
            dateFormatter.string(from: receipt.importedAt),
            dateFormatter.string(from: receipt.updatedAt),
            receipt.transactionKind.displayName,
            receipt.merchantName ?? "",
            receipt.itemDescription ?? "",
            receipt.transactionDate.map { dateFormatter.string(from: $0) } ?? "",
            NumberFormatter.csvAmount.string(from: NSNumber(value: receipt.totalAmount ?? 0)).flatMap { receipt.totalAmount == nil ? "" : $0 } ?? "",
            receipt.currencyCode ?? receipt.resolvedCurrency.rawValue,
            NumberFormatter.csvAmount.string(from: NSNumber(value: receipt.amountInHKD ?? 0)).flatMap { receipt.amountInHKD == nil ? "" : $0 } ?? "",
            NumberFormatter.csvAmount.string(from: NSNumber(value: receipt.taxAmount ?? 0)).flatMap { receipt.taxAmount == nil ? "" : $0 } ?? "",
            receipt.category ?? "",
            receipt.expenseType.displayName,
            receipt.taxCategory?.displayName ?? "",
            receipt.reviewStatus.rawValue,
            receipt.importSource.rawValue,
            receipt.processingState.rawValue,
            receipt.notes ?? "",
            photoFilename
        ]
    }
}

private extension NumberFormatter {
    static var csvAmount: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter
    }
}

private struct PocketPalExportDocument: FileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .folder] }

    let contentType: UTType
    private let data: Data?
    private let wrapper: FileWrapper?

    init(data: Data, contentType: UTType) {
        self.contentType = contentType
        self.data = data
        self.wrapper = nil
    }

    init(fileWrapper: FileWrapper, contentType: UTType) {
        self.contentType = contentType
        self.data = nil
        self.wrapper = fileWrapper
    }

    init(configuration: ReadConfiguration) throws {
        self.contentType = configuration.contentType
        self.data = configuration.file.regularFileContents
        self.wrapper = configuration.file
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let wrapper {
            return wrapper
        }

        return FileWrapper(regularFileWithContents: data ?? Data())
    }
}

private struct SettingsExportPayload: Codable {
    struct Defaults: Codable {
        let currencyCode: String
        let expenseTypeRawValue: String
        let taxYearStartMonth: Int
        let ocrLanguages: [String]
    }

    let exportedAt: Date
    let defaults: Defaults
    let receipts: [ReceiptExport]
}

private struct ReceiptExport: Codable {
    let id: UUID
    let importedAt: Date
    let updatedAt: Date
    let merchantName: String?
    let transactionKind: String
    let itemDescription: String?
    let transactionDate: Date?
    let totalAmount: Double?
    let currencyCode: String?
    let taxAmount: Double?
    let category: String?
    let notes: String?
    let reviewStatus: String
    let importSource: String
    let processingState: String
    let expenseType: String

    init(_ receipt: Receipt) {
        id = receipt.id
        importedAt = receipt.importedAt
        updatedAt = receipt.updatedAt
        merchantName = receipt.merchantName
        transactionKind = receipt.transactionKind.rawValue
        itemDescription = receipt.itemDescription
        transactionDate = receipt.transactionDate
        totalAmount = receipt.totalAmount
        currencyCode = receipt.currencyCode
        taxAmount = receipt.taxAmount
        category = receipt.category
        notes = receipt.notes
        reviewStatus = receipt.reviewStatus.rawValue
        importSource = receipt.importSource.rawValue
        processingState = receipt.processingState.rawValue
        expenseType = receipt.expenseType.rawValue
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewSampleData.makeContainer())
        .environment(\.serviceContainer, ServiceContainer())
}
