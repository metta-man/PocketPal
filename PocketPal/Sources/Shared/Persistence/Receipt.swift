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
    var financeMetadataJSON: String?
    var transactionKindRawValue: String?
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
    var extractionProviderRawValue: String?
    var extractionDecisionRawValue: String?
    var cloudExtractionAttemptedAt: Date?
    var cloudExtractionErrorMessage: String?
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
        transactionKind: TransactionKind = .expense,
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
        extractionProvider: ReceiptExtractionProvider? = nil,
        extractionDecision: ReceiptExtractionDecision? = nil,
        cloudExtractionAttemptedAt: Date? = nil,
        cloudExtractionErrorMessage: String? = nil,
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
        self.transactionKindRawValue = transactionKind.rawValue
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
        self.extractionProviderRawValue = extractionProvider?.rawValue
        self.extractionDecisionRawValue = extractionDecision?.rawValue
        self.cloudExtractionAttemptedAt = cloudExtractionAttemptedAt
        self.cloudExtractionErrorMessage = cloudExtractionErrorMessage
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

    var transactionKind: TransactionKind {
        get { TransactionKind(rawValue: transactionKindRawValue ?? "") ?? .expense }
        set { transactionKindRawValue = newValue.rawValue }
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

    var extractionProvider: ReceiptExtractionProvider? {
        get {
            guard let raw = extractionProviderRawValue else { return nil }
            return ReceiptExtractionProvider(rawValue: raw)
        }
        set { extractionProviderRawValue = newValue?.rawValue }
    }

    var extractionDecision: ReceiptExtractionDecision? {
        get {
            guard let raw = extractionDecisionRawValue else { return nil }
            return ReceiptExtractionDecision(rawValue: raw)
        }
        set { extractionDecisionRawValue = newValue?.rawValue }
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

    var signedAmountInHKD: Double? {
        guard totalAmount != nil else { return nil }
        return cashIncomeHKD - cashExpenseHKD
    }

    func apply(extraction: ReceiptExtraction) {
        let previousValues = ReceiptReviewValues(receipt: self)
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
        extractionProvider = extraction.primaryProvider
        extractionDecision = extraction.decision
        if ReceiptReviewValues(receipt: self) != previousValues {
            reviewStatus = .inbox
            reviewedAt = nil
        }
    }

    func rebuildSearchText() {
        searchText = [
            merchantName,
            itemDescription,
            category,
            notes,
            transactionKind.displayName,
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

/// Reclassifies the confirmed batch in place, retaining assets and OCR relationships.
@MainActor
enum ReceiptBusinessTransfer {
    @discardableResult
    static func move(_ receipts: [Receipt], persist: () throws -> Void) throws -> Int {
        var seen = Set<UUID>()
        let candidates = receipts.filter {
            !$0.isDeleted && $0.expenseType == .personal && seen.insert($0.id).inserted
        }
        let snapshots = candidates.map {
            (receipt: $0, expenseType: $0.expenseTypeRawValue, status: $0.reviewStatusRawValue,
             reviewedAt: $0.reviewedAt, updatedAt: $0.updatedAt, searchText: $0.searchText)
        }
        guard !candidates.isEmpty else { return 0 }
        do {
            for receipt in candidates {
                receipt.expenseType = .business
                receipt.reviewStatus = .inbox
                receipt.reviewedAt = nil
                receipt.touch()
                receipt.rebuildSearchText()
            }
            try persist()
            return candidates.count
        } catch {
            // Restore only fields touched here; preserve unrelated context edits.
            for snapshot in snapshots {
                snapshot.receipt.expenseTypeRawValue = snapshot.expenseType
                snapshot.receipt.reviewStatusRawValue = snapshot.status
                snapshot.receipt.reviewedAt = snapshot.reviewedAt
                snapshot.receipt.updatedAt = snapshot.updatedAt
                snapshot.receipt.searchText = snapshot.searchText
            }
            throw error
        }
    }
}
