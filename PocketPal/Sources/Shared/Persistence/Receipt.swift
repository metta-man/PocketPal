import Foundation
import SwiftData

@Model
final class Receipt {
    var id: UUID
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

    // MARK: - Expense Classification (for tax/business use)
    var expenseTypeRawValue: String
    var taxCategoryRawValue: String?

    // MARK: - Source Tracking (for email/ecommerce imports)
    var sourceProviderRawValue: String?
    var sourceOrderID: String?
    var sourceEmailID: String?

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
        searchText: String = "",
        expenseType: ExpenseType = .personal,
        taxCategory: TaxCategory? = nil,
        sourceProvider: ConnectionProvider? = nil,
        sourceOrderID: String? = nil,
        sourceEmailID: String? = nil
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
        self.expenseTypeRawValue = expenseType.rawValue
        self.taxCategoryRawValue = taxCategory?.rawValue
        self.sourceProviderRawValue = sourceProvider?.rawValue
        self.sourceOrderID = sourceOrderID
        self.sourceEmailID = sourceEmailID
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

    var expenseType: ExpenseType {
        get { ExpenseType(rawValue: expenseTypeRawValue) ?? .personal }
        set { expenseTypeRawValue = newValue.rawValue }
    }

    var taxCategory: TaxCategory? {
        get {
            guard let raw = taxCategoryRawValue else { return nil }
            return TaxCategory(rawValue: raw)
        }
        set { taxCategoryRawValue = newValue?.rawValue }
    }

    var sourceProvider: ConnectionProvider? {
        get {
            guard let raw = sourceProviderRawValue else { return nil }
            return ConnectionProvider(rawValue: raw)
        }
        set { sourceProviderRawValue = newValue?.rawValue }
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

    var resolvedCurrency: Currency {
        Currency.from(code: currencyCode) ?? AppPreferences.defaultCurrency
    }

    var amountInHKD: Double? {
        guard let totalAmount else { return nil }
        return ExchangeRateTable.convertToHKD(amount: totalAmount, from: resolvedCurrency)
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
            expenseType.displayName,
            taxCategory?.displayName,
            sourceProvider?.displayName,
            sourceOrderID,
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
