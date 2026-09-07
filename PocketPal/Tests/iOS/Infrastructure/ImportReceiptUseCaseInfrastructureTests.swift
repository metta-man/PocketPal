import Foundation
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import PocketPal

@MainActor
final class ImportReceiptUseCaseInfrastructureTests: XCTestCase {
    func testImageImportCreatesReceiptAssetAndOCRWithoutCloudFallback() async throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        let storage = FakeReceiptFileStorage(kind: .image, contentType: .jpeg)
        let ocrService = FakeOCRService(
            payload: OCRPayload(rawText: "Lumi Cafe\nTOTAL HKD 42.50", confidence: 0.93)
        )
        let extractionDate = Date(timeIntervalSince1970: 1_767_225_600)
        let extractionService = FakeReceiptExtractor(
            extraction: ReceiptExtraction(
                merchantName: "Lumi Cafe",
                itemDescription: "Coffee",
                transactionDate: extractionDate,
                totalAmount: 42.5,
                currencyCode: Currency.hkd.rawValue,
                taxAmount: nil,
                category: ReceiptCategory.meals.rawValue,
                confidence: 0.94,
                decision: .acceptedLocal,
                providers: [.localRules]
            )
        )
        let cloudProbe = CloudProviderProbe()
        let useCase = ImportReceiptUseCase(
            storageService: storage,
            ocrService: ocrService,
            extractionService: extractionService,
            refinementService: NoOpReceiptRefiner(),
            cloudExtractionServiceProvider: { cloudProbe.makeService() },
            processingPolicy: .localOnly
        )

        let receipt = try await useCase.execute(
            input: .inMemory(ImportedReceiptDocument(
                data: Data([0xff, 0xd8, 0xff]),
                suggestedFilename: "receipt.jpg",
                contentType: .jpeg
            )),
            source: .scanner,
            modelContext: context,
            expenseType: .business
        )

        let persistedReceipt = try await waitForOCRResult(receiptID: receipt.id, context: context)
        let receipts = try context.fetch(FetchDescriptor<Receipt>())
        let assets = try context.fetch(FetchDescriptor<ReceiptAsset>())
        let ocrResults = try context.fetch(FetchDescriptor<OCRResult>())

        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(ocrResults.count, 1)
        XCTAssertEqual(storage.storedInMemoryReceiptIDs, [receipt.id])
        XCTAssertEqual(storage.storedFileReceiptIDs, [])
        XCTAssertEqual(ocrService.recognizedAssetIDs, [persistedReceipt.asset?.id])
        XCTAssertEqual(cloudProbe.makeCount, 0)

        XCTAssertEqual(persistedReceipt.expenseType, .business)
        XCTAssertEqual(persistedReceipt.importSource, .scanner)
        XCTAssertEqual(persistedReceipt.processingState, .ready)
        XCTAssertEqual(persistedReceipt.merchantName, "Lumi Cafe")
        XCTAssertEqual(persistedReceipt.itemDescription, "Coffee")
        XCTAssertEqual(persistedReceipt.transactionDate, extractionDate)
        XCTAssertEqual(persistedReceipt.totalAmount, 42.5)
        XCTAssertEqual(persistedReceipt.currencyCode, Currency.hkd.rawValue)
        XCTAssertEqual(persistedReceipt.category, ReceiptCategory.meals.rawValue)
        XCTAssertEqual(persistedReceipt.extractionDecision, .acceptedLocal)
        XCTAssertEqual(persistedReceipt.extractionProvider, .localRules)
        XCTAssertTrue(persistedReceipt.searchText.contains("Lumi Cafe"))
        XCTAssertTrue(persistedReceipt.searchText.contains("TOTAL HKD 42.50"))

        let asset = try XCTUnwrap(persistedReceipt.asset)
        XCTAssertEqual(asset.receiptID, persistedReceipt.id)
        XCTAssertEqual(asset.receipt?.id, persistedReceipt.id)
        XCTAssertEqual(asset.kind, .image)
        XCTAssertEqual(asset.originalFilename, "receipt.jpg")
        XCTAssertEqual(asset.contentTypeIdentifier, UTType.jpeg.identifier)
        XCTAssertEqual(asset.storageRelativePath, "\(persistedReceipt.id.uuidString)/original.jpg")

