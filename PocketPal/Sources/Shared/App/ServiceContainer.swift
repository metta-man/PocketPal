import Foundation

import Foundation

final class ServiceContainer {
    let fileStorageService: ReceiptFileStorageServicing
    let ocrService: OCRServicing
    let extractionService: ReceiptExtracting
    let importReceiptUseCase: ImportReceiptUseCase
    let keychainService: KeychainServicing

    init(
        fileStorageService: ReceiptFileStorageServicing? = nil,
        ocrService: OCRServicing? = nil,
        extractionService: ReceiptExtracting? = nil,
        keychainService: KeychainServicing? = nil
    ) {
        let resolvedFileStorage = fileStorageService ?? ReceiptFileStorageService()
        let resolvedOCRService = ocrService ?? VisionOCRService(storageService: resolvedFileStorage)
        let resolvedExtractionService = extractionService ?? ReceiptExtractionService()
        let resolvedKeychainService = keychainService ?? KeychainService()

        self.fileStorageService = resolvedFileStorage
        self.ocrService = resolvedOCRService
        self.extractionService = resolvedExtractionService
        self.keychainService = resolvedKeychainService
        self.importReceiptUseCase = ImportReceiptUseCase(
            storageService: resolvedFileStorage,
            ocrService: resolvedOCRService,
            extractionService: resolvedExtractionService
        )
    }
}
