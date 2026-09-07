import Foundation
import SwiftData
import UniformTypeIdentifiers

struct ReceiptProcessingPolicy: Sendable {
    let automaticCloudEnhancementEnabled: @Sendable () -> Bool
    let cloudUploadConsentGranted: @Sendable () -> Bool

    static let appDefaults = ReceiptProcessingPolicy(
        automaticCloudEnhancementEnabled: { AppPreferences.cloudReceiptEnhancementEnabled },
        cloudUploadConsentGranted: { AppPreferences.cloudReceiptUploadConsentGranted }
    )

    static let localOnly = ReceiptProcessingPolicy(
        automaticCloudEnhancementEnabled: { false },
        cloudUploadConsentGranted: { false }
    )

    var allowsAutomaticCloudExtraction: Bool {
        automaticCloudEnhancementEnabled() && cloudUploadConsentGranted()
    }

    // Kept as a compatibility entry point; Gemini now runs regardless of local confidence.
    func allowsAutomaticCloudFallback(for extraction: ReceiptExtraction) -> Bool {
        allowsAutomaticCloudExtraction
    }
}

final class ImportReceiptUseCase {
    private let storageService: ReceiptFileStorageServicing
    private let ocrService: OCRServicing
    private let extractionService: ReceiptExtracting
    private let refinementService: ReceiptRefining
    private let cloudExtractionServiceProvider: @Sendable () -> CloudReceiptExtractionServicing
    private let processingPolicy: ReceiptProcessingPolicy
    @MainActor private var activeReceiptIDs: Set<UUID> = []

    @MainActor
    func canManuallyExtract(_ receipt: Receipt) -> Bool {
        receipt.asset != nil && !activeReceiptIDs.contains(receipt.id)
    }

    init(
        storageService: ReceiptFileStorageServicing,
        ocrService: OCRServicing,
        extractionService: ReceiptExtracting,
        refinementService: ReceiptRefining,
        cloudExtractionServiceProvider: @escaping @Sendable () -> CloudReceiptExtractionServicing,
        processingPolicy: ReceiptProcessingPolicy = .appDefaults
    ) {
        self.storageService = storageService
        self.ocrService = ocrService
        self.extractionService = extractionService
        self.refinementService = refinementService
        self.cloudExtractionServiceProvider = cloudExtractionServiceProvider
        self.processingPolicy = processingPolicy
    }

    @discardableResult
    @MainActor
    func execute(
        input: ReceiptImportInput,
        source: ReceiptImportSource,
        modelContext: ModelContext,
        expenseType: ExpenseType = .personal
    ) async throws -> Receipt {
        let receipt = Receipt(importSource: source, expenseType: expenseType)
        modelContext.insert(receipt)

        let storedFile: StoredReceiptFile
        do {
            switch input {
            case .file(let fileURL):
                storedFile = try storageService.storeImportedFile(from: fileURL, receiptID: receipt.id)
            case .inMemory(let document):
                storedFile = try storageService.storeImportedData(document, receiptID: receipt.id)
            }
        } catch {
            // Roll back the pending Receipt so a failed import leaves no orphan rows.
            modelContext.delete(receipt)
            throw error
        }

        let asset = ReceiptAsset(
            receiptID: receipt.id,
            kind: storedFile.kind,
            originalFilename: storedFile.originalFilename,
            contentTypeIdentifier: storedFile.contentType.identifier,
            fileSizeBytes: storedFile.fileSizeBytes,
            storageRelativePath: storedFile.relativePath,
            thumbnailRelativePath: storedFile.thumbnailRelativePath
        )

        asset.receipt = receipt
        receipt.asset = asset
        receipt.processingState = (storedFile.kind == .image || processingPolicy.allowsAutomaticCloudExtraction) ? .queued : .ready
        receipt.processingErrorMessage = nil
        receipt.touch()
        receipt.rebuildSearchText()

        modelContext.insert(asset)
        do {
            try modelContext.save()
        } catch {
            // Roll back all staged rows so a failed save leaves no pending
            // Receipt/ReceiptAsset (and therefore no OCRResult) objects in
            // the ModelContext. The asset is removed before its parent
            // Receipt to respect relationship teardown order.
            modelContext.delete(asset)
            modelContext.delete(receipt)
            throw error
        }

        if storedFile.kind == .image || processingPolicy.allowsAutomaticCloudExtraction {
            let receiptID = receipt.id
            Task { @MainActor [weak self] in
                await self?.processOCRIfNeeded(for: receiptID, modelContext: modelContext)
            }
        }

        return receipt
    }

