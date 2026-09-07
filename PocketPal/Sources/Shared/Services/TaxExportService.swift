import Foundation

struct TaxReportSummary {
    let receiptCount: Int
    let readyCount: Int
    let needsReviewCount: Int
    let deductibleTotalHKD: Double
    let reimbursableTotalHKD: Double
}

enum TaxExportService {
    static func summary(for receipts: [Receipt]) -> TaxReportSummary {
        TaxReportSummary(
            receiptCount: receipts.count,
            readyCount: receipts.filter(\.taxReadiness.isReadyForTaxExport).count,
            needsReviewCount: receipts.filter { !$0.taxReadiness.isReadyForTaxExport }.count,
            deductibleTotalHKD: receipts
                .filter { $0.expenseType == .business }
                .compactMap(\.amountInHKD)
                .reduce(0, +),
            reimbursableTotalHKD: receipts
                .filter { $0.expenseType == .reimbursable }
                .compactMap(\.amountInHKD)
                .reduce(0, +)
        )
    }

    /// Formal export enforces readiness here, even if a caller supplies unfiltered rows.
    static func makeConfirmedTaxCSVData(receipts: [Receipt]) -> Data {
        makeTaxCSVData(receipts: receipts.filter(\.taxReadiness.isReadyForTaxExport))
    }

    /// Full-ledger export retains incomplete records and labels their status.
    static func makeTaxCSVData(receipts: [Receipt]) -> Data {
        let rows = [
            TaxCSVRow.header
        ] + receipts.map { TaxCSVRow(receipt: $0).fields }

        let csv = "\u{FEFF}" + rows
            .map { $0.map(csvEscapedField).joined(separator: ",") }
            .joined(separator: "\n")

        return Data(csv.utf8)
    }

    static func taxYearInterval(referenceDate: Date = .now, startMonth: Int = AppPreferences.taxYearStartMonth) -> DateInterval? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: referenceDate)
        let month = calendar.component(.month, from: referenceDate)
        let startYear = month >= startMonth ? year : year - 1

        guard let start = calendar.date(from: DateComponents(year: startYear, month: startMonth, day: 1)),
              let end = calendar.date(byAdding: .year, value: 1, to: start) else {
            return nil
        }

        return DateInterval(start: start, end: end)
    }

    private static func csvEscapedField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }

        return escaped
    }
}

private struct TaxCSVRow {
    static let header = [
        "Tax Ready",
        "Missing Items",
        "Transaction Date",
        "Merchant",
        "Description",
        "Amount",
        "Currency",
        "Amount HKD",
        "Tax Amount",
        "Expense Type",
        "Tax Category",
        "Category",
        "Review Status",
        "Import Source",
        "Notes",
        "Receipt ID"
    ]

    let fields: [String]

    init(receipt: Receipt) {
        let readiness = receipt.taxReadiness
        let missingItems = readiness.issues.map(\.title).joined(separator: "; ")

        fields = [
            readiness.isReadyForTaxExport ? "Yes" : "No",
            missingItems,
            receipt.transactionDate.map { Self.dateFormatter.string(from: $0) } ?? "",
            receipt.merchantName ?? "",
            receipt.itemDescription ?? "",
            Self.amountFormatter.string(from: NSNumber(value: receipt.totalAmount ?? 0)).flatMap { receipt.totalAmount == nil ? "" : $0 } ?? "",
            receipt.resolvedCurrency.rawValue,
            Self.amountFormatter.string(from: NSNumber(value: receipt.amountInHKD ?? 0)).flatMap { receipt.amountInHKD == nil ? "" : $0 } ?? "",
            Self.amountFormatter.string(from: NSNumber(value: receipt.taxAmount ?? 0)).flatMap { receipt.taxAmount == nil ? "" : $0 } ?? "",
            receipt.expenseType.displayName,
            receipt.taxCategory?.displayName ?? "",
            receipt.category ?? "",
            receipt.reviewStatus.rawValue,
            receipt.importSource.rawValue,
            receipt.notes ?? "",
            receipt.id.uuidString
        ]
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter
    }()
}
