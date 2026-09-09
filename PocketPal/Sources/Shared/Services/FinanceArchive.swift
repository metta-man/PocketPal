import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

struct FinanceReceiptSnapshot: Codable {
    var id: UUID
    var importedAt: Date
    var updatedAt: Date
    var reviewedAt: Date?
    var reviewStatusRawValue: String
    var importSourceRawValue: String
    var financeMetadataJSON: String?
    var transactionKindRawValue: String?
    var processingStateRawValue: String
    var processingErrorMessage: String?
    var merchantName: String?
    var itemDescription: String?
    var transactionDate: Date?
    var totalAmount: Double?
    var currencyCode: String?
    var taxAmount: Double?
    var category: String?
    var notes: String?
    var extractionConfidence: Double?
    var extractionProviderRawValue: String?
    var extractionDecisionRawValue: String?
    var cloudExtractionAttemptedAt: Date?
    var cloudExtractionErrorMessage: String?
    var searchText: String
    var expenseTypeRawValue: String
    var taxCategoryRawValue: String?
    var sourceProviderRawValue: String?
    var sourceOrderID: String?
    var sourceEmailID: String?
    init(_ receipt: Receipt) {
        id = receipt.id
        importedAt = receipt.importedAt
        updatedAt = receipt.updatedAt
        reviewedAt = receipt.reviewedAt
        reviewStatusRawValue = receipt.reviewStatusRawValue
        importSourceRawValue = receipt.importSourceRawValue
        financeMetadataJSON = receipt.financeMetadataJSON
        transactionKindRawValue = receipt.transactionKindRawValue
        processingStateRawValue = receipt.processingStateRawValue
        processingErrorMessage = receipt.processingErrorMessage
        merchantName = receipt.merchantName
        itemDescription = receipt.itemDescription
        transactionDate = receipt.transactionDate
        totalAmount = receipt.totalAmount
        currencyCode = receipt.currencyCode
        taxAmount = receipt.taxAmount
        category = receipt.category
        notes = receipt.notes
        extractionConfidence = receipt.extractionConfidence
        extractionProviderRawValue = receipt.extractionProviderRawValue
        extractionDecisionRawValue = receipt.extractionDecisionRawValue
        cloudExtractionAttemptedAt = receipt.cloudExtractionAttemptedAt
        cloudExtractionErrorMessage = receipt.cloudExtractionErrorMessage
        searchText = receipt.searchText
        expenseTypeRawValue = receipt.expenseTypeRawValue
        taxCategoryRawValue = receipt.taxCategoryRawValue
        sourceProviderRawValue = receipt.sourceProviderRawValue
        sourceOrderID = receipt.sourceOrderID
        sourceEmailID = receipt.sourceEmailID
    }
    func apply(to receipt: Receipt) {
        receipt.id = id
        receipt.importedAt = importedAt
        receipt.updatedAt = updatedAt
        receipt.reviewedAt = reviewedAt
        receipt.reviewStatusRawValue = reviewStatusRawValue
        receipt.importSourceRawValue = importSourceRawValue
        receipt.financeMetadataJSON = financeMetadataJSON
        receipt.transactionKindRawValue = transactionKindRawValue
        receipt.processingStateRawValue = processingStateRawValue
        receipt.processingErrorMessage = processingErrorMessage
        receipt.merchantName = merchantName
        receipt.itemDescription = itemDescription
        receipt.transactionDate = transactionDate
        receipt.totalAmount = totalAmount
        receipt.currencyCode = currencyCode
        receipt.taxAmount = taxAmount
        receipt.category = category
        receipt.notes = notes
        receipt.extractionConfidence = extractionConfidence
        receipt.extractionProviderRawValue = extractionProviderRawValue
        receipt.extractionDecisionRawValue = extractionDecisionRawValue
        receipt.cloudExtractionAttemptedAt = cloudExtractionAttemptedAt
        receipt.cloudExtractionErrorMessage = cloudExtractionErrorMessage
        receipt.searchText = searchText
        receipt.expenseTypeRawValue = expenseTypeRawValue
        receipt.taxCategoryRawValue = taxCategoryRawValue
        receipt.sourceProviderRawValue = sourceProviderRawValue
        receipt.sourceOrderID = sourceOrderID
        receipt.sourceEmailID = sourceEmailID
    }
}
struct FinanceBackupEvidence: Codable {
    var metadata: FinanceEvidence
    var bytes: Data
    var checksum: String
}
struct FinanceBackupRow: Codable {
    var receipt: FinanceReceiptSnapshot
    var evidence: [FinanceBackupEvidence]
    var ocrText: String?
    var ocrConfidence: Double?
    var ocrID: UUID?
    var ocrCreated: Date?
}
struct FinanceBackup: Codable {
    var version = 1
    var exportedAt = Date.now
    var rows: [FinanceBackupRow]
}
@MainActor
enum FinanceArchive {
    static func encode(_ records: [Receipt], storage: ReceiptFileStorageServicing) throws -> Data {
        let rows = try records.map { receipt in
            FinanceBackupRow(receipt: FinanceReceiptSnapshot(receipt), evidence: try receipt.allEvidence.map { file in
                let bytes = try Data(contentsOf: storage.fileURL(forRelativePath: file.path))
                return FinanceBackupEvidence(metadata: file, bytes: bytes, checksum: digest(bytes))
            }, ocrText: receipt.ocrResult?.rawText, ocrConfidence: receipt.ocrResult?.confidence,
               ocrID: receipt.ocrResult?.id, ocrCreated: receipt.ocrResult?.createdAt)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(FinanceBackup(rows: rows))
        guard encoded.count <= 250_000_000 else { throw FinanceWorkflowError.invalid("備份超過 250 MB，請選擇較短期間分批備份。") }
        return encoded
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func decode(_ data: Data) throws -> FinanceBackup {
        guard data.count <= 250_000_000 else { throw FinanceWorkflowError.invalid("此備份超過 250 MB，請分批匯出。") }
        let backup = try JSONDecoder().decode(FinanceBackup.self, from: data)
        guard backup.version == 1, Set(backup.rows.map { $0.receipt.id }).count == backup.rows.count else {
            throw FinanceWorkflowError.invalid("備份版本不支援或含重複 ID。")
        }
        for row in backup.rows {
            if let json = row.receipt.financeMetadataJSON {
                let metadata = try JSONDecoder().decode(FinanceMetadata.self, from: Data(json.utf8))
                guard metadata.payments.allSatisfy({ $0.amount > 0 }), Set(metadata.payments.map(\.id)).count == metadata.payments.count else {
                    throw FinanceWorkflowError.invalid("付款資料不完整。")
                }
            }
            for file in row.evidence {
                guard digest(file.bytes) == file.checksum, let type = UTType(file.metadata.type), type.conforms(to: .image) || type.conforms(to: .pdf) else {
                    throw FinanceWorkflowError.invalid("附件校驗失敗或格式不支援，沒有匯入資料。")
                }
            }
        }
        return backup
    }
    /// Add-only restore is idempotent. Existing IDs are reported, never overwritten.
    static func restore(_ backup: FinanceBackup, existing: [Receipt], context: ModelContext,
                        storage: ReceiptFileStorageServicing, asSubmission: Bool) throws -> Int {
        _ = try decode(JSONEncoder().encode(backup))
        let known = Set(existing.map(\.id))
        var inserted: [Receipt] = []
        var files: [URL] = []
        do {
            for row in backup.rows where !known.contains(row.receipt.id) {
                let receipt = Receipt(id: row.receipt.id, importSource: .files)
                row.receipt.apply(to: receipt)
                var metadata = receipt.finance
                metadata.evidence = []
                for (index, file) in row.evidence.enumerated() {
                    let type = UTType(file.metadata.type)!
                    // Never use an imported path as a filesystem destination.
                    let relative = UUID().uuidString + "/original." + (type.preferredFilenameExtension ?? "bin")
                    let destination = storage.fileURL(forRelativePath: relative)
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try file.bytes.write(to: destination, options: .atomic)
                    files.append(destination)
                    if index == 0 {
                        receipt.asset = ReceiptAsset(id: file.metadata.id, receiptID: receipt.id, kind: type.conforms(to: .pdf) ? .pdf : .image,
                            originalFilename: file.metadata.name, contentTypeIdentifier: file.metadata.type,
                            fileSizeBytes: Int64(file.bytes.count), storageRelativePath: relative)
                    } else {
                        metadata.evidence.append(FinanceEvidence(id: file.metadata.id, name: file.metadata.name, path: relative, type: file.metadata.type))
                    }
                }
                if let text = row.ocrText {
                    receipt.ocrResult = OCRResult(id: row.ocrID ?? UUID(), createdAt: row.ocrCreated ?? .now, rawText: text, confidence: row.ocrConfidence)
                }
                if asSubmission {
                    metadata.approval = "待審批"
                    receipt.reviewStatus = .inbox; receipt.reviewedAt = nil
                }
                metadata.audit.append(FinanceAudit(actor: "本機", action: asSubmission ? "匯入員工提交，等待核對" : "由備份還原"))
                receipt.finance = metadata
                context.insert(receipt); inserted.append(receipt)
            }
            try context.save()
            return inserted.count
        } catch {
            for receipt in inserted { context.delete(receipt) }
            for url in files { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }
}
struct FinanceFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct FinanceArchiveView: View {
    let ledger: ReceiptLedger
    @Environment(\.modelContext) private var context
    @Environment(\.serviceContainer) private var services
    @Query private var receipts: [Receipt]
    @State private var allSpaces = false
    @State private var submissionsOnly = false
    @State private var limitDates = false
    @State private var start = Date.distantPast
    @State private var end = Date.now
    @State private var document: FinanceFileDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var backup: FinanceBackup?
    @State private var asSubmission = true
    @State private var message: String?
    @State private var confirm = false
    private var selected: [Receipt] {
        receipts.filter {
            (allSpaces || ($0.expenseType == .personal) == (ledger == .personal)) &&
            (!submissionsOnly || $0.finance.approval == "待審批") &&
            (!limitDates || ReceiptDeliveryPackage.calendar.startOfDay(for: $0.importedAt) >= ReceiptDeliveryPackage.calendar.startOfDay(for: start) && ReceiptDeliveryPackage.calendar.startOfDay(for: $0.importedAt) <= ReceiptDeliveryPackage.calendar.startOfDay(for: end))
        }
    }
    var body: some View {
        Form {
            Section("完整備份／交接檔") {
                Toggle("包含個人及業務兩個空間", isOn: $allSpaces)
                Toggle("只匯出待審批提交", isOn: $submissionsOnly)
                Toggle("按新增日期分批", isOn: $limitDates)
                if limitDates {
                    DatePicker("新增日期由", selection: $start, displayedComponents: .date)
                    DatePicker("至", selection: $end, displayedComponents: .date)
                    Text("分批以新增日期篩選；每個檔案上限 250 MB。") .font(.caption)
                }
                Text("將匯出 \(selected.count) 筆，連同全部附件、OCR、付款、定期設定及修改紀錄。任何原檔無法讀取時會停止備份。")
                Text("此檔案包含財務及個人資料，請選擇合適的儲存或分享位置。獨立會計模組請先從匯入頁整合所需紀錄。") .font(.caption)
                Button("建立備份／交接檔") {
                    do {
                        document = FinanceFileDocument(data: try FinanceArchive.encode(selected, storage: services.fileStorageService))
                        exporting = true
                    } catch { message = error.localizedDescription }
                }.disabled(selected.isEmpty)
            }
            Section("還原／收取員工提交") {
                Toggle("作為員工提交（需重新核對）", isOn: $asSubmission)
                Button("選擇 PocketPal 備份檔") { importing = true }
                if let backup {
                    Text("共 \(backup.rows.count) 筆；新增 \(newCount) 筆；已有 ID 的 \(backup.rows.count - newCount) 筆保留現有版本。")
                    Text("有相同 ID 的紀錄不會被覆蓋。交接檔的姓名及批准狀態不作身份驗證。") .font(.caption)
                    Button("確認匯入 \(newCount) 筆") { confirm = true }.disabled(newCount == 0)
                }
            }
        }
        .formStyle(.grouped)
            .navigationTitle("備份及交接")
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "PocketPal-Full-Backup") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 250_000_000 else { throw FinanceWorkflowError.invalid("檔案太大，請分批匯入。") }
                backup = try FinanceArchive.decode(Data(contentsOf: url))
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("匯入 \(newCount) 筆紀錄？", isPresented: $confirm, titleVisibility: .visible) {
            Button("確認匯入") {
                guard let backup else { return }
                do {
                    let count = try FinanceArchive.restore(backup, existing: receipts, context: context, storage: services.fileStorageService, asSubmission: asSubmission)
                    self.backup = nil; message = "已匯入 \(count) 筆。"
                } catch { message = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("資料交接", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("好", role: .cancel) {} } message: { Text(message ?? "") }
    }
    private var newCount: Int { backup?.rows.filter { row in !receipts.contains { $0.id == row.receipt.id } }.count ?? 0 }
}
