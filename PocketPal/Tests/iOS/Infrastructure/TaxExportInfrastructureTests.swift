import Foundation
import SwiftData
import XCTest
import SwiftUI
import UIKit
@testable import PocketPal

@MainActor
final class TaxExportInfrastructureTests: XCTestCase {
    func testTaxExportSummarizesAndSerializesReceiptLedgerRows() throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        let readyReceiptID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000101"))
        let incompleteReceiptID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000102"))

        let readyReceipt = Receipt(
            id: readyReceiptID,
            importedAt: Date(timeIntervalSince1970: 1_775_044_800),
            updatedAt: Date(timeIntervalSince1970: 1_775_044_800),
            reviewStatus: .reviewed,
            importSource: .scanner,
            processingState: .ready,
            merchantName: "Lumi, Cafe",
            itemDescription: "Client \"Lunch\"\nSet",
            transactionDate: Date(timeIntervalSince1970: 1_776_230_400),
            totalAmount: 128.5,
            currencyCode: Currency.hkd.rawValue,
            taxAmount: 8.5,
            category: ReceiptCategory.meals.rawValue,
            notes: "Discuss Q2 roadmap",
            extractionConfidence: 0.94,
            extractionProvider: .localRules,
            extractionDecision: .acceptedLocal,
            expenseType: .business,
            taxCategory: .meals
        )
        let readyAsset = ReceiptAsset(
            receiptID: readyReceipt.id,
            kind: .image,
            originalFilename: "lumi-cafe.jpg",
            contentTypeIdentifier: "public.jpeg",
            fileSizeBytes: 2_048,
            storageRelativePath: "\(readyReceipt.id.uuidString)/original.jpg"
        )
        readyAsset.receipt = readyReceipt
        readyReceipt.asset = readyAsset

        let incompleteReceipt = Receipt(
            id: incompleteReceiptID,
            importedAt: Date(timeIntervalSince1970: 1_775_131_200),
            updatedAt: Date(timeIntervalSince1970: 1_775_131_200),
            reviewStatus: .inbox,
            importSource: .manual,
            processingState: .ready,
            expenseType: .business
        )

        context.insert(readyReceipt)
        context.insert(readyAsset)
        context.insert(incompleteReceipt)
        try context.save()

        var descriptor = FetchDescriptor<Receipt>(
            sortBy: [SortDescriptor(\.importedAt)]
        )
        descriptor.includePendingChanges = false
        let receipts = try context.fetch(descriptor)

        let summary = TaxExportService.summary(for: receipts)
        XCTAssertEqual(summary.receiptCount, 2)
        XCTAssertEqual(summary.readyCount, 1)
        XCTAssertEqual(summary.needsReviewCount, 1)
        XCTAssertEqual(summary.deductibleTotalHKD, 128.5)
        XCTAssertEqual(summary.reimbursableTotalHKD, 0)

        let readyReceipts = receipts.filter(\.taxReadiness.isReadyForTaxExport)
        XCTAssertEqual(readyReceipts.map(\.id), [readyReceiptID])

        let allRowsData = TaxExportService.makeTaxCSVData(receipts: receipts)
        XCTAssertEqual([UInt8](allRowsData.prefix(3)), [0xEF, 0xBB, 0xBF])
        let allRowsCSV = try XCTUnwrap(String(
            data: allRowsData,
            encoding: .utf8
        ))
        XCTAssertTrue(allRowsCSV.contains("Tax Ready,Missing Items,Transaction Date"))
        XCTAssertTrue(allRowsCSV.contains("\"Lumi, Cafe\""))
        XCTAssertTrue(allRowsCSV.contains("\"Client \"\"Lunch\"\"\nSet\""))
        XCTAssertTrue(allRowsCSV.contains("Business,Meals & Entertainment,Meals,reviewed,scanner,Discuss Q2 roadmap,\(readyReceiptID.uuidString)"))
        XCTAssertTrue(allRowsCSV.contains("No,Missing merchant; Missing date; Missing amount; Missing category; Missing tax category; No receipt attached"))

