#if os(macOS)
import AppKit
import Foundation
import SwiftData
import SwiftUI
import XCTest
@testable import PocketPal

@MainActor
final class MacCoreSettingsInfrastructureTests: XCTestCase {
    func testDeliveryPeriodUsesHongKongDaysAndExplicitUndatedSelection() throws {
        let calendar = ReceiptDeliveryPackage.calendar
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        let first = Receipt(importSource: .manual, transactionDate: start)
        let last = Receipt(importSource: .manual, transactionDate: nextDay.addingTimeInterval(-1))
        let outside = Receipt(importSource: .manual, transactionDate: nextDay)
        let undated = Receipt(importSource: .manual)
        let business = Receipt(importSource: .manual, transactionDate: start, expenseType: .business)
        let records = [first, last, outside, undated, business]
        let selected = ReceiptDeliveryPackage.select(records, ledger: .personal, start: start, end: start,
                                                    includeUndated: false, confirmedOnly: false)
        XCTAssertEqual(Set(selected.map(\.id)), Set([first.id, last.id]))
        XCTAssertEqual(ReceiptDeliveryPackage.select(records, ledger: .personal, start: start, end: start,
                                                     includeUndated: true, confirmedOnly: false).count, 3)
        XCTAssertTrue(ReceiptDeliveryPackage.select(records, ledger: .personal, start: start, end: start,
                                                    includeUndated: true, confirmedOnly: true).isEmpty)
    }

