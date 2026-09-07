import Foundation
import ImageIO
import Darwin
@preconcurrency import Vision

private struct GroundTruth: Decodable {
    let company: String?
    let date: String?
    let total: String?
}

private struct OCRSmokeRunner {
    static func recognizeText(at url: URL) async throws -> OCRPayload {
        let source = try imageSource(from: url)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3_200
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OCRPayload, Error>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let candidates = observations.compactMap { $0.topCandidates(1).first }
                let text = candidates.map(\.string).joined(separator: "\n")
                let confidence = candidates.isEmpty ? nil : candidates.map(\.confidence).reduce(0, +) / Float(candidates.count)
                continuation.resume(returning: OCRPayload(rawText: text, confidence: confidence.map(Double.init)))
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = OCRPreferences.selectedRecognitionLanguages()
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func imageSource(from url: URL) throws -> CGImageSource {
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

@main
private struct ReceiptExtractionSmokeTest {
    static func main() async {
        var keyDirectory: URL?
        var imagePaths: [String] = []
        var printsRawOCR = false
        var minimumMerchantMatches: Int?
        var minimumDateMatches: Int?
        var minimumTotalMatches: Int?
        var minimumSamples: Int?
        var args = Array(CommandLine.arguments.dropFirst())

        while let arg = args.first {
            args.removeFirst()
            if arg == "--key-dir", let value = args.first {
                args.removeFirst()
                keyDirectory = URL(fileURLWithPath: value)
            } else if arg == "--raw" {
                printsRawOCR = true
            } else if arg == "--min-merchant-matches" {
                minimumMerchantMatches = parseIntegerArgument(named: arg, args: &args)
            } else if arg == "--min-date-matches" {
                minimumDateMatches = parseIntegerArgument(named: arg, args: &args)
            } else if arg == "--min-total-matches" {
                minimumTotalMatches = parseIntegerArgument(named: arg, args: &args)
            } else if arg == "--min-samples" {
                minimumSamples = parseIntegerArgument(named: arg, args: &args)
            } else {
                imagePaths.append(arg)
            }
        }

        guard !imagePaths.isEmpty else {
            print("Usage: ReceiptExtractionSmokeTest [--key-dir PATH] [--min-samples N] [--min-merchant-matches N] [--min-date-matches N] [--min-total-matches N] image1.jpg image2.jpg ...")
            Darwin.exit(2)
        }

        let service = ReceiptExtractionService()
        var merchantMatches = 0
        var dateMatchCount = 0
        var totalMatches = 0
        var evaluated = 0
        var failedSamples = 0

        for path in imagePaths.sorted() {
            let imageURL = URL(fileURLWithPath: path)
            let sampleID = imageURL.deletingPathExtension().lastPathComponent

            do {
                let payload = try await OCRSmokeRunner.recognizeText(at: imageURL)
                let extraction = service.extractFields(from: payload.rawText)
                let truth = loadGroundTruth(sampleID: sampleID, keyDirectory: keyDirectory)

                let merchantMatch = truth?.company.map { approximatelyMatches(extraction.merchantName, expected: $0) }
                let dateMatch = truth?.date.map { dateMatches(extraction.transactionDate, expected: $0) }
                let totalMatch = truth?.total.map { amountMatches(extraction.totalAmount, expected: $0) }

                if truth != nil {
                    evaluated += 1
                    merchantMatches += merchantMatch == true ? 1 : 0
                    dateMatchCount += dateMatch == true ? 1 : 0
                    totalMatches += totalMatch == true ? 1 : 0
                }

                print("""

                == \(imageURL.lastPathComponent) ==
                OCR confidence: \(format(payload.confidence))
                Local confidence: \(format(extraction.confidence)) / \(extraction.decision.rawValue)
                Merchant: \(extraction.merchantName ?? "-") \(status(merchantMatch))
                Date: \(formatDate(extraction.transactionDate)) \(status(dateMatch))
                Total: \(formatAmount(extraction.totalAmount)) \(status(totalMatch))
                Currency: \(extraction.currencyCode ?? "-")
                Expected: \(expectedSummary(truth))
                OCR preview: \(preview(payload.rawText))
                """)

                if printsRawOCR {
                    print("OCR raw:\n\(payload.rawText)")
                }
            } catch {
                failedSamples += 1
                print("\n== \(imageURL.lastPathComponent) ==\nERROR: \(error.localizedDescription)")
            }
        }

        if evaluated > 0 {
            print("""

            == Summary ==
            Samples: \(evaluated)
            Merchant matches: \(merchantMatches)/\(evaluated)
            Date matches: \(dateMatchCount)/\(evaluated)
            Total matches: \(totalMatches)/\(evaluated)
            """)
        }

        var failures: [String] = []
        if failedSamples > 0 {
            failures.append("\(failedSamples) sample(s) failed during OCR/extraction")
        }
        if let minimumSamples, evaluated < minimumSamples {
            failures.append("expected at least \(minimumSamples) labeled samples, got \(evaluated)")
        }
        if let minimumMerchantMatches, merchantMatches < minimumMerchantMatches {
            failures.append("expected at least \(minimumMerchantMatches) merchant matches, got \(merchantMatches)")
        }
        if let minimumDateMatches, dateMatchCount < minimumDateMatches {
            failures.append("expected at least \(minimumDateMatches) date matches, got \(dateMatchCount)")
        }
        if let minimumTotalMatches, totalMatches < minimumTotalMatches {
            failures.append("expected at least \(minimumTotalMatches) total matches, got \(totalMatches)")
        }

        guard failures.isEmpty else {
            for failure in failures {
                print("FAIL: \(failure)")
            }
            Darwin.exit(1)
        }
    }

    private static func parseIntegerArgument(named name: String, args: inout [String]) -> Int {
        guard let value = args.first, let integer = Int(value) else {
            print("Invalid or missing value for \(name)")
            Darwin.exit(2)
        }

        args.removeFirst()
        return integer
    }

    private static func loadGroundTruth(sampleID: String, keyDirectory: URL?) -> GroundTruth? {
        guard let keyDirectory else { return nil }
        let url = keyDirectory.appendingPathComponent("\(sampleID).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GroundTruth.self, from: data)
    }

    private static func approximatelyMatches(_ actual: String?, expected: String) -> Bool {
        guard let actual else { return false }
        let normalizedActual = normalize(actual)
        let normalizedExpected = normalize(expected)
        guard !normalizedActual.isEmpty, !normalizedExpected.isEmpty else { return false }
        return normalizedActual == normalizedExpected
            || normalizedActual.contains(normalizedExpected)
            || normalizedExpected.contains(normalizedActual)
    }

    private static func dateMatches(_ actual: Date?, expected: String) -> Bool {
        guard let actual, let expectedDate = parseExpectedDate(expected) else { return false }
        return Calendar.current.isDate(actual, inSameDayAs: expectedDate)
    }

    private static func amountMatches(_ actual: Double?, expected: String) -> Bool {
        guard let actual, let expectedAmount = AmountParser.parse(expected) else { return false }
        return abs(actual - expectedAmount) < 0.01
    }

    private static func parseExpectedDate(_ value: String) -> Date? {
        let components = value
            .split { $0 == "-" || $0 == "/" || $0 == "." }
            .map(String.init)
        guard components.count == 3,
              let first = Int(components[0]),
              let second = Int(components[1]),
              let third = Int(components[2]) else {
            return nil
        }

        let year: Int
        let month: Int
        let day: Int

        if components[0].count == 4 {
            year = first
            month = second
            day = third
        } else {
            year = third < 100 ? (third >= 70 ? 1900 + third : 2000 + third) : third
            if first > 12 {
                day = first
                month = second
            } else if second > 12 {
                month = first
                day = second
            } else {
                day = first
                month = second
            }
        }

        guard (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }

        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }

    private static func status(_ value: Bool?) -> String {
        switch value {
        case .some(true): return "[OK]"
        case .some(false): return "[MISS]"
        case .none: return ""
        }
    }

    private static func expectedSummary(_ truth: GroundTruth?) -> String {
        guard let truth else { return "-" }
        return "merchant=\(truth.company ?? "-"), date=\(truth.date ?? "-"), total=\(truth.total ?? "-")"
    }

    private static func preview(_ text: String) -> String {
        let flattened = text
            .split(whereSeparator: \.isNewline)
            .prefix(8)
            .joined(separator: " | ")
        return flattened.count > 260 ? String(flattened.prefix(260)) + "..." : flattened
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.2f", value)
    }

    private static func formatDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func formatAmount(_ amount: Double?) -> String {
        guard let amount else { return "-" }
        return String(format: "%.2f", amount)
    }
}