        let readyRowsCSV = try XCTUnwrap(String(
            data: TaxExportService.makeTaxCSVData(receipts: readyReceipts),
            encoding: .utf8
        ))
        XCTAssertTrue(readyRowsCSV.contains(readyReceiptID.uuidString))
        XCTAssertFalse(readyRowsCSV.contains(incompleteReceiptID.uuidString))
    }

    private func completeReceipt(reviewed: Bool = false, business: Bool = true) -> Receipt {
        let receipt = Receipt(importedAt: .now, reviewStatus: reviewed ? .reviewed : .inbox,
                              importSource: .scanner, processingState: .ready,
                              merchantName: "Review Cafe", transactionDate: .now,
                              totalAmount: 42, currencyCode: "HKD", category: "Meals",
                              expenseType: business ? .business : .personal,
                              taxCategory: business ? .meals : nil)
        receipt.asset = ReceiptAsset(receiptID: receipt.id, kind: .image,
                                     originalFilename: "receipt.jpg", contentTypeIdentifier: "public.jpeg",
                                     fileSizeBytes: 100, storageRelativePath: "test/receipt.jpg")
        return receipt
    }

    func testCompleteUnconfirmedReceiptCannotEnterFormalExport() throws {
        let pending = completeReceipt()
        let confirmed = completeReceipt(reviewed: true)
        let personal = completeReceipt(reviewed: true, business: false)
        let income = completeReceipt(reviewed: true)
        income.transactionKind = .income
        XCTAssertTrue(pending.taxReadiness.fieldIssues.isEmpty)
        XCTAssertEqual(pending.taxReadiness.issues.map(\.id), ["review"])
        XCTAssertFalse(pending.taxReadiness.isReadyForTaxExport)
        let csv = try XCTUnwrap(String(data: TaxExportService.makeConfirmedTaxCSVData(
            receipts: [pending, confirmed, personal, income]), encoding: .utf8))
        XCTAssertTrue(csv.contains(confirmed.id.uuidString))
        for excluded in [pending, personal, income] { XCTAssertFalse(csv.contains(excluded.id.uuidString)) }
        let backup = try XCTUnwrap(String(data: TaxExportService.makeTaxCSVData(receipts: [pending]), encoding: .utf8))
        XCTAssertTrue(backup.contains(pending.id.uuidString))
        XCTAssertTrue(backup.contains("Not confirmed"))
    }

    func testConfirmationPersistsAndDraftSaveRevokesExportEligibility() throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        let receipt = completeReceipt()
        context.insert(receipt)
        try context.save()
        try ReceiptReviewPersistence.save(receipt: receipt, values: ReceiptReviewValues(receipt: receipt), confirmed: true) {
            try context.save()
        }
        XCTAssertTrue(receipt.taxReadiness.isReadyForTaxExport)
        XCTAssertNotNil(receipt.reviewedAt)
        var edited = ReceiptReviewValues(receipt: receipt)
        edited.totalAmount = 99
        try ReceiptReviewPersistence.save(receipt: receipt, values: edited, confirmed: false) { try context.save() }
        XCTAssertEqual(receipt.totalAmount, 99)
        XCTAssertNil(receipt.reviewedAt)
        XCTAssertFalse(receipt.taxReadiness.isReadyForTaxExport)
        let reloaded = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Receipt>()).first)
        XCTAssertEqual(reloaded.reviewStatus, .inbox)
        XCTAssertEqual(reloaded.totalAmount, 99)
    }

    func testFailedSaveRestoresOnlyCurrentReceiptAndDoesNotAdvanceSession() throws {
        enum Failure: Error { case diskFull }
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        let receipt = completeReceipt()
        let other = completeReceipt()
        context.insert(receipt)
        context.insert(other)
        try context.save()
        other.notes = "Unrelated unsaved work"
        let before = ReceiptReviewValues(receipt: receipt)
        let beforeUpdated = receipt.updatedAt
        let beforeSearch = receipt.searchText
        var draft = before
        draft.totalAmount = 321
        var session = ReceiptReviewSession(receipt: receipt, queue: [receipt, other])
        do {
            try ReceiptReviewPersistence.save(receipt: receipt, values: draft, confirmed: true) { throw Failure.diskFull }
            _ = session.advance()
            XCTFail("Expected save failure")
        } catch Failure.diskFull { }
        XCTAssertEqual(ReceiptReviewValues(receipt: receipt), before)
        XCTAssertEqual(receipt.updatedAt, beforeUpdated)
        XCTAssertEqual(receipt.searchText, beforeSearch)
        XCTAssertEqual(receipt.reviewStatus, .inbox)
        XCTAssertNil(receipt.reviewedAt)
        XCTAssertEqual(other.notes, "Unrelated unsaved work")
        XCTAssertEqual(draft.totalAmount, 321)
        XCTAssertEqual(session.current.id, receipt.id)
    }

    func testMissingFieldsAndFutureDateCannotBeConfirmed() throws {
        let receipt = completeReceipt()
        for issue in ["merchant", "date", "amount", "category", "taxCategory", "proof", "futureDate", "processing"] {
            let valid = completeReceipt()
            switch issue {
            case "merchant": valid.merchantName = nil
            case "date": valid.transactionDate = nil
            case "amount": valid.totalAmount = nil
            case "category": valid.category = nil
            case "taxCategory": valid.taxCategory = nil
            case "proof": valid.asset = nil
            case "futureDate": valid.transactionDate = Date().addingTimeInterval(86400 * 3)
            default: valid.processingState = .runningOCR
            }
            XCTAssertTrue(valid.taxReadiness.fieldIssues.contains { $0.id == issue })
            var didPersist = false
            XCTAssertThrowsError(try ReceiptReviewPersistence.save(receipt: valid,
                values: ReceiptReviewValues(receipt: valid), confirmed: true) { didPersist = true })
            XCTAssertFalse(didPersist)
            XCTAssertEqual(valid.reviewStatus, .inbox)
        }
        var draftRequirements = ReceiptReviewRequirements(receipt: receipt)
        draftRequirements.totalAmount = nil
        XCTAssertEqual(draftRequirements.issues.map(\.id), ["amount"])
        XCTAssertTrue(receipt.taxReadiness.fieldIssues.isEmpty, "Draft validation must not mutate the stored receipt")
    }

    func testReviewQueueSkipsDuplicatesConfirmedAndUnprocessedRecords() throws {
        let first = completeReceipt()
        let reviewed = completeReceipt(reviewed: true)
        let processing = completeReceipt()
        processing.processingState = .runningOCR
        let second = completeReceipt()
        let outsideScope = completeReceipt()
        var session = ReceiptReviewSession(receipt: first, queue: [first, reviewed, processing, second, second])
        XCTAssertEqual(session.nextReceipt?.id, second.id)
        try ReceiptReviewPersistence.save(receipt: first, values: ReceiptReviewValues(receipt: first), confirmed: true) { }
        XCTAssertTrue(session.advance())
        XCTAssertEqual(session.current.id, second.id)
        XCTAssertNotEqual(session.current.id, outsideScope.id)
        XCTAssertNil(session.nextReceipt)
        XCTAssertFalse(session.advance())
        XCTAssertEqual(session.current.id, second.id)
    }


    func testReviewSessionModeSurvivesConfirmationAndCannotAdvanceBeforeSave() throws {
        let first = completeReceipt()
        let second = completeReceipt()
        let route = ReceiptReviewRoute(receipt: first, queue: [first, second])
        var session = ReceiptReviewSession(receipt: first, queue: route.queue)
        XCTAssertFalse(session.advance())
        first.reviewStatus = .reviewed
        XCTAssertTrue(route.isReviewSession)
        XCTAssertTrue(session.advance())
        XCTAssertEqual(session.current.id, second.id)
    }

    func testExtractionChangesRevokePriorConfirmation() {
        let receipt = completeReceipt(reviewed: true)
        receipt.itemDescription = nil
        receipt.reviewedAt = .now
        receipt.apply(extraction: ReceiptExtraction(
            merchantName: nil, itemDescription: "Extracted lunch", transactionDate: nil,
            totalAmount: nil, currencyCode: nil, taxAmount: nil, category: nil,
            confidence: 0.9, decision: .acceptedLocal, providers: [.localRules]))
        XCTAssertEqual(receipt.reviewStatus, .inbox)
        XCTAssertNil(receipt.reviewedAt)
        XCTAssertFalse(receipt.taxReadiness.isReadyForTaxExport)
    }

    func testWorkspaceTotalsExcludeOtherLedgerPendingUndatedAndOtherMonths() {
        let now = Date(timeIntervalSince1970: 1_788_825_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func make(_ purpose: ExpenseType, _ currency: String, _ amount: Double) -> Receipt {
            Receipt(reviewStatus: .reviewed, importSource: .files, processingState: .ready,
                    transactionDate: now, totalAmount: amount, currencyCode: currency, expenseType: purpose)
        }
        let personal = make(.personal, "HKD", 100)
        let foreign = make(.personal, "CNY", 20)
        let income = make(.personal, "HKD", 300)
        income.transactionKind = .income
        let business = make(.business, "HKD", 900)
        let reimbursable = make(.reimbursable, "HKD", 80)
        let pending = make(.personal, "HKD", 999); pending.reviewStatus = .inbox
        let undated = make(.personal, "HKD", 888); undated.transactionDate = nil
        let old = make(.personal, "HKD", 777); old.transactionDate = calendar.date(byAdding: .month, value: -1, to: now)
        let entries = [personal, foreign, income, business, reimbursable, pending, undated, old]
        let totals = WorkspaceSummary.monthlyTotals(entries, ledger: .personal, now: now, calendar: calendar)
        XCTAssertEqual(totals.map(\.currency), ["CNY", "HKD"])
        XCTAssertEqual(totals.map(\.expense), [20, 100])
        XCTAssertEqual(totals.map(\.income), [0, 300])
        XCTAssertEqual(WorkspaceSummary.monthlyTotals(entries, ledger: .business, now: now, calendar: calendar).first?.expense, 980)
        XCTAssertTrue(ReceiptListScope.undated.includes(undated))
        XCTAssertFalse(ReceiptListScope.pending.includes(personal))
        XCTAssertTrue(ReceiptListScope.pending.includes(pending))
    }

    func testWorkspaceSessionKeepsWindowsFiltersAndLocksIndependent() {
        let first = ReceiptWorkspaceSession()
        let second = ReceiptWorkspaceSession()
        first.filters[.personal] = .undated
        first.filters[.business] = .neverExtracted
        first.searches[.personal] = "coffee"
        XCTAssertEqual(first.filters[.personal], .undated)
        XCTAssertEqual(first.filters[.business], .neverExtracted)
        XCTAssertNil(first.searches[.business])
        XCTAssertTrue(second.filters.isEmpty)
        second.restoreFilters(first.savedFilters)
        XCTAssertEqual(second.filters[.business], .neverExtracted)
        XCTAssertEqual(second.searches[.personal], "coffee")
        second.filters[.personal] = .all
        XCTAssertEqual(first.filters[.personal], .undated)
        let editor = UUID(), importer = UUID()
        first.setLocked(true, owner: editor); first.setLocked(true, owner: importer)
        first.setLocked(false, owner: editor)
        XCTAssertTrue(first.isLocked)
        XCTAssertFalse(second.isLocked)
        first.setLocked(false, owner: importer)
        XCTAssertFalse(first.isLocked)
    }

    func testPersonalAndBusinessHomesRenderInBothAppearances() async throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let personal = completeReceipt(reviewed: true, business: false)
        personal.transactionDate = .now
        container.mainContext.insert(personal)
        let business = completeReceipt(business: true)
        container.mainContext.insert(business)
        try container.mainContext.save()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        for ledger in ReceiptLedger.allCases {
            for dark in [false, true] {
                let content: AnyView = ledger == .personal
                    ? AnyView(PersonalHomeView(openRecords: { _ in }))
                    : AnyView(BusinessHomeView(openReceipts: { _ in }))
                let view = VStack(spacing: 0) {
                    WorkspaceSwitcher(ledger: .constant(ledger), locked: false)
                    content
                }
                .modelContainer(container)
                .environment(\.receiptWorkspace, ReceiptWorkspaceSession())
                .environment(\.serviceContainer, ServiceContainer())
                .environment(\.dynamicTypeSize, dark ? .accessibility3 : .large)
                .environment(\.colorScheme, dark ? .dark : .light)
                let host = UIHostingController(rootView: view)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
                window.rootViewController = host; window.isHidden = false
                host.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 200_000_000)
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "workspace-\(ledger.rawValue)-\(dark ? "dark-large" : "light")"
                attachment.lifetime = .keepAlways
                add(attachment)
                XCTAssertGreaterThan(image.size.height, 0)
                window.isHidden = true; window.rootViewController = nil
            }
        }
    }

    func testReviewEditorRendersAtPhoneSizeAndAccessibilitySize() async throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let receipt = completeReceipt(business: false)
        receipt.asset = nil
        container.mainContext.insert(receipt)
        try container.mainContext.save()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        for largeText in [false, true] {
            let view = NavigationStack {
                ReceiptDetailView(receipt: receipt, reviewQueue: [receipt])
            }
            .modelContainer(container)
            .environment(\.serviceContainer, ServiceContainer())
            .environment(\.dynamicTypeSize, largeText ? .accessibility3 : .large)
            .environment(\.colorScheme, largeText ? .dark : .light)
            let host = UIHostingController(rootView: view)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 200_000_000)
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            XCTAssertGreaterThan(image.size.height, 0)
            let attachment = XCTAttachment(image: image)
            attachment.name = largeText ? "review-accessibility-dark" : "review-phone-light"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }


    func testReviewQueueSkipsReceiptDeletedDuringSession() throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        let first = completeReceipt()
        let deleted = completeReceipt()
        let last = completeReceipt()
        for receipt in [first, deleted, last] { context.insert(receipt) }
        try context.save()
        let session = ReceiptReviewSession(receipt: first, queue: [first, deleted, last])
        context.delete(deleted)
        XCTAssertEqual(session.nextReceipt?.id, last.id)
        try context.save()
        XCTAssertEqual(session.nextReceipt?.id, last.id)
    }

}
