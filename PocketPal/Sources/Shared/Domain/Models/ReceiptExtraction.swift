import Foundation

struct OCRPayload: Sendable {
    let rawText: String
    let confidence: Double?
}

enum ReceiptExtractionProvider: String, Codable, CaseIterable, Sendable {
    case visionOCR
    case localRules
    case appleFoundationModel
    case openAI
    case gemini

    var displayName: String {
        switch self {
        case .visionOCR:
            return "Vision OCR"
        case .localRules:
            return "Local rules"
        case .appleFoundationModel:
            return "Apple Intelligence"
        case .gemini:
            return "Gemini"
        case .openAI:
            return "OpenAI"
        }
    }
}

enum ReceiptExtractionDecision: String, Codable, CaseIterable, Sendable {
    case acceptedLocal
    case needsReview
    case eligibleForCloudFallback
    case cloudEnhanced
    case cloudFailed

    var displayName: String {
        switch self {
        case .acceptedLocal:
            return "Local"
        case .needsReview:
            return "Review"
        case .eligibleForCloudFallback:
            return "Cloud Ready"
        case .cloudEnhanced:
            return "Cloud"
        case .cloudFailed:
            return "Cloud Failed"
        }
    }
}

enum ReceiptExtractionField: String, Codable, CaseIterable, Hashable, Sendable {
    case merchantName
    case itemDescription
    case transactionDate
    case totalAmount
    case currencyCode
    case taxAmount
    case category
}

struct ReceiptExtraction: Sendable {
    let merchantName: String?
    let itemDescription: String?
    let transactionDate: Date?
    let totalAmount: Double?
    let currencyCode: String?
    let taxAmount: Double?
    let category: String?
    let confidence: Double?
    let decision: ReceiptExtractionDecision
    let providers: [ReceiptExtractionProvider]
    let fieldConfidences: [ReceiptExtractionField: Double]
    let fieldSources: [ReceiptExtractionField: ReceiptExtractionProvider]

    init(
        merchantName: String?,
        itemDescription: String?,
        transactionDate: Date?,
        totalAmount: Double?,
        currencyCode: String?,
        taxAmount: Double?,
        category: String?,
        confidence: Double?,
        decision: ReceiptExtractionDecision = .needsReview,
        providers: [ReceiptExtractionProvider] = [.localRules],
        fieldConfidences: [ReceiptExtractionField: Double] = [:],
        fieldSources: [ReceiptExtractionField: ReceiptExtractionProvider] = [:]
    ) {
        self.merchantName = merchantName
        self.itemDescription = itemDescription
        self.transactionDate = transactionDate
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode
        self.taxAmount = taxAmount
        self.category = category
        self.confidence = confidence
        self.decision = decision
        self.providers = providers
        self.fieldConfidences = fieldConfidences
        self.fieldSources = fieldSources
    }

    var shouldAttemptCloudFallback: Bool {
        decision == .eligibleForCloudFallback
            || merchantName.isNilOrBlank
            || transactionDate == nil
            || totalAmount == nil
            || (confidence ?? 0) < 0.72
    }

    var primaryProvider: ReceiptExtractionProvider {
        providers.last ?? .localRules
    }

