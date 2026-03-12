import Foundation
import ImageIO
@preconcurrency import Vision

enum OCRServiceError: LocalizedError {
    case missingAssetURL
    case unsupportedAssetType

    var errorDescription: String? {
        switch self {
        case .missingAssetURL:
            return "The imported asset could not be located."
        case .unsupportedAssetType:
            return "OCR is currently supported for image receipts only."
        }
    }
}

protocol OCRServicing {
    func recognizeText(for asset: ReceiptAsset) async throws -> OCRPayload
}

final class VisionOCRService: OCRServicing {
    private let storageService: ReceiptFileStorageServicing

    init(storageService: ReceiptFileStorageServicing) {
        self.storageService = storageService
    }

    func recognizeText(for asset: ReceiptAsset) async throws -> OCRPayload {
        guard asset.kind == .image else {
            throw OCRServiceError.unsupportedAssetType
        }

        let fileURL = storageService.fileURL(forRelativePath: asset.storageRelativePath)
        return try await recognizeText(at: fileURL)
    }

    private func recognizeText(at url: URL) async throws -> OCRPayload {
        let cgImage = try makeOCRImage(from: url)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OCRPayload, Error>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
                let text = recognizedStrings.joined(separator: "\n")
                let confidence = observations.isEmpty ? nil : observations.map(\.confidence).reduce(0, +) / Float(observations.count)
                continuation.resume(
                    returning: OCRPayload(rawText: text, confidence: confidence.map(Double.init))
                )
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = OCRPreferences.selectedRecognitionLanguages()
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handler = VNImageRequestHandler(cgImage: cgImage)
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func makeOCRImage(from url: URL) throws -> CGImage {
        let source = try imageSource(from: url)

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3_200
        ]

        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return thumbnail
        }

        guard let fullImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return fullImage
    }

    private func imageSource(from url: URL) throws -> CGImageSource {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            return source
        }

        let data = try Data(contentsOf: url)
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            return source
        }

        throw CocoaError(.fileReadCorruptFile)
    }
}
