import Foundation

struct ReceiptReadinessIssue: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
}

struct ReceiptTaxReadiness {
    let receipt: Receipt

    var fieldIssues: [ReceiptReadinessIssue] {
        ReceiptReviewRequirements(receipt: receipt).issues
    }

    var issues: [ReceiptReadinessIssue] {
        var result = fieldIssues
        if receipt.reviewStatus != .reviewed {
            result.append(.init(id: "review", title: "Not confirmed",
                                detail: "Check the receipt details and confirm before export.",
                                systemImage: "checkmark.circle"))
        }
        return result
    }

    var isReadyForTaxExport: Bool {
        receipt.transactionKind == .expense && receipt.expenseType.isTaxDeductible && !receipt.finance.isTemplate && receipt.finance.treatment == .regular && receipt.finance.matchedRecord == nil && issues.isEmpty
    }

    var readinessLabel: String {
        isReadyForTaxExport ? "Tax Ready" : "Not ready"
    }

    var suggestedTaxCategory: TaxCategory {
        if let category = receipt.taxCategory {
            return category
        }

        let normalized = (receipt.category ?? "").lowercased()
        if normalized.contains("meal") || normalized.contains("dining") || normalized.contains("餐") {
            return .meals
        }
        if normalized.contains("travel") || normalized.contains("transport") || normalized.contains("lodging") || normalized.contains("交通") {
            return .travel
        }
        if normalized.contains("office") || normalized.contains("stationery") {
            return .office
        }
        if normalized.contains("equipment") {
            return .equipment
        }
        if normalized.contains("utilit") {
            return .utilities
        }
        if receipt.expenseType.isTaxDeductible {
            return .deductible
        }
        return .nonDeductible
    }
}

extension Receipt {
    var taxReadiness: ReceiptTaxReadiness {
        ReceiptTaxReadiness(receipt: self)
    }
}

struct ReceiptReviewRequirements {
    var processingState: ReceiptProcessingState
    var merchantName: String?
    var transactionDate: Date?
    var totalAmount: Double?
    var category: String?
    var isTaxExportCandidate: Bool
    var taxCategory: TaxCategory?
    var hasAttachment: Bool

    init(receipt: Receipt) {
        processingState = receipt.processingState
        merchantName = receipt.merchantName
        transactionDate = receipt.transactionDate
        totalAmount = receipt.totalAmount
        category = receipt.category
        isTaxExportCandidate = receipt.transactionKind == .expense && receipt.expenseType.isTaxDeductible
        taxCategory = receipt.taxCategory
        hasAttachment = !receipt.allEvidence.isEmpty
    }

    var issues: [ReceiptReadinessIssue] {
        var issues: [ReceiptReadinessIssue] = []

        if processingState != .ready {
            issues.append(.init(
                id: "processing",
                title: "Processing incomplete",
                detail: "Finish OCR or resolve the import error before export.",
                systemImage: "hourglass"
            ))
        }

        if merchantName.isNilOrBlank {
            issues.append(.init(
                id: "merchant",
                title: "Missing merchant",
                detail: "Add the supplier or merchant name.",
                systemImage: "storefront"
            ))
        }

        if transactionDate == nil {
            issues.append(.init(
                id: "date",
                title: "Missing date",
                detail: "Add the transaction date for tax-year reporting.",
                systemImage: "calendar"
            ))
        }

        if totalAmount == nil || totalAmount?.isFinite == false {
            issues.append(.init(
                id: "amount",
                title: "Missing amount",
                detail: "Add the total paid amount.",
                systemImage: "banknote"
            ))
        }

        if category.isNilOrBlank {
            issues.append(.init(
                id: "category",
                title: "Missing category",
                detail: "Choose a spending category.",
                systemImage: "tag"
            ))
        }

        if isTaxExportCandidate, taxCategory == nil {
            issues.append(.init(
                id: "taxCategory",
                title: "Missing tax category",
                detail: "Choose how this expense should appear in tax exports.",
                systemImage: "checklist"
            ))
        }

        if isTaxExportCandidate, !hasAttachment {
            issues.append(.init(
                id: "proof",
                title: "No receipt attached",
                detail: "Attach the original receipt before export.",
                systemImage: "doc.badge.plus"
            ))
        }

        // Narrow guardrail: a receipt dated clearly in the future is misleading
        // for tax/export purposes. Allow a 1-day grace window to tolerate
        // timezone edge cases around midnight.
        if let transactionDate = transactionDate,
           let graceDeadline = Calendar.current.date(byAdding: .day, value: 1, to: .now),
           transactionDate > graceDeadline {
            issues.append(.init(
                id: "futureDate",
                title: "Future-dated receipt",
                detail: "Receipts dated in the future are excluded from tax export. Correct the date before exporting.",
                systemImage: "calendar.badge.exclamationmark"
            ))
        }

        return issues
    }

}