    @MainActor
    private func processOCRIfNeeded(for receiptID: UUID, modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Receipt>(predicate: #Predicate { $0.id == receiptID })
        descriptor.fetchLimit = 1
        guard let receipt = try? modelContext.fetch(descriptor).first,
              let asset = receipt.asset,
              receipt.reviewStatus != .reviewed,
              receipt.processingState == .queued || receipt.processingState == .failed else { return }
        guard activeReceiptIDs.insert(receipt.id).inserted else { return }
        defer { activeReceiptIDs.remove(receipt.id) }
        let original = ReceiptReviewValues(receipt: receipt)
        receipt.processingState = .runningOCR
        receipt.processingErrorMessage = nil
        var rawText = ""
        var extraction = extractionService.extractFields(from: "")
        var localError: String?

        if asset.kind == .image {
            do {
                let payload = try await ocrService.recognizeText(for: asset)
                rawText = payload.rawText
                extraction = try await makeLocalExtraction(from: rawText)
                guard !receipt.isDeleted, receipt.modelContext != nil else { return }
                let ocrResult: OCRResult
                if let existing = receipt.ocrResult {
                    ocrResult = existing
                    ocrResult.rawText = rawText
                    ocrResult.confidence = payload.confidence
                } else {
                    ocrResult = OCRResult(rawText: rawText, confidence: payload.confidence)
                    ocrResult.receipt = receipt
                    receipt.ocrResult = ocrResult
                    modelContext.insert(ocrResult)
                }
                guard ReceiptReviewValues(receipt: receipt) == original, receipt.reviewStatus != .reviewed else {
                    receipt.processingState = .ready
                    try? modelContext.save()
                    return
                }
                receipt.apply(extraction: extraction)
            } catch {
                localError = error.localizedDescription
            }
        }
        guard !receipt.isDeleted, receipt.modelContext != nil else { return }
        if localError != nil && (ReceiptReviewValues(receipt: receipt) != original || receipt.reviewStatus == .reviewed) {
            receipt.processingState = .ready
            try? modelContext.save()
            return
        }
        // Stay in processing state until cloud extraction completes: no premature confirmation.
        receipt.touch()
        receipt.rebuildSearchText()
        try? modelContext.save()
        var cloudSucceeded = false
        if processingPolicy.allowsAutomaticCloudFallback(for: extraction) {
            let cloudExtractionService = cloudExtractionServiceProvider()
            if cloudExtractionService.isConfigured() {
                let baseline = ReceiptReviewValues(receipt: receipt)
                do {
                    let result = try await cloudExtraction(for: receipt, asset: asset, rawText: rawText,
                        localExtraction: extraction, cloudExtractionService: cloudExtractionService)
                    guard !receipt.isDeleted, receipt.modelContext != nil else { return }
                    guard processingPolicy.allowsAutomaticCloudExtraction else {
                        throw GeminiReceiptError.receiptChanged
                    }
                    try Self.applyCloudResult(result, to: receipt, expected: baseline)
                    cloudSucceeded = true
                    receipt.cloudExtractionErrorMessage = nil
                } catch {
                    guard !receipt.isDeleted, receipt.modelContext != nil else { return }
                    receipt.cloudExtractionErrorMessage = error.localizedDescription
                    receipt.extractionDecision = .cloudFailed
                }
            } else {
                receipt.cloudExtractionErrorMessage = GeminiReceiptError.missingKey.localizedDescription
            }
        }
        receipt.processingState = (cloudSucceeded || localError == nil) ? .ready : .failed
        receipt.processingErrorMessage = cloudSucceeded ? nil : localError
        receipt.touch()
        receipt.rebuildSearchText()
        try? modelContext.save()
    }

    @MainActor
    func enhanceWithCloud(for receipt: Receipt, modelContext: ModelContext,
                          uploadConsentGranted: Bool = false,
                          allowReplacingConfirmedReceipt: Bool = false) async throws {
        guard uploadConsentGranted || processingPolicy.cloudUploadConsentGranted() else {
            throw GeminiReceiptError.consentRequired
        }
        guard receipt.reviewStatus != .reviewed || allowReplacingConfirmedReceipt else {
            throw GeminiReceiptError.confirmedReceipt
        }
        guard let asset = receipt.asset, canManuallyExtract(receipt) else {
            throw CloudReceiptExtractionError.missingImageData
        }
        activeReceiptIDs.insert(receipt.id)
        defer { activeReceiptIDs.remove(receipt.id) }
        let rawText = receipt.ocrResult?.rawText ?? ""
        let baseline = ReceiptReviewValues(receipt: receipt)
        // A persisted running flag can outlive its task after termination or an update.
        let previousState: ReceiptProcessingState = receipt.processingState.isActive ? .failed : receipt.processingState
        let previousConfidence = receipt.extractionConfidence
        let previousProvider = receipt.extractionProvider
        let previousReviewStatus = receipt.reviewStatus
        let previousReviewedAt = receipt.reviewedAt
        var didApplyResult = false
        receipt.processingState = .runningOCR
        receipt.cloudExtractionAttemptedAt = .now
        receipt.cloudExtractionErrorMessage = nil
        receipt.touch()
        do {
            try modelContext.save()
        } catch {
            receipt.processingState = previousState
            throw error
        }
        do {
            let result = try await cloudExtraction(for: receipt, asset: asset, rawText: rawText,
                localExtraction: extractionService.extractFields(from: rawText),
                cloudExtractionService: cloudExtractionServiceProvider())
            guard !receipt.isDeleted, receipt.modelContext != nil else { throw GeminiReceiptError.receiptChanged }
            try Self.applyCloudResult(
                result,
                to: receipt,
                expected: baseline,
                allowReplacingConfirmedReceipt: allowReplacingConfirmedReceipt
            )
            didApplyResult = true
            receipt.processingState = .ready
            receipt.processingErrorMessage = nil
            receipt.touch()
            receipt.rebuildSearchText()
            try modelContext.save()
        } catch {
            if !receipt.isDeleted, receipt.modelContext != nil {
                if didApplyResult {
                    baseline.apply(to: receipt)
                    receipt.extractionConfidence = previousConfidence
                    receipt.extractionProvider = previousProvider
                    receipt.reviewStatus = previousReviewStatus
                    receipt.reviewedAt = previousReviewedAt
                    receipt.rebuildSearchText()
                }
                receipt.processingState = previousState
                receipt.cloudExtractionErrorMessage = error.localizedDescription
                receipt.extractionDecision = .cloudFailed
                try? modelContext.save()
            }
            throw error
        }
    }

    /// Cloud facts replace machine candidates, including nulls. Confirmed values are replaced only after an explicit UI confirmation.
    @MainActor
    static func applyCloudResult(_ extraction: ReceiptExtraction, to receipt: Receipt,
                                 expected: ReceiptReviewValues,
                                 allowReplacingConfirmedReceipt: Bool = false) throws {
        guard (receipt.reviewStatus != .reviewed || allowReplacingConfirmedReceipt),
              ReceiptReviewValues(receipt: receipt) == expected else {
            throw GeminiReceiptError.receiptChanged
        }
        receipt.merchantName = extraction.merchantName
        receipt.itemDescription = extraction.itemDescription
        receipt.transactionDate = extraction.transactionDate
        receipt.totalAmount = extraction.totalAmount
        receipt.currencyCode = extraction.currencyCode
        receipt.taxAmount = extraction.taxAmount
        receipt.category = extraction.category
        receipt.extractionConfidence = extraction.confidence
        receipt.extractionProvider = extraction.primaryProvider
        receipt.extractionDecision = extraction.decision
        receipt.reviewStatus = .inbox
        receipt.reviewedAt = nil
    }

    private func makeLocalExtraction(from rawText: String) async throws -> ReceiptExtraction {
        let localExtraction = extractionService.extractFields(from: rawText)
        guard let refinedExtraction = try await refinementService.refine(rawText: rawText, localExtraction: localExtraction) else {
            return localExtraction
        }

        return localExtraction.mergedWithModelResult(
            refinedExtraction,
            provider: .appleFoundationModel
        )
        .validated()
    }

    private func cloudExtraction(
        for receipt: Receipt,
        asset: ReceiptAsset,
        rawText: String,
        localExtraction: ReceiptExtraction,
        cloudExtractionService: CloudReceiptExtractionServicing
    ) async throws -> ReceiptExtraction {
        receipt.cloudExtractionAttemptedAt = .now
        receipt.cloudExtractionErrorMessage = nil
        let fileURL = storageService.fileURL(forRelativePath: asset.storageRelativePath)
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= GeminiReceiptExtractionService.maximumDocumentBytes else { throw GeminiReceiptError.documentTooLarge }
        let imageData = try Data(contentsOf: fileURL)
        let request = CloudReceiptExtractionRequest(
            rawText: rawText,
            imageData: imageData,
            imageContentType: mimeType(for: asset),
            localExtraction: localExtraction
        )
        let cloudExtraction = try await cloudExtractionService.extractReceipt(from: request)
        return cloudExtraction.validated()
    }

    private func mimeType(for asset: ReceiptAsset) -> String {
        if let type = UTType(asset.contentTypeIdentifier),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }

        return "image/jpeg"
    }
}