    func mergedWithModelResult(
        _ modelResult: ReceiptExtraction,
        provider: ReceiptExtractionProvider,
        cloudEnhanced: Bool = false
    ) -> ReceiptExtraction {
        var mergedFieldConfidences = fieldConfidences
        var mergedFieldSources = fieldSources

        func choose<T>(
            field: ReceiptExtractionField,
            local: T?,
            model: T?,
            defaultModelConfidence: Double
        ) -> T? {
            guard let model else {
                return local
            }

            let localConfidence = mergedFieldConfidences[field] ?? 0
            let modelConfidence = modelResult.fieldConfidences[field] ?? defaultModelConfidence
            guard local == nil || modelConfidence > localConfidence else {
                return local
            }

            mergedFieldConfidences[field] = modelConfidence
            mergedFieldSources[field] = provider
            return model
        }

        let mergedMerchant = choose(field: .merchantName, local: merchantName.nilIfBlank, model: modelResult.merchantName.nilIfBlank, defaultModelConfidence: 0.82)
        let mergedDescription = choose(field: .itemDescription, local: itemDescription.nilIfBlank, model: modelResult.itemDescription.nilIfBlank, defaultModelConfidence: 0.72)
        let mergedDate = choose(field: .transactionDate, local: transactionDate, model: modelResult.transactionDate, defaultModelConfidence: 0.82)
        let mergedTotal = choose(field: .totalAmount, local: totalAmount, model: modelResult.totalAmount, defaultModelConfidence: 0.9)
        let mergedCurrency = choose(field: .currencyCode, local: currencyCode.nilIfBlank, model: modelResult.currencyCode.nilIfBlank, defaultModelConfidence: 0.76)
        let mergedTax = choose(field: .taxAmount, local: taxAmount, model: modelResult.taxAmount, defaultModelConfidence: 0.72)
        let mergedCategory = choose(field: .category, local: category.nilIfBlank, model: modelResult.category.nilIfBlank, defaultModelConfidence: 0.68)
        let mergedConfidence = max(confidence ?? 0, modelResult.confidence ?? 0)
        let mergedDecision: ReceiptExtractionDecision = cloudEnhanced ? .cloudEnhanced : confidenceDecision(
            merchantName: mergedMerchant,
            transactionDate: mergedDate,
            totalAmount: mergedTotal,
            confidence: mergedConfidence
        )

        var mergedProviders = providers
        if !mergedProviders.contains(provider) {
            mergedProviders.append(provider)
        }

        return ReceiptExtraction(
            merchantName: mergedMerchant,
            itemDescription: mergedDescription,
            transactionDate: mergedDate,
            totalAmount: mergedTotal,
            currencyCode: mergedCurrency,
            taxAmount: mergedTax,
            category: mergedCategory,
            confidence: mergedConfidence,
            decision: mergedDecision,
            providers: mergedProviders,
            fieldConfidences: mergedFieldConfidences,
            fieldSources: mergedFieldSources
        )
    }

    func validated(referenceDate: Date = .now) -> ReceiptExtraction {
        let validAmount = totalAmount.flatMap { $0 > 0 ? $0 : nil }
        let validTax: Double?
        if let taxAmount, taxAmount >= 0, validAmount.map({ taxAmount <= $0 }) ?? true {
            validTax = taxAmount
        } else {
            validTax = nil
        }
        let validCurrency = Currency.from(code: currencyCode)?.rawValue
        let validDate = transactionDate.flatMap { date in
            let graceDeadline = Calendar.current.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
            return date <= graceDeadline ? date : nil
        }
        let validConfidence = confidence.map { min(1, max(0, $0)) }
        let decision: ReceiptExtractionDecision
        switch self.decision {
        case .cloudEnhanced, .cloudFailed:
            decision = self.decision
        case .acceptedLocal, .needsReview, .eligibleForCloudFallback:
            decision = Self.confidenceDecision(
                merchantName: merchantName.nilIfBlank,
                transactionDate: validDate,
                totalAmount: validAmount,
                confidence: validConfidence ?? 0
            )
        }

        return ReceiptExtraction(
            merchantName: merchantName.nilIfBlank,
            itemDescription: itemDescription.nilIfBlank,
            transactionDate: validDate,
            totalAmount: validAmount,
            currencyCode: validCurrency,
            taxAmount: validTax,
            category: category.nilIfBlank,
            confidence: validConfidence,
            decision: decision,
            providers: providers,
            fieldConfidences: fieldConfidences,
            fieldSources: fieldSources
        )
    }

    static func confidenceDecision(
        merchantName: String?,
        transactionDate: Date?,
        totalAmount: Double?,
        confidence: Double
    ) -> ReceiptExtractionDecision {
        if merchantName.isNilOrBlank || transactionDate == nil || totalAmount == nil || confidence < 0.55 {
            return .eligibleForCloudFallback
        }

        return confidence >= 0.72 ? .acceptedLocal : .needsReview
    }

    private func confidenceDecision(
        merchantName: String?,
        transactionDate: Date?,
        totalAmount: Double?,
        confidence: Double
    ) -> ReceiptExtractionDecision {
        Self.confidenceDecision(
            merchantName: merchantName,
            transactionDate: transactionDate,
            totalAmount: totalAmount,
            confidence: confidence
        )
    }
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        switch self {
        case .some(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .none:
            return nil
        }
    }

    var isNilOrBlank: Bool {
        nilIfBlank == nil
    }
}
