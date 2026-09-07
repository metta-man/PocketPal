#if os(macOS)
import Foundation
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import PocketPal

@MainActor
final class MacReceiptLoopInfrastructureTests: XCTestCase {
    func testMacReceiptImportRunsLocalOCRAndExtractionInReceiptLedger() async throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        let storage = MacFakeReceiptFileStorage(kind: .image, contentType: .jpeg)
        let ocrService = MacFakeOCRService(
            payload: OCRPayload(rawText: "Mac Desk Store\nTOTAL HKD 88.00", confidence: 0.91)
        )
        let transactionDate = Date(timeIntervalSince1970: 1_777_094_400)
        let extractionService = MacFakeReceiptExtractor(
            extraction: ReceiptExtraction(
                merchantName: "Mac Desk Store",
                itemDescription: "USB-C Hub",
                transactionDate: transactionDate,
                totalAmount: 88,
                currencyCode: Currency.hkd.rawValue,
                taxAmount: nil,
                category: ReceiptCategory.office.rawValue,
                confidence: 0.92,
                decision: .acceptedLocal,
                providers: [.localRules]
            )
        )
        let cloudProbe = MacCloudProviderProbe()
        let useCase = ImportReceiptUseCase(
            storageService: storage,
            ocrService: ocrService,
            extractionService: extractionService,
            refinementService: MacNoOpReceiptRefiner(),
            cloudExtractionServiceProvider: { cloudProbe.makeService() },
            processingPolicy: .localOnly
        )

        let receipt = try await useCase.execute(
            input: .inMemory(ImportedReceiptDocument(
                data: Data([0xff, 0xd8, 0xff]),
                suggestedFilename: "mac-receipt.jpg",
                contentType: .jpeg
            )),
            source: .dragDrop,
            modelContext: context
        )

        let persistedReceipt = try await waitForOCRResult(receiptID: receipt.id, context: context)
        let receipts = try context.fetch(FetchDescriptor<Receipt>())
        let assets = try context.fetch(FetchDescriptor<ReceiptAsset>())
        let ocrResults = try context.fetch(FetchDescriptor<OCRResult>())

        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(ocrResults.count, 1)
        XCTAssertEqual(storage.storedInMemoryReceiptIDs, [receipt.id])
        XCTAssertEqual(ocrService.recognizedAssetIDs, [persistedReceipt.asset?.id])
        XCTAssertEqual(cloudProbe.makeCount, 0)

        XCTAssertEqual(persistedReceipt.importSource, .dragDrop)
        XCTAssertEqual(persistedReceipt.processingState, .ready)
        XCTAssertEqual(persistedReceipt.merchantName, "Mac Desk Store")
        XCTAssertEqual(persistedReceipt.itemDescription, "USB-C Hub")
        XCTAssertEqual(persistedReceipt.transactionDate, transactionDate)
        XCTAssertEqual(persistedReceipt.totalAmount, 88)
        XCTAssertEqual(persistedReceipt.currencyCode, Currency.hkd.rawValue)
        XCTAssertEqual(persistedReceipt.category, ReceiptCategory.office.rawValue)
        XCTAssertEqual(persistedReceipt.extractionDecision, .acceptedLocal)
        XCTAssertEqual(persistedReceipt.extractionProvider, .localRules)
        XCTAssertTrue(persistedReceipt.searchText.contains("Mac Desk Store"))
        XCTAssertTrue(persistedReceipt.searchText.contains("TOTAL HKD 88.00"))
    }

    private func waitForOCRResult(receiptID: UUID, context: ModelContext) async throws -> Receipt {
        let deadline = Date().addingTimeInterval(2)

        while Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
            var descriptor = FetchDescriptor<Receipt>(
                predicate: #Predicate { receipt in
                    receipt.id == receiptID
                }
            )
            descriptor.fetchLimit = 1

            if let receipt = try context.fetch(descriptor).first,
               receipt.processingState == .ready,
               receipt.ocrResult != nil {
                return receipt
            }
        }

        XCTFail("Timed out waiting for macOS OCR result")
        throw CocoaError(.userCancelled)
    }
}

private final class MacFakeReceiptFileStorage: ReceiptFileStorageServicing {
    private let kind: ReceiptAssetKind
    private let contentType: UTType
    private(set) var storedInMemoryReceiptIDs: [UUID] = []

    init(kind: ReceiptAssetKind, contentType: UTType) {
        self.kind = kind
        self.contentType = contentType
    }

    func storeImportedFile(from sourceURL: URL, receiptID: UUID) throws -> StoredReceiptFile {
        storedFile(receiptID: receiptID, originalFilename: sourceURL.lastPathComponent)
    }

    func storeImportedData(_ document: ImportedReceiptDocument, receiptID: UUID) throws -> StoredReceiptFile {
        storedInMemoryReceiptIDs.append(receiptID)
        return storedFile(receiptID: receiptID, originalFilename: document.suggestedFilename)
    }

    func fileURL(forRelativePath relativePath: String) -> URL {
        URL(filePath: NSTemporaryDirectory()).appending(path: relativePath)
    }

    func removeAllStoredFiles() throws {}

    private func storedFile(receiptID: UUID, originalFilename: String) -> StoredReceiptFile {
        StoredReceiptFile(
            relativePath: "\(receiptID.uuidString)/original.jpg",
            thumbnailRelativePath: "\(receiptID.uuidString)/thumbnail.jpg",
            originalFilename: originalFilename,
            contentType: contentType,
            kind: kind,
            fileSizeBytes: 3
        )
    }
}

private final class MacFakeOCRService: OCRServicing {
    private let payload: OCRPayload
    private(set) var recognizedAssetIDs: [UUID] = []

    init(payload: OCRPayload) {
        self.payload = payload
    }

    func recognizeText(for asset: ReceiptAsset) async throws -> OCRPayload {
        recognizedAssetIDs.append(asset.id)
        return payload
    }
}

private struct MacFakeReceiptExtractor: ReceiptExtracting {
    let extraction: ReceiptExtraction

    func extractFields(from rawText: String) -> ReceiptExtraction {
        extraction
    }
}

private struct MacNoOpReceiptRefiner: ReceiptRefining {
    func refine(rawText: String, localExtraction: ReceiptExtraction) async throws -> ReceiptExtraction? {
        nil
    }
}

private final class MacCloudProviderProbe: @unchecked Sendable {
    private(set) var makeCount = 0

    func makeService() -> CloudReceiptExtractionServicing {
        makeCount += 1
        return MacFailingCloudReceiptExtractionService()
    }
}

private struct MacFailingCloudReceiptExtractionService: CloudReceiptExtractionServicing {
    func isConfigured() -> Bool {
        XCTFail("Cloud service should not be configured during macOS local-only import")
        return false
    }

    func extractReceipt(from request: CloudReceiptExtractionRequest) async throws -> ReceiptExtraction {
        XCTFail("Cloud extraction should not run during macOS local-only import")
        throw CloudReceiptExtractionError.unsupportedProvider
    }
}
#endif
