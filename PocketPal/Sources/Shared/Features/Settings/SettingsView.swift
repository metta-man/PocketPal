import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.serviceContainer) private var services

    @Query(sort: [SortDescriptor(\Receipt.importedAt, order: .reverse)])
    private var receipts: [Receipt]

    @Query(sort: [SortDescriptor(\Connection.createdAt, order: .reverse)])
    private var connections: [Connection]

    @AppStorage(OCRPreferences.selectedLanguageCodesKey)
    private var storedLanguageCodes = OCRPreferences.defaultLanguageCodes.joined(separator: ",")

    @AppStorage(AppPreferences.defaultCurrencyCodeKey)
    private var defaultCurrencyCode = AppPreferences.defaultCurrency.rawValue

    @AppStorage(AppPreferences.defaultExpenseTypeKey)
    private var defaultExpenseTypeRawValue = AppPreferences.defaultExpenseType.rawValue

    @AppStorage(AppPreferences.taxYearStartMonthKey)
    private var taxYearStartMonth = AppPreferences.taxYearStartMonth

    @State private var exportDocument: PocketPalExportDocument?
    @State private var isShowingExporter = false
    @State private var exportFilename = "PocketPal-Export.json"
    @State private var clearAllConfirmation = false
    @State private var errorMessage: String?

    private var selectedLanguageCodes: [String] {
        OCRPreferences.selectedRecognitionLanguages()
    }

    private var monthSymbols: [String] {
        Calendar.current.monthSymbols
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Defaults") {
                    Picker("Default Currency", selection: $defaultCurrencyCode) {
                        ForEach(Currency.allCases) { currency in
                            Text("\(currency.flag) \(currency.displayName)").tag(currency.rawValue)
                        }
                    }

                    Picker("Expense Type", selection: $defaultExpenseTypeRawValue) {
                        ForEach(ExpenseType.allCases, id: \.self) { expenseType in
                            Label(expenseType.displayName, systemImage: expenseType.systemImage)
                                .tag(expenseType.rawValue)
                        }
                    }
                }

                Section("Tax Year") {
                    Picker("Start Month", selection: $taxYearStartMonth) {
                        ForEach(Array(monthSymbols.enumerated()), id: \.offset) { index, month in
                            Text(month).tag(index + 1)
                        }
                    }

                    Text(AppPreferences.taxYearDescription())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("OCR Languages") {
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
                } footer: {
                    Text("PocketPal uses these languages on the next OCR run. For Hong Kong receipts, Traditional Chinese and English usually work best together.")
                }

                Section("Data Management") {
                    Button("Export All Data") {
                        prepareExport()
                    }

                    Button("Clear All Data", role: .destructive) {
                        clearAllConfirmation = true
                    }
                } footer: {
                    Text("\(receipts.count) receipts and \(connections.count) connected accounts stored locally.")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: appBuild)
                    Text("PocketPal helps Hong Kong users capture receipts, track expenses, and prepare records for tax and reimbursement workflows.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Color.receiptGroupedBackground)
            .toolbarBackground(Color.receiptGroupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.receiptGroupedBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            #endif
        }
        .fileExporter(
            isPresented: $isShowingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Clear All Data?", isPresented: $clearAllConfirmation) {
            Button("Clear", role: .destructive) {
                clearAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes all receipts, connections, and stored receipt files.")
        }
        .alert("Settings Error", isPresented: Binding(
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

    private func prepareExport() {
        do {
            let payload = SettingsExportPayload(
                exportedAt: .now,
                defaults: .init(
                    currencyCode: defaultCurrencyCode,
                    expenseTypeRawValue: defaultExpenseTypeRawValue,
                    taxYearStartMonth: taxYearStartMonth,
                    ocrLanguages: selectedLanguageCodes
                ),
                receipts: receipts.map(ReceiptExport.init),
                connections: connections.map(ConnectionExport.init)
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            exportDocument = PocketPalExportDocument(data: try encoder.encode(payload))
            exportFilename = "PocketPal-Export-\(exportDateStamp).json"
            isShowingExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearAllData() {
        do {
            for receipt in receipts {
                modelContext.delete(receipt)
            }

            for connection in connections {
                modelContext.delete(connection)
            }

            try services.fileStorageService.removeAllStoredFiles()
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var exportDateStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }
}

private struct PocketPalExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
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
    let connections: [ConnectionExport]
}

private struct ReceiptExport: Codable {
    let id: UUID
    let importedAt: Date
    let updatedAt: Date
    let merchantName: String?
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

private struct ConnectionExport: Codable {
    let id: UUID
    let provider: String
    let createdAt: Date
    let lastSyncAt: Date?
    let syncEnabled: Bool
    let syncIntervalSeconds: Int
    let lastError: String?
    let lastSyncStatus: String

    init(_ connection: Connection) {
        id = connection.id
        provider = connection.provider.rawValue
        createdAt = connection.createdAt
        lastSyncAt = connection.lastSyncAt
        syncEnabled = connection.syncEnabled
        syncIntervalSeconds = connection.syncIntervalSeconds
        lastError = connection.lastError
        lastSyncStatus = connection.lastSyncStatus.rawValue
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewSampleData.makeContainer())
        .environment(\.serviceContainer, ServiceContainer())
}