        let ocrResult = try XCTUnwrap(persistedReceipt.ocrResult)
        XCTAssertEqual(ocrResult.receipt?.id, persistedReceipt.id)
        XCTAssertEqual(ocrResult.rawText, "Lumi Cafe\nTOTAL HKD 42.50")
        XCTAssertEqual(ocrResult.confidence, 0.93)
    }

    func testStorageFailureDoesNotLeaveReceiptRows() async throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        let useCase = ImportReceiptUseCase(
            storageService: ThrowingReceiptFileStorage(),
            ocrService: FakeOCRService(payload: OCRPayload(rawText: "", confidence: nil)),
            extractionService: FakeReceiptExtractor(extraction: .emptyAcceptedLocal),
            refinementService: NoOpReceiptRefiner(),
            cloudExtractionServiceProvider: { FailingCloudReceiptExtractionService() },
            processingPolicy: .localOnly
        )

        do {
            _ = try await useCase.execute(
                input: .inMemory(ImportedReceiptDocument(
                    data: Data("broken".utf8),
                    suggestedFilename: "broken.jpg",
                    contentType: .jpeg
                )),
                source: .files,
                modelContext: context
            )
            XCTFail("Expected storage failure to abort import")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
        }

        XCTAssertEqual(try context.fetch(FetchDescriptor<Receipt>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReceiptAsset>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<OCRResult>()).count, 0)
    }

    func testServiceContainerInitializationDoesNotConstructCredentialOrCloudProviders() {
        let keychainProbe = KeychainProviderProbe()
        let cloudProbe = CloudProviderProbe()
        let services = ServiceContainer(
            fileStorageService: FakeReceiptFileStorage(kind: .image, contentType: .jpeg),
            ocrService: FakeOCRService(payload: OCRPayload(rawText: "", confidence: nil)),
            extractionService: FakeReceiptExtractor(extraction: .emptyAcceptedLocal),
            refinementService: NoOpReceiptRefiner(),
            cloudExtractionServiceProvider: { cloudProbe.makeService() },
            keychainServiceProvider: { keychainProbe.makeService() }
        )

        _ = services.importReceiptUseCase

        XCTAssertEqual(keychainProbe.makeCount, 0)
        XCTAssertEqual(cloudProbe.makeCount, 0)
    }

    func testDefaultServiceContainerDoesNotConstructKeychainForLocalOnlyImport() async throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        let storage = FakeReceiptFileStorage(kind: .image, contentType: .jpeg)
        let ocrService = FakeOCRService(
            payload: OCRPayload(rawText: "Local Only Store\nTOTAL HKD 10.00", confidence: 0.95)
        )
        let extractionService = FakeReceiptExtractor(
            extraction: ReceiptExtraction(
                merchantName: "Local Only Store",
                itemDescription: nil,
                transactionDate: nil,
                totalAmount: 10,
                currencyCode: Currency.hkd.rawValue,
                taxAmount: nil,
                category: nil,
                confidence: 0.95,
                decision: .acceptedLocal,
                providers: [.localRules]
            )
        )
        let keychainProbe = KeychainProviderProbe()
        let services = ServiceContainer(
            fileStorageService: storage,
            ocrService: ocrService,
            extractionService: extractionService,
            refinementService: NoOpReceiptRefiner(),
            receiptProcessingPolicy: .localOnly,
            keychainServiceProvider: { keychainProbe.makeService() }
        )

        XCTAssertEqual(keychainProbe.makeCount, 0)

        let receipt = try await services.importReceiptUseCase.execute(
            input: .inMemory(ImportedReceiptDocument(
                data: Data([0xff, 0xd8, 0xff]),
                suggestedFilename: "local-only.jpg",
                contentType: .jpeg
            )),
            source: .scanner,
            modelContext: context
        )

        _ = try await waitForOCRResult(receiptID: receipt.id, context: context)
        XCTAssertEqual(keychainProbe.makeCount, 0)
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

        XCTFail("Timed out waiting for OCR result")
        throw CocoaError(.userCancelled)
    }
}

