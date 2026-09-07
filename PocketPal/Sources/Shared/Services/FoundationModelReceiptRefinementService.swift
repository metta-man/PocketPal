import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

protocol ReceiptRefining: Sendable {
    func refine(rawText: String, localExtraction: ReceiptExtraction) async throws -> ReceiptExtraction?
}

struct FoundationModelReceiptRefinementService: ReceiptRefining {
    func refine(rawText: String, localExtraction: ReceiptExtraction) async throws -> ReceiptExtraction? {
        guard localExtraction.shouldAttemptCloudFallback || (localExtraction.confidence ?? 0) < 0.82 else {
            return nil
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await FoundationModelReceiptRefiner().refine(rawText: rawText, localExtraction: localExtraction)
        }
        #endif

        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Structured receipt fields extracted from OCR text")
private struct FoundationReceiptExtractionDraft {
    @Guide(description: "Merchant or store name. Empty string if unknown.")
    var merchantName: String

    @Guide(description: "Short item, purchase, or purpose description. Empty string if unknown.")
    var itemDescription: String

    @Guide(description: "Transaction date in yyyy-MM-dd format. Empty string if unknown.")
    var transactionDateISO: String

    @Guide(description: "Final paid total amount. Use 0 if unknown.")
    var totalAmount: Double

    @Guide(description: "Currency code: HKD, USD, or CNY. Empty string if unknown.")
    var currencyCode: String

    @Guide(description: "Tax amount. Use 0 if unknown or not shown.")
    var taxAmount: Double

    @Guide(description: "Best category: Groceries, Meals, Travel, Transport, Office, Shopping, Utilities, Entertainment, Health, Lodging, or Uncategorized.")
    var category: String

    @Guide(description: "Confidence from 0.0 to 1.0.")
    var confidence: Double
}

@available(iOS 26.0, macOS 26.0, *)
private struct FoundationModelReceiptRefiner {
    func refine(rawText: String, localExtraction: ReceiptExtraction) async throws -> ReceiptExtraction? {
        let session = LanguageModelSession(instructions: """
        You extract receipt fields from OCR text for a personal finance app.
        Use the local candidate when it is clearly right.
        Do not invent missing fields. Prefer Hong Kong receipt conventions.
        Return only fields supported by the schema.
        """)
        let localDate = localExtraction.transactionDate.map(Self.isoDateFormatter.string(from:)) ?? ""
        let localTotal = localExtraction.totalAmount.map { String($0) } ?? ""
        let localTax = localExtraction.taxAmount.map { String($0) } ?? ""
        let promptOCR = """
        OCR text:
        \(rawText)
        """

        let promptCandidate = """

        Local candidate:
        merchantName: \(localExtraction.merchantName ?? "")
        itemDescription: \(localExtraction.itemDescription ?? "")
        transactionDate: \(localDate)
        totalAmount: \(localTotal)
        currencyCode: \(localExtraction.currencyCode ?? "")
        taxAmount: \(localTax)
        category: \(localExtraction.category ?? "")

        Extract the final paid total, not subtotal, change, card number, phone number, or balance.
        """
        let prompt = promptOCR + promptCandidate
        let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 600)
        let response = try await session.respond(
            to: prompt,
            generating: FoundationReceiptExtractionDraft.self,
            options: options
        )

        return makeExtraction(from: response.content).validated()
    }

    private func makeExtraction(from draft: FoundationReceiptExtractionDraft) -> ReceiptExtraction {
        let date = draft.transactionDateISO.nilIfBlank.flatMap { Self.isoDateFormatter.date(from: $0) }
        let totalAmount = draft.totalAmount > 0 ? draft.totalAmount : nil
        let taxAmount = draft.taxAmount > 0 ? draft.taxAmount : nil
        let currency = Currency.from(code: draft.currencyCode)?.rawValue
        let confidence = min(1, max(0, draft.confidence))
        let category = ReceiptCategory(rawValue: draft.category)?.rawValue

        var fieldConfidences: [ReceiptExtractionField: Double] = [:]
        var fieldSources: [ReceiptExtractionField: ReceiptExtractionProvider] = [:]

        func record(_ field: ReceiptExtractionField, exists: Bool, confidence: Double) {
            guard exists else { return }
            fieldConfidences[field] = confidence
            fieldSources[field] = .appleFoundationModel
        }

        record(.merchantName, exists: draft.merchantName.nilIfBlank != nil, confidence: 0.82)
        record(.itemDescription, exists: draft.itemDescription.nilIfBlank != nil, confidence: 0.68)
        record(.transactionDate, exists: date != nil, confidence: 0.84)
        record(.totalAmount, exists: totalAmount != nil, confidence: 0.88)
        record(.currencyCode, exists: currency != nil, confidence: 0.78)
        record(.taxAmount, exists: taxAmount != nil, confidence: 0.7)
        record(.category, exists: category != nil, confidence: 0.68)

        return ReceiptExtraction(
            merchantName: draft.merchantName.nilIfBlank,
            itemDescription: draft.itemDescription.nilIfBlank,
            transactionDate: date,
            totalAmount: totalAmount,
            currencyCode: currency,
            taxAmount: taxAmount,
            category: category,
            confidence: confidence,
            decision: ReceiptExtraction.confidenceDecision(
                merchantName: draft.merchantName.nilIfBlank,
                transactionDate: date,
                totalAmount: totalAmount,
                confidence: confidence
            ),
            providers: [.appleFoundationModel],
            fieldConfidences: fieldConfidences,
            fieldSources: fieldSources
        )
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
#endif

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
