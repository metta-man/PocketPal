import Foundation
import SwiftData

@Model
final class Receipt {
    @Attribute(.unique) var id: UUID
    var importedAt: Date
    var updatedAt: Date
    var reviewedAt: Date?
    var reviewStatusRawValue: String
    var importSourceRawValue: String
    var processingStateRawValue: String
    var processingErrorMessage: String?
    var merchantName: String?
    var itemDescription: String?
    var transactionDate: Date?
    var totalAmount: Double?
    var currencyCode: String?
    var taxAmount: Double?
    var category: String?
    var notes: String?
    var extractionConfidence: Double?
    var searchText: String

    @Relationship(deleteRule: .cascade, inverse: \ReceiptAsset.receipt) var asset: ReceiptAsset?
    @Relationship(deleteRule: .cascade, inverse: \OCRResult.receipt) var ocrResult: OCRResult?

    init(
        id: UUID = UUID(),
        importedAt: Date = .now,
        updatedAt: Date = .now,
        reviewStatus: ReceiptReviewStatus = .inbox,
        importSource: ReceiptImportSource,
        processingState: ReceiptProcessingState = .queued,
        merchantName: String? = nil,
        itemDescription: String? = nil,
        transactionDate: Date? = nil,
        totalAmount: Double? = nil,
        currencyCode: String? = nil,
        taxAmount: Double? = nil,
        category: String? = nil,
        notes: String? = nil,
        extractionConfidence: Double? = nil,
        searchText: String = ""
    ) {
        self.id = id
        self.importedAt = importedAt
        self.updatedAt = updatedAt
        self.reviewedAt = nil
        self.reviewStatusRawValue = reviewStatus.rawValue
        self.importSourceRawValue = importSource.rawValue
        self.processingStateRawValue = processingState.rawValue
        self.processingErrorMessage = nil
        self.merchantName = merchantName
        self.itemDescription = itemDescription
        self.transactionDate = transactionDate
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode
        self.taxAmount = taxAmount
        self.category = category
        self.notes = notes
        self.extractionConfidence = extractionConfidence
        self.searchText = searchText
    }

    var reviewStatus: ReceiptReviewStatus {
        get { ReceiptReviewStatus(rawValue: reviewStatusRawValue) ?? .inbox }
        set { reviewStatusRawValue = newValue.rawValue }
    }

    var importSource: ReceiptImportSource {
        get { ReceiptImportSource(rawValue: importSourceRawValue) ?? .files }
        set { importSourceRawValue = newValue.rawValue }
    }

    var processingState: ReceiptProcessingState {
        get { ReceiptProcessingState(rawValue: processingStateRawValue) ?? .queued }
        set { processingStateRawValue = newValue.rawValue }
    }

    var processingStatusLabel: String {
        switch processingState {
        case .queued:
            return "Queued"
        case .runningOCR:
            return "Reading Text"
        case .ready:
            return reviewStatus == .reviewed ? "Reviewed" : "Ready"
        case .failed:
            return "Needs Retry"
        }
    }

    var displayMerchantName: String {
        if let merchantName, !merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return merchantName
        }

        return asset?.originalFilename ?? "Untitled Receipt"
    }

    func apply(extraction: ReceiptExtraction) {
        if merchantName.isBlank {
            merchantName = extraction.merchantName
        }
        if itemDescription.isBlank {
            itemDescription = extraction.itemDescription
        }
        transactionDate = transactionDate ?? extraction.transactionDate
        totalAmount = totalAmount ?? extraction.totalAmount
        currencyCode = currencyCode ?? extraction.currencyCode
        taxAmount = taxAmount ?? extraction.taxAmount
        category = category ?? extraction.category
        extractionConfidence = extraction.confidence
    }

    func rebuildSearchText() {
        searchText = [
            merchantName,
            itemDescription,
            category,
            notes,
            ocrResult?.rawText
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    func touch() {
        updatedAt = .now
    }
}

private extension Optional where Wrapped == String {
    var isBlank: Bool {
        switch self {
        case .some(let value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .none:
            return true
        }
    }
}