private final class FakeReceiptFileStorage: ReceiptFileStorageServicing {
    private let kind: ReceiptAssetKind
    private let contentType: UTType
    private(set) var storedFileReceiptIDs: [UUID] = []
    private(set) var storedInMemoryReceiptIDs: [UUID] = []

    init(kind: ReceiptAssetKind, contentType: UTType) {
        self.kind = kind
        self.contentType = contentType
    }

    func storeImportedFile(from sourceURL: URL, receiptID: UUID) throws -> StoredReceiptFile {
        storedFileReceiptIDs.append(receiptID)
        return storedFile(receiptID: receiptID, originalFilename: sourceURL.lastPathComponent)
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

private struct ThrowingReceiptFileStorage: ReceiptFileStorageServicing {
    func storeImportedFile(from sourceURL: URL, receiptID: UUID) throws -> StoredReceiptFile {
        throw CocoaError(.fileWriteNoPermission)
    }

    func storeImportedData(_ document: ImportedReceiptDocument, receiptID: UUID) throws -> StoredReceiptFile {
        throw CocoaError(.fileWriteNoPermission)
    }

    func fileURL(forRelativePath relativePath: String) -> URL {
        URL(filePath: NSTemporaryDirectory()).appending(path: relativePath)
    }

    func removeAllStoredFiles() throws {}
}

private final class FakeOCRService: OCRServicing {
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

private struct FakeReceiptExtractor: ReceiptExtracting {
    let extraction: ReceiptExtraction

    func extractFields(from rawText: String) -> ReceiptExtraction {
        extraction
    }
}

private struct NoOpReceiptRefiner: ReceiptRefining {
    func refine(rawText: String, localExtraction: ReceiptExtraction) async throws -> ReceiptExtraction? {
        nil
    }
}

private final class CloudProviderProbe: @unchecked Sendable {
    private(set) var makeCount = 0

    func makeService() -> CloudReceiptExtractionServicing {
        makeCount += 1
        return FailingCloudReceiptExtractionService()
    }
}

private final class KeychainProviderProbe: @unchecked Sendable {
    private(set) var makeCount = 0

    func makeService() -> KeychainServicing {
        makeCount += 1
        return FailingKeychainService()
    }
}

private struct FailingKeychainService: KeychainServicing {
    func store(key: String, data: Data) throws {
        XCTFail("Keychain should not be constructed or used during local-only import")
    }

    func retrieve(key: String) throws -> Data? {
        XCTFail("Keychain should not be constructed or used during local-only import")
        return nil
    }

    func delete(key: String) throws {
        XCTFail("Keychain should not be constructed or used during local-only import")
    }

    func storeSecureString(key: String, value: String) throws {
        XCTFail("Keychain should not be constructed or used during local-only import")
    }

    func retrieveSecureString(key: String) throws -> String? {
        XCTFail("Keychain should not be constructed or used during local-only import")
        return nil
    }
}

private struct FailingCloudReceiptExtractionService: CloudReceiptExtractionServicing {
    func isConfigured() -> Bool {
        XCTFail("Cloud service should not be configured during local-only import")
        return false
    }

    func extractReceipt(from request: CloudReceiptExtractionRequest) async throws -> ReceiptExtraction {
        XCTFail("Cloud extraction should not run during local-only import")
        throw CloudReceiptExtractionError.unsupportedProvider
    }
}

private extension ReceiptExtraction {
    static var emptyAcceptedLocal: ReceiptExtraction {
        ReceiptExtraction(
            merchantName: nil,
            itemDescription: nil,
            transactionDate: nil,
            totalAmount: nil,
            currencyCode: nil,
            taxAmount: nil,
            category: nil,
            confidence: 1,
            decision: .acceptedLocal,
            providers: [.localRules]
        )
    }
}

@MainActor
final class GeminiReceiptInfrastructureTests: XCTestCase {
    private let fields = #"{"merchant_name":"香港茶餐廳","item_description":null,"transaction_date":"2026-08-30","total_amount":128.5,"currency_code":"HKD","tax_amount":0,"category":"Meals"}"#

    private func makeSession(status: Int = 200, finish: String = "STOP", text: String? = nil,
                             inspect: ((URLRequest) throws -> Void)? = nil) -> URLSession {
        let text = text ?? fields
        GeminiTestURLProtocol.handler = { request in
            try inspect?(request)
            return (status, try JSONSerialization.data(withJSONObject: [
                "candidates": [["finishReason": finish, "content": ["parts": [["text": text]]]]]
            ]))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiTestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func request(mime: String = "image/jpeg") -> CloudReceiptExtractionRequest {
        CloudReceiptExtractionRequest(rawText: "OCR WRONG TOTAL 999", imageData: Data([1, 2, 3]),
                                      imageContentType: mime, localExtraction: .emptyAcceptedLocal)
    }

    func testGeminiSendsOriginalDocumentAndNullableSchemaWithoutKeyInURL() async throws {
        let session = makeSession { request in
            XCTAssertEqual(request.url?.host, "generativelanguage.googleapis.com")
            XCTAssertTrue(request.url?.path.contains("gemini-3.5-flash-lite:generateContent") == true)
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-only-key")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: GeminiTestURLProtocol.body(request)) as? [String: Any])
            let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
            let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
            let media = try XCTUnwrap(parts.first?["inlineData"] as? [String: String])
            XCTAssertEqual(media["data"], Data([1, 2, 3]).base64EncodedString())
            XCTAssertEqual(media["mimeType"], "image/jpeg")
            let config = try XCTUnwrap(body["generationConfig"] as? [String: Any])
            XCTAssertEqual(config["responseMimeType"] as? String, "application/json")
            let schema = try XCTUnwrap(config["responseJsonSchema"] as? [String: Any])
            let properties = try XCTUnwrap(schema["properties"] as? [String: [String: Any]])
            XCTAssertEqual(properties["total_amount"]?["type"] as? [String], ["number", "null"])
        }
        defer { session.invalidateAndCancel() }
        let result = try await GeminiReceiptExtractionService(keychainService: GeminiTestKeychain(), session: session)
            .extractReceipt(from: request())
        XCTAssertEqual(result.merchantName, "香港茶餐廳")
        XCTAssertEqual(result.totalAmount, 128.5)
        XCTAssertEqual(result.taxAmount, 0)
        XCTAssertNil(result.itemDescription)
        XCTAssertNil(result.confidence)
        XCTAssertEqual(result.primaryProvider, .gemini)
    }

    func testGeminiPreservesUnknownsAndRejectsTruncatedMalformedAndHTTPResponses() async throws {
        let unknowns = #"{"merchant_name":null,"item_description":null,"transaction_date":null,"total_amount":null,"currency_code":null,"tax_amount":null,"category":null}"#
        let session = makeSession(text: unknowns)
        defer { session.invalidateAndCancel() }
        let result = try await GeminiReceiptExtractionService(keychainService: GeminiTestKeychain(), session: session)
            .extractReceipt(from: request(mime: "application/pdf"))
        XCTAssertNil(result.totalAmount)
        XCTAssertNil(result.currencyCode)
        for (status, finish, text) in [(429, "STOP", fields), (200, "MAX_TOKENS", fields), (200, "STOP", "{}"), (200, "STOP", "invalid")] {
            let badSession = makeSession(status: status, finish: finish, text: text)
            defer { badSession.invalidateAndCancel() }
            do {
                _ = try await GeminiReceiptExtractionService(keychainService: GeminiTestKeychain(), session: badSession)
                    .extractReceipt(from: request())
                XCTFail("Invalid response must not replace local data")
            } catch { }
        }
    }

    func testMissingKeyDoesNotSendRequestAndLegacyConsentIsNotReused() async {
        let session = makeSession { _ in XCTFail("Must not send without Gemini credentials") }
        defer { session.invalidateAndCancel() }
        do {
            _ = try await GeminiReceiptExtractionService(keychainService: GeminiTestKeychain(key: nil), session: session)
                .extractReceipt(from: request())
            XCTFail("Expected missing key")
        } catch { XCTAssertTrue(error is GeminiReceiptError) }
        XCTAssertNotEqual(AppPreferences.geminiAPIKeyKey, AppPreferences.openAIAPIKeyKey)
        XCTAssertNotEqual(AppPreferences.cloudReceiptUploadConsentKey, "settings.cloudReceiptUploadConsent")
        XCTAssertFalse(ReceiptProcessingPolicy(automaticCloudEnhancementEnabled: { true }, cloudUploadConsentGranted: { false })
            .allowsAutomaticCloudFallback(for: .emptyAcceptedLocal))
    }

    func testCloudFactsCorrectWrongOCRAndDoNotOverwriteConcurrentEditsOrConfirmation() throws {
        let receipt = Receipt(importSource: .scanner, processingState: .ready, merchantName: "Wrong", totalAmount: 999)
        let result = geminiResult
        try ImportReceiptUseCase.applyCloudResult(result, to: receipt, expected: ReceiptReviewValues(receipt: receipt))
        XCTAssertEqual(receipt.totalAmount, 128.5)
        XCTAssertEqual(receipt.extractionProvider, .gemini)
        let baseline = ReceiptReviewValues(receipt: receipt)
        receipt.totalAmount = 200
        XCTAssertThrowsError(try ImportReceiptUseCase.applyCloudResult(result, to: receipt, expected: baseline))
        XCTAssertEqual(receipt.totalAmount, 200)
        receipt.reviewStatus = .reviewed
        XCTAssertThrowsError(try ImportReceiptUseCase.applyCloudResult(result, to: receipt, expected: ReceiptReviewValues(receipt: receipt)))
        XCTAssertEqual(receipt.reviewStatus, .reviewed)
    }

    func testAutomaticGeminiRunsForHighConfidenceImageAndPDFEvenWhenOCRFails() async throws {
        for (pdf, failOCR) in [(false, false), (false, true), (true, false)] {
            let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
            let context = ModelContext(container)
            let storage = try GeminiTestStorage(pdf: pdf)
            defer { try? FileManager.default.removeItem(at: storage.root) }
            let useCase = ImportReceiptUseCase(storageService: storage,
                ocrService: GeminiPipelineOCR(fail: failOCR, shouldNotRun: pdf),
                extractionService: FakeReceiptExtractor(extraction: ReceiptExtraction(merchantName: "Wrong OCR", itemDescription: nil,
                    transactionDate: .now, totalAmount: 999, currencyCode: "HKD", taxAmount: nil, category: "Meals",
                    confidence: 0.99, decision: .acceptedLocal)), refinementService: NoOpReceiptRefiner(),
                cloudExtractionServiceProvider: { FakeGeminiService(result: self.geminiResult, pdf: pdf) },
                processingPolicy: ReceiptProcessingPolicy(automaticCloudEnhancementEnabled: { true }, cloudUploadConsentGranted: { true }))
            let receipt = try await useCase.execute(input: .inMemory(ImportedReceiptDocument(data: Data([1, 2, 3]),
                suggestedFilename: pdf ? "receipt.pdf" : "receipt.jpg", contentType: pdf ? .pdf : .jpeg)), source: .files, modelContext: context)
            for _ in 0..<100 {
                if !receipt.processingState.isActive { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertEqual(receipt.processingState, .ready)
            XCTAssertEqual(receipt.extractionProvider, .gemini)
            XCTAssertEqual(receipt.totalAmount, 128.5)
            XCTAssertEqual(receipt.reviewStatus, .inbox)
            XCTAssertNil(receipt.processingErrorMessage)
        }
    }

    func testManualPDFExtractionRequiresConsentButDoesNotRequireOCRText() async throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        let storage = try GeminiTestStorage(pdf: true)
        defer { try? FileManager.default.removeItem(at: storage.root) }
        let useCase = ImportReceiptUseCase(storageService: storage,
            ocrService: GeminiPipelineOCR(fail: false, shouldNotRun: true),
            extractionService: FakeReceiptExtractor(extraction: .emptyAcceptedLocal), refinementService: NoOpReceiptRefiner(),
            cloudExtractionServiceProvider: { FakeGeminiService(result: self.geminiResult, pdf: true) }, processingPolicy: .localOnly)
        let receipt = try await useCase.execute(input: .inMemory(ImportedReceiptDocument(data: Data([1, 2, 3]),
            suggestedFilename: "receipt.pdf", contentType: .pdf)), source: .files, modelContext: context)
        XCTAssertNil(receipt.ocrResult)
        // Simulate a previous process exiting while extraction was running.
        receipt.processingState = .runningOCR
        try context.save()
        XCTAssertTrue(useCase.canManuallyExtract(receipt))
        do {
            try await useCase.enhanceWithCloud(for: receipt, modelContext: context)
            XCTFail("Manual upload requires explicit consent")
        } catch { XCTAssertEqual(error.localizedDescription, GeminiReceiptError.consentRequired.localizedDescription) }
        try await useCase.enhanceWithCloud(for: receipt, modelContext: context, uploadConsentGranted: true)
        XCTAssertEqual(receipt.totalAmount, 128.5)
        XCTAssertEqual(receipt.extractionProvider, .gemini)
        XCTAssertEqual(receipt.processingState, .ready)
    }

    func testConfirmedReceiptCanBeExplicitlyReprocessedAndReturnsToReview() async throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        let storage = try GeminiTestStorage(pdf: true)
        defer { try? FileManager.default.removeItem(at: storage.root) }
        let useCase = ImportReceiptUseCase(
            storageService: storage,
            ocrService: GeminiPipelineOCR(fail: false, shouldNotRun: true),
            extractionService: FakeReceiptExtractor(extraction: .emptyAcceptedLocal),
            refinementService: NoOpReceiptRefiner(),
            cloudExtractionServiceProvider: { FakeGeminiService(result: self.geminiResult, pdf: true) },
            processingPolicy: .localOnly
        )
        let receipt = try await useCase.execute(
            input: .inMemory(ImportedReceiptDocument(
                data: Data([1, 2, 3]),
                suggestedFilename: "old-receipt.pdf",
                contentType: .pdf
            )),
            source: .files,
            modelContext: context
        )
        receipt.merchantName = "Old merchant"
        receipt.totalAmount = 999
        receipt.notes = "Keep this note"
        receipt.expenseType = .business
        receipt.taxCategory = .deductible
        receipt.reviewStatus = .reviewed
        receipt.reviewedAt = .now
        try context.save()

        do {
            try await useCase.enhanceWithCloud(
                for: receipt,
                modelContext: context,
                uploadConsentGranted: true
            )
            XCTFail("Confirmed receipts still require explicit replacement consent")
        } catch {
            XCTAssertEqual(error.localizedDescription, GeminiReceiptError.confirmedReceipt.localizedDescription)
        }

        try await useCase.enhanceWithCloud(
            for: receipt,
            modelContext: context,
            uploadConsentGranted: true,
            allowReplacingConfirmedReceipt: true
        )

        XCTAssertEqual(receipt.merchantName, "香港茶餐廳")
        XCTAssertEqual(receipt.totalAmount, 128.5)
        XCTAssertEqual(receipt.extractionProvider, .gemini)
        XCTAssertEqual(receipt.reviewStatus, .inbox)
        XCTAssertNil(receipt.reviewedAt)
        XCTAssertEqual(receipt.notes, "Keep this note")
        XCTAssertEqual(receipt.expenseType, .business)
        XCTAssertEqual(receipt.taxCategory, .deductible)
    }

    func testOfflineGeminiPreservesLocalExtraction() async throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        let context = ModelContext(container)
        let storage = try GeminiTestStorage(pdf: false)
        defer { try? FileManager.default.removeItem(at: storage.root) }
        let local = ReceiptExtraction(merchantName: "Local Cafe", itemDescription: nil, transactionDate: .now,
            totalAmount: 42, currencyCode: "HKD", taxAmount: nil, category: "Meals", confidence: 0.99)
        let useCase = ImportReceiptUseCase(storageService: storage,
            ocrService: GeminiPipelineOCR(fail: false, shouldNotRun: false),
            extractionService: FakeReceiptExtractor(extraction: local), refinementService: NoOpReceiptRefiner(),
            cloudExtractionServiceProvider: { OfflineGeminiService() },
            processingPolicy: ReceiptProcessingPolicy(automaticCloudEnhancementEnabled: { true }, cloudUploadConsentGranted: { true }))
        let receipt = try await useCase.execute(input: .inMemory(ImportedReceiptDocument(data: Data([1, 2, 3]),
            suggestedFilename: "receipt.jpg", contentType: .jpeg)), source: .files, modelContext: context)
        for _ in 0..<100 {
            if !receipt.processingState.isActive { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(receipt.processingState, .ready)
        XCTAssertEqual(receipt.merchantName, "Local Cafe")
        XCTAssertEqual(receipt.totalAmount, 42)
        XCTAssertEqual(receipt.extractionProvider, .localRules)
        XCTAssertEqual(receipt.extractionDecision, .cloudFailed)
        XCTAssertNotNil(receipt.cloudExtractionErrorMessage)
        XCTAssertNotNil(receipt.asset)
    }

    func testBatchSelectionKeepsSuccessfulGeminiResultsEvenAfterFailedRetry() {
        let receipt = Receipt(importSource: .files, processingState: .ready)
        receipt.asset = ReceiptAsset(receiptID: receipt.id, kind: .image,
            originalFilename: "test.jpg", contentTypeIdentifier: "public.jpeg",
            fileSizeBytes: 3, storageRelativePath: "test.jpg")
        XCTAssertTrue(GeminiReceiptSelection.neverExtracted.includes(receipt))
        receipt.extractionProvider = .gemini
        receipt.cloudExtractionErrorMessage = "HTTP 429"
        XCTAssertFalse(GeminiReceiptSelection.neverExtracted.includes(receipt))
        XCTAssertTrue(GeminiReceiptSelection.unconfirmed.includes(receipt))
        receipt.reviewStatus = .reviewed
        XCTAssertFalse(GeminiReceiptSelection.unconfirmed.includes(receipt))
        XCTAssertTrue(GeminiReceiptSelection.all.includes(receipt))
        receipt.asset = nil
        XCTAssertFalse(GeminiReceiptSelection.all.includes(receipt))
    }

    func testPersonalAndBusinessLedgersDoNotOverlap() {
        let personal = Receipt(importSource: .manual, expenseType: .personal)
        let business = Receipt(importSource: .manual, expenseType: .business)
        let reimbursable = Receipt(importSource: .manual, expenseType: .reimbursable)
        for receipt in [personal, business, reimbursable] {
            XCTAssertNotEqual(ReceiptLedger.personal.includes(receipt), ReceiptLedger.business.includes(receipt))
        }
        XCTAssertTrue(ReceiptLedger.personal.includes(personal))
        XCTAssertTrue(ReceiptLedger.business.includes(business))
        XCTAssertTrue(ReceiptLedger.business.includes(reimbursable))
    }

    func testQuotaPolicyHonorsServerDelayAndStopsDailyQuota() throws {
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 429,
                                       httpVersion: nil, headerFields: ["Retry-After": "45"])!
        let temporary = GeminiQuotaError(response: response, data: Data())
        XCTAssertEqual(temporary.retryDelay(attempt: 0), 45)
        XCTAssertEqual(temporary.retryDelay(attempt: 1), 60)
        XCTAssertNil(temporary.retryDelay(attempt: 2))
        let body = Data(#"{"error":{"details":[{"violations":[{"quotaId":"GenerateRequestsPerDayPerProject"}]}]}}"#.utf8)
        let daily = GeminiQuotaError(response: response, data: body)
        XCTAssertTrue(daily.dailyQuota)
        XCTAssertNil(daily.retryDelay(attempt: 0))
    }

    func testGeminiConnectionCheckDoesNotUploadDocuments() async throws {
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertFalse(request.url!.path.contains("generateContent"))
            XCTAssertTrue(GeminiTestURLProtocol.body(request).isEmpty)
        }
        defer { session.invalidateAndCancel() }
        try await GeminiReceiptExtractionService(keychainService: GeminiTestKeychain(), session: session).verifyConfiguration()
    }

    private nonisolated var geminiResult: ReceiptExtraction {
        ReceiptExtraction(merchantName: "香港茶餐廳", itemDescription: nil, transactionDate: Date(timeIntervalSince1970: 1_788_048_000),
            totalAmount: 128.5, currencyCode: "HKD", taxAmount: nil, category: "Meals", confidence: nil,
            decision: .cloudEnhanced, providers: [.gemini])
    }
}

private struct GeminiTestKeychain: KeychainServicing {
    var key: String? = "test-only-key"
    func store(key: String, data: Data) throws { }
    func retrieve(key: String) throws -> Data? { nil }
    func delete(key: String) throws { }
    func storeSecureString(key: String, value: String) throws { }
    func retrieveSecureString(key: String) throws -> String? {
        XCTAssertEqual(key, AppPreferences.geminiAPIKeyKey)
        return self.key
    }
}

private final class GeminiTestURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
    static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

private struct GeminiPipelineOCR: OCRServicing {
    let fail: Bool
    let shouldNotRun: Bool
    func recognizeText(for asset: ReceiptAsset) async throws -> OCRPayload {
        XCTAssertFalse(shouldNotRun)
        if fail { throw CocoaError(.fileReadCorruptFile) }
        return OCRPayload(rawText: "Wrong OCR TOTAL 999", confidence: 0.99)
    }
}

private struct FakeGeminiService: CloudReceiptExtractionServicing {
    let result: ReceiptExtraction
    let pdf: Bool
    func isConfigured() -> Bool { true }
    func extractReceipt(from request: CloudReceiptExtractionRequest) async throws -> ReceiptExtraction {
        XCTAssertEqual(request.imageContentType, pdf ? "application/pdf" : "image/jpeg")
        XCTAssertEqual(request.imageData, Data([1, 2, 3]))
        return result
    }
}

private struct GeminiTestStorage: ReceiptFileStorageServicing {
    let root: URL
    let pdf: Bool
    init(pdf: Bool) throws {
        self.pdf = pdf
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func storeImportedFile(from sourceURL: URL, receiptID: UUID) throws -> StoredReceiptFile { throw CocoaError(.fileReadUnknown) }
    func storeImportedData(_ document: ImportedReceiptDocument, receiptID: UUID) throws -> StoredReceiptFile {
        try document.data.write(to: root.appendingPathComponent("original"))
        return StoredReceiptFile(relativePath: "original", thumbnailRelativePath: nil, originalFilename: document.suggestedFilename,
                                 contentType: pdf ? .pdf : .jpeg, kind: pdf ? .pdf : .image, fileSizeBytes: Int64(document.data.count))
    }
    func fileURL(forRelativePath relativePath: String) -> URL { root.appendingPathComponent(relativePath) }
    func removeAllStoredFiles() throws { try FileManager.default.removeItem(at: root) }
}

private struct OfflineGeminiService: CloudReceiptExtractionServicing {
    func isConfigured() -> Bool { true }
    func extractReceipt(from request: CloudReceiptExtractionRequest) async throws -> ReceiptExtraction {
        throw URLError(.notConnectedToInternet)
    }
}