    func testDeliveryPreservesPDFAndImagesAndReportsMissingEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pdf = Data("%PDF-1.7 test evidence".utf8)
        let jpg = Data([0xff, 0xd8, 0xff, 0xd9])
        try pdf.write(to: directory.appendingPathComponent("sample.pdf"))
        try jpg.write(to: directory.appendingPathComponent("sample.jpg"))
        let income = Receipt(importSource: .manual, transactionKind: .income, merchantName: "=SUM(1,2)",
                             transactionDate: .now, totalAmount: 100, currencyCode: "HKD")
        income.asset = ReceiptAsset(receiptID: income.id, kind: .pdf, originalFilename: "sample.pdf",
                                    contentTypeIdentifier: "com.adobe.pdf", fileSizeBytes: Int64(pdf.count), storageRelativePath: "sample.pdf")
        let expense = Receipt(importSource: .files, totalAmount: 30, currencyCode: "HKD")
        expense.asset = ReceiptAsset(receiptID: expense.id, kind: .image, originalFilename: "sample.jpg",
                                     contentTypeIdentifier: "public.jpeg", fileSizeBytes: Int64(jpg.count), storageRelativePath: "sample.jpg")
        let missing = Receipt(importSource: .files)
        missing.asset = ReceiptAsset(receiptID: missing.id, kind: .pdf, originalFilename: "gone.pdf",
                                     contentTypeIdentifier: "com.adobe.pdf", fileSizeBytes: 1, storageRelativePath: "gone.pdf")
        let wrapper = try ReceiptDeliveryPackage.make(receipts: [income, expense, missing], scope: "Test", excludedCount: 2) {
            directory.appendingPathComponent($0)
        }
        let files = try XCTUnwrap(wrapper.fileWrappers)
        let attachments = try XCTUnwrap(files["Attachments"]?.fileWrappers)
        XCTAssertEqual(attachments[income.id.uuidString + ".pdf"]?.regularFileContents, pdf)
        XCTAssertEqual(attachments[expense.id.uuidString + ".jpg"]?.regularFileContents, jpg)
        XCTAssertEqual(attachments.count, 2)
        let csv = String(decoding: try XCTUnwrap(files["receipts.csv"]?.regularFileContents), as: UTF8.self)
        XCTAssertTrue(csv.contains("'=SUM(1,2)"))
        XCTAssertTrue(csv.contains("Attachments/" + income.id.uuidString + ".pdf"))
        let issues = String(decoding: try XCTUnwrap(files["missing-items.csv"]?.regularFileContents), as: UTF8.self)
        XCTAssertTrue(issues.contains("原始附件無法讀取"))
        XCTAssertTrue(issues.contains("欠有效金額"))
        let summary = String(decoding: try XCTUnwrap(files["README.txt"]?.regularFileContents), as: UTF8.self)
        XCTAssertTrue(summary.contains("淨收支 70"))
        XCTAssertNil(missing.totalAmount)
        XCTAssertEqual(income.reviewStatus, .inbox)
    }

    func testFinanceCSVRetainsNumericRefundsWithoutExecutingFormulas() {
        let csv = String(decoding: ReceiptDeliveryPackage.csv([["-12.50", "=SUM(1,2)", "+1+2"]]), as: UTF8.self)
        XCTAssertTrue(csv.contains("\"-12.50\""))
        XCTAssertTrue(csv.contains("'=SUM(1,2)"))
        XCTAssertTrue(csv.contains("'+1+2"))
    }

    func testFinanceScreensRenderWithUnpaidPayrollAndRecurringRecords() throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = container.mainContext
        let receipt = Receipt(importSource: .manual, processingState: .ready, merchantName: "陳小姐 · 9 月人工", transactionDate: .now, totalAmount: 22000, currencyCode: "HKD", category: "人工及僱主成本", expenseType: .business)
        var metadata = FinanceMetadata(); metadata.tracksPayments = true; metadata.dueDate = .now.addingTimeInterval(-86400)
        metadata.project = "九龍店"; metadata.payroll = FinancePayroll(employee: "陳小姐", month: "2026-09", gross: 21000, employerCost: 1000, deductions: 1000)
        metadata.payments = [.init(date: .now, amount: 10000, reference: "首次付款")]
        receipt.finance = metadata; context.insert(receipt); try context.save()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PocketPalFinanceSnapshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("Finance snapshots: " + directory.path)

        func render<V: View>(_ view: V, name: String) throws {
            let host = NSHostingView(rootView: view.modelContainer(container).environment(\.serviceContainer, ServiceContainer()).environment(\.colorScheme, .light).background(Color.white))
            host.frame = NSRect(x: 0, y: 0, width: 1000, height: 850)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host; window.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name))
            XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
            window.orderOut(nil)
        }
        try render(FinanceWorkspaceView(ledger: .business), name: "finance-workspace-mac.png")
        try render(NavigationStack { FinanceRecordView(receipt: receipt) }, name: "finance-record-mac.png")
        try render(FinanceCreateView(ledger: .business), name: "finance-create-mac.png")
    }

    func testFinanceCashTreatmentAndPartialPaymentValidation() throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        let receipt = Receipt(importSource: .manual, transactionKind: .income, totalAmount: 100, currencyCode: "HKD")
        receipt.finance = FinanceMetadata(tracksPayments: true, approval: "已批准")
        context.insert(receipt); try context.save()
        XCTAssertEqual(receipt.cashIncome, 0)
        try FinanceWorkflow.pay(receipt, amount: Decimal(string: "30.1")!, date: .now, reference: "FPS", actor: "Tester", context: context)
        XCTAssertEqual(receipt.finance.approval, "待審批")
        XCTAssertEqual(receipt.outstanding, Decimal(string: "69.9"))
        XCTAssertEqual(receipt.cashIncome, Decimal(string: "30.1"))
        XCTAssertThrowsError(try FinanceWorkflow.pay(receipt, amount: 70, date: .now, reference: "", actor: "Tester", context: context))
        XCTAssertEqual(receipt.finance.payments.count, 1)
        var metadata = receipt.finance; metadata.treatment = .transfer; receipt.finance = metadata
        XCTAssertEqual(receipt.cashIncome, 0)
        metadata.treatment = .expenseRefund; receipt.finance = metadata
        XCTAssertEqual(receipt.cashIncome, 0)
        XCTAssertEqual(receipt.cashExpense, -Decimal(string: "30.1")!)
        XCTAssertFalse(receipt.taxReadiness.isReadyForTaxExport)
    }

    func testFinanceRecurringMonthEndAndIdempotency() throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        let calendar = ReceiptDeliveryPackage.calendar
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let march = calendar.date(from: DateComponents(year: 2026, month: 3, day: 31))!
        let template = Receipt(importSource: .manual, merchantName: "租金", totalAmount: 100)
        var metadata = FinanceMetadata(); metadata.isTemplate = true; metadata.nextDue = january
        metadata.recurrence = "每月"; metadata.anchorDay = 31; template.finance = metadata
        context.insert(template); try context.save()
        XCTAssertFalse(ReceiptLedger.personal.includes(template))
        XCTAssertEqual(FinanceWorkflow.occurrences(template, through: march).map { calendar.component(.day, from: $0) }, [31, 28, 31])
        XCTAssertEqual(try FinanceWorkflow.generate([template], records: [template], through: march, context: context), 3)
        let all = try context.fetch(FetchDescriptor<Receipt>())
        XCTAssertEqual(all.count, 4)
        XCTAssertEqual(all.filter { !$0.finance.isTemplate }.reduce(Decimal.zero) { $0 + $1.cashExpense }, 0)
        XCTAssertEqual(try FinanceWorkflow.generate([template], records: all, through: march, context: context), 0)
    }

    func testFinanceExportUsesPaymentMonthAndIncludesMultipleEvidence() throws {
        let calendar = ReceiptDeliveryPackage.calendar
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let february = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10))!
        let receipt = Receipt(importSource: .manual, transactionKind: .income, transactionDate: january, totalAmount: 100, currencyCode: "HKD")
        var metadata = FinanceMetadata(); metadata.tracksPayments = true
        metadata.payments = [.init(date: january, amount: 25, reference: "訂金"), .init(date: february, amount: 75, reference: "尾數")]
        receipt.finance = metadata
        XCTAssertEqual(ReceiptDeliveryPackage.select([receipt], ledger: .personal, start: february, end: february, includeUndated: false, confirmedOnly: false).count, 1)
        let wrapper = try ReceiptDeliveryPackage.make(receipts: [receipt], scope: "February", excludedCount: 0, start: february, end: february) { _ in URL(filePath: "/missing") }
        let summary = String(decoding: wrapper.fileWrappers!["monthly-summary.csv"]!.regularFileContents!, as: UTF8.self)
        XCTAssertTrue(summary.contains("2026-02")); XCTAssertTrue(summary.contains("75")); XCTAssertFalse(summary.contains("2026-01"))
    }

    func testFinanceArchiveRoundTripPreservesMetadataFilesAndIsIdempotent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FinanceTestStorage(root: directory)
        let bytes = Data("%PDF-1.7 evidence".utf8)
        try bytes.write(to: directory.appendingPathComponent("one.pdf"))
        try bytes.write(to: directory.appendingPathComponent("two.pdf"))
        let source = Receipt(importSource: .files, merchantName: "Client", totalAmount: 100, currencyCode: "HKD", notes: "Keep all", sourceOrderID: "Order-42")
        source.asset = ReceiptAsset(receiptID: source.id, kind: .pdf, originalFilename: "one.pdf", contentTypeIdentifier: "com.adobe.pdf", fileSizeBytes: Int64(bytes.count), storageRelativePath: "one.pdf")
        source.ocrResult = OCRResult(rawText: "Original OCR", confidence: 0.75)
        var metadata = FinanceMetadata(); metadata.client = "Customer"; metadata.project = "Project"; metadata.tracksPayments = true
        metadata.payments = [.init(date: .now, amount: 40, reference: "FPS")]
        metadata.evidence = [.init(name: "two.pdf", path: "two.pdf", type: "com.adobe.pdf")]
        source.finance = metadata
        let data = try FinanceArchive.encode([source], storage: storage)
        let backup = try FinanceArchive.decode(data)
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        XCTAssertEqual(try FinanceArchive.restore(backup, existing: [], context: context, storage: storage, asSubmission: true), 1)
        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<Receipt>()).first)
        XCTAssertEqual(restored.id, source.id)
        XCTAssertEqual(restored.sourceOrderID, "Order-42")
        XCTAssertEqual(restored.finance.project, "Project")
        XCTAssertEqual(restored.outstanding, 60)
        XCTAssertEqual(restored.finance.approval, "待審批")
        XCTAssertEqual(restored.ocrResult?.rawText, "Original OCR")
        XCTAssertEqual(restored.allEvidence.count, 2)
        for file in restored.allEvidence { XCTAssertEqual(try Data(contentsOf: storage.fileURL(forRelativePath: file.path)), bytes) }
        XCTAssertEqual(try FinanceArchive.restore(backup, existing: [restored], context: context, storage: storage, asSubmission: false), 0)
        var corrupt = backup; corrupt.rows[0].evidence[0].bytes = Data("tampered".utf8)
        XCTAssertThrowsError(try FinanceArchive.restore(corrupt, existing: [], context: context, storage: storage, asSubmission: false))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Receipt>()), 1)
    }

    func testFinanceReviewCannotReduceBelowPaymentsAndRestoresAuditOnFailure() throws {
        enum Failure: Error { case save }
        let receipt = Receipt(importSource: .manual, totalAmount: 100, currencyCode: "HKD")
        var metadata = FinanceMetadata(); metadata.tracksPayments = true; metadata.payments = [.init(date: .now, amount: 70, reference: "")]
        receipt.finance = metadata
        let before = receipt.financeMetadataJSON
        var values = ReceiptReviewValues(receipt: receipt); values.totalAmount = 60
        XCTAssertThrowsError(try ReceiptReviewPersistence.save(receipt: receipt, values: values, confirmed: false) {})
        XCTAssertEqual(receipt.totalAmount, 100)
        values.totalAmount = 120
        XCTAssertThrowsError(try ReceiptReviewPersistence.save(receipt: receipt, values: values, confirmed: false) { throw Failure.save })
        XCTAssertEqual(receipt.totalAmount, 100); XCTAssertEqual(receipt.financeMetadataJSON, before)
    }

    func testLegacyInvoiceImportPreservesActualPaymentDateAndNotes() throws {
        let container = try PocketPalModelContainer.makeExperiments(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let issued = Date(timeIntervalSince1970: 1700000000)
        let paid = issued.addingTimeInterval(86400 * 40)
        let invoice = InvoiceRecord(invoiceNumber: "INV-1", clientName: "Client", issueDate: issued, amountHKD: 125, status: .paid, paidAt: paid, notes: "Keep original notes")
        context.insert(invoice); try context.save()
        let draft = try XCTUnwrap(FinanceImporter.legacy(context: context).first)
        XCTAssertEqual(draft.notes, "Keep original notes")
        XCTAssertTrue(draft.metadata.tracksPayments)
        XCTAssertEqual(draft.metadata.payments.first?.date, paid)
        XCTAssertEqual(draft.metadata.payments.first?.amount, 125)
        XCTAssertEqual(invoice.notes, "Keep original notes")
    }

    func testFinanceImportPreservesDuplicateMultiplicityAndSourceIdempotency() throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        let drafts = (0..<2).map { FinanceImportDraft(key: "bank:same:\($0)", name: "Shop", date: .now, amount: 10, kind: .expense, category: "", metadata: FinanceMetadata()) }
        XCTAssertEqual(try FinanceImporter.insert(drafts, existing: [], ledger: .business, context: context), 2)
        let all = try context.fetch(FetchDescriptor<Receipt>())
        XCTAssertEqual(try FinanceImporter.insert(drafts, existing: all, ledger: .business, context: context), 0)
        XCTAssertEqual(FinanceWorkflow.duplicates(of: all[0], in: all).count, 1)
    }

    func testBusinessTransferPersistsSameRecordsAndPreservesAssets() throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        let personal = Receipt(reviewStatus: .reviewed, importSource: .photos,
                               totalAmount: 123, notes: "Keep this note")
        personal.reviewedAt = .now
        let asset = ReceiptAsset(receiptID: personal.id, kind: .image,
                                 originalFilename: "receipt.jpg", contentTypeIdentifier: "public.jpeg",
                                 fileSizeBytes: 42, storageRelativePath: "receipts/original.jpg")
        personal.asset = asset
        let income = Receipt(importSource: .manual, transactionKind: .income)
        let business = Receipt(reviewStatus: .reviewed, importSource: .files, expenseType: .business)
        let reimbursable = Receipt(importSource: .files, expenseType: .reimbursable)
        for receipt in [personal, income, business, reimbursable] { context.insert(receipt) }
        try context.save()
        let count = try ReceiptBusinessTransfer.move([personal, personal, income, business, reimbursable]) {
            try context.save()
        }
        XCTAssertEqual(count, 2)
        XCTAssertEqual(personal.reviewStatus, .inbox)
        XCTAssertNil(personal.reviewedAt)
        XCTAssertEqual(personal.asset?.id, asset.id)
        XCTAssertEqual(personal.asset?.storageRelativePath, "receipts/original.jpg")
        XCTAssertEqual(personal.notes, "Keep this note")
        XCTAssertEqual(personal.totalAmount, 123)
        XCTAssertEqual(income.transactionKind, .income)
        XCTAssertEqual(business.reviewStatus, .reviewed)
        XCTAssertEqual(reimbursable.expenseType, .reimbursable)
        let reloaded = try ModelContext(container).fetch(FetchDescriptor<Receipt>())
        XCTAssertEqual(reloaded.count, 4)
        XCTAssertEqual(reloaded.first { $0.id == personal.id }?.expenseType, .business)
        XCTAssertEqual(try ReceiptBusinessTransfer.move([personal, income]) { XCTFail("No save expected") }, 0)
    }

    func testBusinessTransferRestoresBatchOnSaveFailure() throws {
        enum Failure: Error { case save }
        let first = Receipt(reviewStatus: .reviewed, importSource: .manual, notes: "Original")
        let second = Receipt(importSource: .files)
        first.reviewedAt = Date(timeIntervalSince1970: 123)
        first.searchText = "original search"
        let updatedAt = first.updatedAt
        XCTAssertThrowsError(try ReceiptBusinessTransfer.move([first, second]) {
            first.notes = "Unrelated edit"
            throw Failure.save
        })
        XCTAssertEqual(first.expenseType, .personal)
        XCTAssertEqual(second.expenseType, .personal)
        XCTAssertEqual(first.reviewStatus, .reviewed)
        XCTAssertEqual(first.reviewedAt, Date(timeIntervalSince1970: 123))
        XCTAssertEqual(first.updatedAt, updatedAt)
        XCTAssertEqual(first.searchText, "original search")
        XCTAssertEqual(first.notes, "Unrelated edit")
    }

    func testCollapsedSettingsDoesNotReadCloudAIKeychainState() throws {
        var container: ModelContainer? = try PocketPalModelContainer.make(
            isStoredInMemoryOnly: true,
            cloudSyncEnabled: false
        )
        let keychainService = SpyKeychainService()
        let services = ServiceContainer(keychainService: keychainService)

        let view = SettingsView()
            .environment(\.serviceContainer, services)
            .modelContainer(try XCTUnwrap(container))

        var host: NSHostingView<AnyView>? = NSHostingView(rootView: AnyView(view))
        host?.frame = NSRect(x: 0, y: 0, width: 560, height: 640)
        host?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host?.layoutSubtreeIfNeeded()

        XCTAssertEqual(keychainService.retrieveSecureStringCount, 0)

        host = nil
        container = nil
    }
}

private final class SpyKeychainService: KeychainServicing, @unchecked Sendable {
    private(set) var retrieveSecureStringCount = 0

    func store(key: String, data: Data) throws {}

    func retrieve(key: String) throws -> Data? {
        nil
    }

    func delete(key: String) throws {}

    func storeSecureString(key: String, value: String) throws {}

    func retrieveSecureString(key: String) throws -> String? {
        retrieveSecureStringCount += 1
        return nil
    }
}
private struct FinanceTestStorage: ReceiptFileStorageServicing {
    let root: URL
    func fileURL(forRelativePath path: String) -> URL { root.appendingPathComponent(path) }
    func storeImportedFile(from sourceURL: URL, receiptID: UUID) throws -> StoredReceiptFile { throw CocoaError(.featureUnsupported) }
    func storeImportedData(_ document: ImportedReceiptDocument, receiptID: UUID) throws -> StoredReceiptFile { throw CocoaError(.featureUnsupported) }
    func removeAllStoredFiles() throws { throw CocoaError(.featureUnsupported) }
}
#endif
