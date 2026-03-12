import Foundation

final class ServiceContainer {
    let fileStorageService: ReceiptFileStorageServicing
    let ocrService: OCRServicing
    let extractionService: ReceiptExtracting
    let importReceiptUseCase: ImportReceiptUseCase

    init(
        fileStorageService: ReceiptFileStorageServicing? = nil,
        ocrService: OCRServicing? = nil,
        extractionService: ReceiptExtracting? = nil
    ) {
        let resolvedFileStorage = fileStorageService ?? ReceiptFileStorageService()
        let resolvedOCRService = ocrService ?? VisionOCRService(storageService: resolvedFileStorage)
        let resolvedExtractionService = extractionService ?? ReceiptExtractionService()

        self.fileStorageService = resolvedFileStorage
        self.ocrService = resolvedOCRService
        self.extractionService = resolvedExtractionService
        self.importReceiptUseCase = ImportReceiptUseCase(
            storageService: resolvedFileStorage,
            ocrService: resolvedOCRService,
            extractionService: resolvedExtractionService
        )
    }
}