private extension Optional where Wrapped == String {
    var isNilOrBlank: Bool {
        switch self {
        case .none:
            return true
        case .some(let value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// Only the editable fields. No model copies, file writes or whole-context rollback.
struct ReceiptReviewValues: Equatable {
    var merchantName: String?
    var itemDescription: String?
    var transactionDate: Date?
    var totalAmount: Double?
    var currencyCode: String?
    var taxAmount: Double?
    var category: String?
    var notes: String?
    var transactionKindRawValue: String?
    var expenseTypeRawValue: String
    var taxCategoryRawValue: String?

    init(receipt: Receipt) {
        merchantName = receipt.merchantName
        itemDescription = receipt.itemDescription
        transactionDate = receipt.transactionDate
        totalAmount = receipt.totalAmount
        currencyCode = receipt.currencyCode
        taxAmount = receipt.taxAmount
        category = receipt.category
        notes = receipt.notes
        transactionKindRawValue = receipt.transactionKindRawValue
        expenseTypeRawValue = receipt.expenseTypeRawValue
        taxCategoryRawValue = receipt.taxCategoryRawValue
    }

    func apply(to receipt: Receipt) {
        receipt.merchantName = merchantName
        receipt.itemDescription = itemDescription
        receipt.transactionDate = transactionDate
        receipt.totalAmount = totalAmount
        receipt.currencyCode = currencyCode
        receipt.taxAmount = taxAmount
        receipt.category = category
        receipt.notes = notes
        receipt.transactionKindRawValue = transactionKindRawValue
        receipt.expenseTypeRawValue = expenseTypeRawValue
        receipt.taxCategoryRawValue = taxCategoryRawValue
    }
}

@MainActor
enum ReceiptReviewPersistence {
    enum ReviewError: LocalizedError {
        case incomplete
        var errorDescription: String? { "資料未齊，請補齊後再確認。" }
    }

    static func save(receipt: Receipt, values: ReceiptReviewValues, confirmed: Bool,
                     persist: () throws -> Void) throws {
        let previous = ReceiptReviewValues(receipt: receipt)
        let previousStatus = receipt.reviewStatusRawValue
        let previousReviewedAt = receipt.reviewedAt
        let previousUpdatedAt = receipt.updatedAt
        let previousSearchText = receipt.searchText
        let previousFinance = receipt.financeMetadataJSON
        do {
            values.apply(to: receipt)
            if receipt.finance.payroll != nil && values.totalAmount != previous.totalAmount {
                throw FinanceWorkflowError.invalid("人工金額請在付款、附件、項目及審批頁的人工欄位修改，以保持應發及僱主成本一致。")
            }
            if receipt.finance.tracksPayments && receipt.faceAmount < receipt.paidAmount {
                throw FinanceWorkflowError.invalid("總金額不可少於已記錄付款；請先核對或更正付款紀錄。")
            }
            if !receipt.finance.payments.isEmpty && (values.currencyCode != previous.currencyCode || values.transactionKindRawValue != previous.transactionKindRawValue) {
                throw FinanceWorkflowError.invalid("已有付款紀錄，不能直接改變貨幣或收支方向。")
            }
            if confirmed && !ReceiptReviewRequirements(receipt: receipt).issues.isEmpty {
                throw ReviewError.incomplete
            }
            receipt.reviewStatus = confirmed ? .reviewed : .inbox
            receipt.reviewedAt = confirmed ? .now : nil
            receipt.touch()
            receipt.rebuildSearchText()
            var metadata = receipt.finance
            metadata.audit.append(FinanceAudit(actor: "本機使用者", action: "\(confirmed ? "確認" : "修改")原始資料；金額 \(previous.totalAmount.map(String.init(describing:)) ?? "空白") → \(values.totalAmount.map(String.init(describing:)) ?? "空白")；商戶 \(previous.merchantName ?? "") → \(values.merchantName ?? "")"))
            if previous != values && metadata.approval == "已批准" { metadata.approval = "待審批" }
            receipt.finance = metadata
            try persist()
        } catch {
            previous.apply(to: receipt)
            receipt.reviewStatusRawValue = previousStatus
            receipt.reviewedAt = previousReviewedAt
            receipt.updatedAt = previousUpdatedAt
            receipt.searchText = previousSearchText
            receipt.financeMetadataJSON = previousFinance
            throw error
        }
    }
}
