import Foundation

final class ServiceContainer {
    let fileStorageService: ReceiptFileStorageServicing
    let ocrService: OCRServicing
    let extractionService: ReceiptExtracting
    let refinementService: ReceiptRefining
    let receiptProcessingPolicy: ReceiptProcessingPolicy
    let importReceiptUseCase: ImportReceiptUseCase
    let keychainService: KeychainServicing

    init(
        fileStorageService: ReceiptFileStorageServicing? = nil,
        ocrService: OCRServicing? = nil,
        extractionService: ReceiptExtracting? = nil,
        refinementService: ReceiptRefining? = nil,
        cloudExtractionServiceProvider: (@Sendable () -> CloudReceiptExtractionServicing)? = nil,
        receiptProcessingPolicy: ReceiptProcessingPolicy = .appDefaults,
        keychainService: KeychainServicing? = nil,
        keychainServiceProvider: (@Sendable () -> KeychainServicing)? = nil
    ) {
        let resolvedFileStorage = fileStorageService ?? ReceiptFileStorageService()
        let resolvedOCRService = ocrService ?? VisionOCRService(storageService: resolvedFileStorage)
        let resolvedExtractionService = extractionService ?? ReceiptExtractionService()
        let resolvedKeychainService = keychainService ?? LazyKeychainService(
            factory: keychainServiceProvider ?? { KeychainService() }
        )
        let resolvedRefinementService = refinementService ?? FoundationModelReceiptRefinementService()
        let resolvedCloudExtractionServiceProvider = cloudExtractionServiceProvider ?? {
            GeminiReceiptExtractionService(keychainService: resolvedKeychainService)
        }

        self.fileStorageService = resolvedFileStorage
        self.ocrService = resolvedOCRService
        self.extractionService = resolvedExtractionService
        self.refinementService = resolvedRefinementService
        self.receiptProcessingPolicy = receiptProcessingPolicy
        self.keychainService = resolvedKeychainService
        self.importReceiptUseCase = ImportReceiptUseCase(
            storageService: resolvedFileStorage,
            ocrService: resolvedOCRService,
            extractionService: resolvedExtractionService,
            refinementService: resolvedRefinementService,
            cloudExtractionServiceProvider: resolvedCloudExtractionServiceProvider,
            processingPolicy: receiptProcessingPolicy
        )
    }
}
