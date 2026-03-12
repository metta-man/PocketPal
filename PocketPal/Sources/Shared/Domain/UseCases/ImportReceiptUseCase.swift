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
        receipt.touch()
        receipt.rebuildSearchText()

        modelContext.insert(asset)
        try modelContext.save()

        do {
            let ocrPayload = try await ocrService.recognizeText(for: asset)
            let extraction = extractionService.extractFields(from: ocrPayload.rawText)

            let ocrResult = OCRResult(rawText: ocrPayload.rawText, confidence: ocrPayload.confidence)
            ocrResult.receipt = receipt
            receipt.ocrResult = ocrResult
            receipt.apply(extraction: extraction)
            receipt.touch()
            receipt.rebuildSearchText()

            modelContext.insert(ocrResult)
            try modelContext.save()
        } catch OCRServiceError.unsupportedAssetType {
            try modelContext.save()
        }

        return receipt
    }
}
