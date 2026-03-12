import Foundation
import SwiftData

final class ImportReceiptUseCase {
    private let storageService: ReceiptFileStorageServicing
    private let ocrService: OCRServicing
    private let extractionService: ReceiptExtracting

    init(
        storageService: ReceiptFileStorageServicing,
        ocrService: OCRServicing,
        extractionService: ReceiptExtracting
    ) {
        self.storageService = storageService
        self.ocrService = ocrService
        self.extractionService = extractionService
    }

    @discardableResult
    @MainActor
    func execute(
        input: ReceiptImportInput,
        source: ReceiptImportSource,
        modelContext: ModelContext
    ) async throws -> Receipt {
        let receipt = Receipt(importSource: source)
        modelContext.insert(receipt)

        let storedFile: StoredReceiptFile
        switch input {
        case .file(let fileURL):
            storedFile = try storageService.storeImportedFile(from: fileURL, receiptID: receipt.id)
        case .inMemory(let document):
            storedFile = try storageService.storeImportedData(document, receiptID: receipt.id)
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
        receipt.processingState = storedFile.kind == .image ? .queued : .ready
        receipt.processingErrorMessage = nil
        receipt.touch()
        receipt.rebuildSearchText()

        modelContext.insert(asset)
        try modelContext.save()

        if storedFile.kind == .image {
            let receiptID = receipt.id
            Task { @MainActor [weak self] in
                await self?.processOCRIfNeeded(for: receiptID, modelContext: modelContext)
            }
        }

        return receipt
    }

    @MainActor
    private func processOCRIfNeeded(for receiptID: UUID, modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Receipt>(
            predicate: #Predicate { receipt in
                receipt.id == receiptID
            }
        )
        descriptor.fetchLimit = 1

        guard let receipt = try? modelContext.fetch(descriptor).first,
              let asset = receipt.asset,
              asset.kind == .image,
              receipt.processingState == .queued || receipt.processingState == .failed else {
            return
        }

        receipt.processingState = .runningOCR
        receipt.processingErrorMessage = nil
        receipt.touch()
        try? modelContext.save()

        do {
            let ocrPayload = try await ocrService.recognizeText(for: asset)
            let extraction = extractionService.extractFields(from: ocrPayload.rawText)

            let ocrResult: OCRResult
            if let existingOCRResult = receipt.ocrResult {
                ocrResult = existingOCRResult
                ocrResult.rawText = ocrPayload.rawText
                ocrResult.confidence = ocrPayload.confidence
            } else {
                ocrResult = OCRResult(rawText: ocrPayload.rawText, confidence: ocrPayload.confidence)
                ocrResult.receipt = receipt
                receipt.ocrResult = ocrResult
                modelContext.insert(ocrResult)
            }

            receipt.apply(extraction: extraction)
            receipt.processingState = .ready
            receipt.processingErrorMessage = nil
            receipt.touch()
            receipt.rebuildSearchText()
            try? modelContext.save()
        } catch OCRServiceError.unsupportedAssetType {
            receipt.processingState = .ready
            receipt.processingErrorMessage = nil
            receipt.touch()
            try? modelContext.save()
        } catch {
            receipt.processingState = .failed
            receipt.processingErrorMessage = error.localizedDescription
            receipt.touch()
            try? modelContext.save()
        }
    }
}
