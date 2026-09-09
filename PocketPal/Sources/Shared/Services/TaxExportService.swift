import Foundation
import UniformTypeIdentifiers

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
        let leading = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let isNumber = value.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil
        let safe = !isNumber && leading.map { "=+-@".contains($0) } == true ? "'" + value : value
        let escaped = safe.replacingOccurrences(of: "\"", with: "\"\"")
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

/// Portable ledger delivery; independent of tax eligibility and never mutates receipts.
enum ReceiptDeliveryPackage {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        return value
    }

    static func select(_ receipts: [Receipt], ledger: ReceiptLedger, start: Date, end: Date,
                       includeUndated: Bool, confirmedOnly: Bool) -> [Receipt] {
        let lower = calendar.startOfDay(for: start)
        guard let upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)),
              lower < upper else { return [] }
        return receipts.filter { receipt in
            guard ledger.includes(receipt), !confirmedOnly || receipt.reviewStatus == .reviewed else { return false }
            let hasPayment = receipt.finance.payments.contains { $0.date >= lower && $0.date < upper }
            guard let date = receipt.transactionDate else { return includeUndated || hasPayment }
            return date >= lower && date < upper || hasPayment
        }
    }

    static func issues(for receipt: Receipt, fileURL: (String) -> URL) -> [String] {
        var result: [String] = []
        if receipt.transactionDate == nil { result.append("欠交易日期") }
        if receipt.totalAmount == nil || receipt.totalAmount?.isFinite == false { result.append("欠有效金額") }
        if receipt.reviewStatus != .reviewed { result.append("未確認") }
        if receipt.allEvidence.isEmpty { result.append("未附證明（請確認是否需要）") }
        for evidence in receipt.allEvidence {
            if !FileManager.default.isReadableFile(atPath: fileURL(evidence.path).path) { result.append("原始附件無法讀取：" + evidence.name) }
        }
        if receipt.finance.tracksPayments && receipt.outstanding > 0 { result.append("仍有未收／未付款：" + receipt.outstanding.description) }
        if receipt.finance.matchedRecord != nil { result.append("已匹配另一筆紀錄，未再計入收支") }
        return result
    }

    static func csv(_ rows: [[String]]) -> Data {
        let text = rows.map { row in
            row.map { value in
                // Neutralize spreadsheet formulas in user-provided fields.
                let leading = value.trimmingCharacters(in: .whitespacesAndNewlines).first
                let isNumber = value.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil
                let safe = !isNumber && leading.map { "=+-@".contains($0) } == true ? "'" + value : value
                return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }.joined(separator: ",")
        }.joined(separator: "\r\n")
        return Data(("\u{FEFF}" + text).utf8)
    }

    static func make(receipts: [Receipt], scope: String, excludedCount: Int, start: Date? = nil, end: Date? = nil,
                     fileURL: (String) -> URL) throws -> FileWrapper {
        var rows = [["紀錄 ID", "類型", "交易日期", "商戶／付款人", "描述", "金額", "貨幣", "分類", "確認狀態", "附件路徑", "備註", "款項性質", "已收／已付", "未收／未付", "客戶", "項目", "代墊人", "戶口", "審批", "工時", "所需文件"]]
        var payments = [["紀錄 ID", "付款日期", "金額", "貨幣", "參考"]]
        var audit = [["紀錄 ID", "時間", "操作人", "動作"]]
        var evidenceIndex = [["紀錄 ID", "附件 ID", "原名", "包內路徑"]]
        var payrollRows = [["紀錄 ID", "員工", "月份", "應發", "員工扣款", "僱主成本", "貨幣"]]
        var projectTotals: [String: (income: Decimal, expense: Decimal)] = [:]
        var missing = [["紀錄 ID", "商戶／付款人", "待處理項目"]]
        var files: [String: FileWrapper] = [:]
        var totals: [String: (income: Decimal, expense: Decimal)] = [:]
        var monthly: [String: (income: Decimal, expense: Decimal)] = [:]
        var issueCount = 0
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        for receipt in receipts {
            var path = ""
            var problems = issues(for: receipt, fileURL: fileURL)
            for (index, evidence) in receipt.allEvidence.enumerated() {
                let url = fileURL(evidence.path)
                let ext = evidence.type == UTType.jpeg.identifier ? "jpg" : (UTType(evidence.type)?.preferredFilenameExtension ?? "bin")
                let name = receipt.id.uuidString + (index == 0 ? "" : "-" + evidence.id.uuidString) + "." + ext
                do {
                    let data = try Data(contentsOf: url)
                    files[name] = FileWrapper(regularFileWithContents: data)
                    let relative = "Attachments/" + name
                    path += (path.isEmpty ? "" : "; ") + relative
                    evidenceIndex.append([receipt.id.uuidString, evidence.id.uuidString, evidence.name, relative])
                } catch { problems.append("原始附件無法讀取：" + evidence.name) }
            }
            if !problems.isEmpty {
                issueCount += 1
                missing.append([receipt.id.uuidString, receipt.displayMerchantName, problems.joined(separator: "；")])
            }
            let currency = receipt.currencyCode ?? receipt.resolvedCurrency.rawValue
            let amount = receipt.totalAmount.flatMap { $0.isFinite ? $0 : nil }
            for entry in receipt.cashEntries(start: start, end: end) {
                var total = totals[currency] ?? (0, 0)
                total.income += entry.income; total.expense += entry.expense
                totals[currency] = total
                let month = entry.date.map { String(formatter.string(from: $0).prefix(7)) } ?? "無日期"
                let key = month + " / " + currency
                var monthTotal = monthly[key] ?? (0, 0)
                monthTotal.income += entry.income; monthTotal.expense += entry.expense
                monthly[key] = monthTotal
                let projectKey = (receipt.finance.project.isEmpty ? "未分項目" : receipt.finance.project) + " / " + currency
                var projectTotal = projectTotals[projectKey] ?? (0, 0)
                projectTotal.income += entry.income; projectTotal.expense += entry.expense
                projectTotals[projectKey] = projectTotal
            }
            for payment in receipt.finance.payments {
                payments.append([receipt.id.uuidString, formatter.string(from: payment.date), payment.amount.description, currency, payment.reference])
            }
            for entry in receipt.finance.audit { audit.append([receipt.id.uuidString, ISO8601DateFormatter().string(from: entry.date), entry.actor, entry.action]) }
            if let payroll = receipt.finance.payroll {
                payrollRows.append([receipt.id.uuidString, payroll.employee, payroll.month, payroll.gross.description, payroll.deductions.description, payroll.employerCost.description, currency])
            }
            rows.append([receipt.id.uuidString, receipt.transactionKind.displayName,
                         receipt.transactionDate.map(formatter.string) ?? "", receipt.merchantName ?? "",
                         receipt.itemDescription ?? "", amount.map { String($0) } ?? "", currency,
                         receipt.category ?? "", receipt.reviewStatus.rawValue, path, receipt.notes ?? "",
                         receipt.finance.treatment.rawValue, receipt.paidAmount.description, receipt.outstanding.description,
                         receipt.finance.client, receipt.finance.project, receipt.finance.paidBy, receipt.finance.account,
                         receipt.finance.approval, receipt.finance.hours?.description ?? "", receipt.finance.requiredDocuments.joined(separator: "; ")])
        }
        var summary = "PocketPal 收支紀錄包\n\(scope)\n匯出：\(receipts.count) 筆；排除：\(excludedCount) 筆\n有待處理項目：\(issueCount) 筆\n"
        for currency in totals.keys.sorted() {
            guard let value = totals[currency] else { continue }
            summary += "\n\(currency)：收入 \(value.income)，支出 \(value.expense)，淨收支 \(value.income - value.expense)\n"
        }
        var monthlyRows = [["月份／貨幣", "收入", "支出", "淨收支"]]
        for key in monthly.keys.sorted() {
            guard let value = monthly[key] else { continue }
            monthlyRows.append([key, "\(value.income)", "\(value.expense)", "\(value.income - value.expense)"])
        }
        var projectRows = [["項目／貨幣", "已收", "已付", "淨收支"]]
        for key in projectTotals.keys.sorted() {
            let value = projectTotals[key]!
            projectRows.append([key, value.income.description, value.expense.description, (value.income - value.expense).description])
        }
        summary += "\n摘要按實際付款日期加總；未追蹤付款的舊紀錄沿用交易日期及全額。轉帳、注資、借貸本金及歸還墊支不計入營業收支；退款抵減原收支。付款明細列出所選紀錄的全部付款以供追溯，摘要只計指定期間。\n"
        summary += "\n金額按原幣分開加總；欠有效金額的紀錄不計入合計。淨收支並非應課稅利潤。\n請查看 missing-items.csv；未附證明不一定代表不合資格。此資料包不代表完整資助申請或經審核帳目。\n"
        return FileWrapper(directoryWithFileWrappers: [
            "payments.csv": FileWrapper(regularFileWithContents: csv(payments)),
            "audit.csv": FileWrapper(regularFileWithContents: csv(audit)),
            "evidence-index.csv": FileWrapper(regularFileWithContents: csv(evidenceIndex)),
            "payroll.csv": FileWrapper(regularFileWithContents: csv(payrollRows)),
            "project-summary.csv": FileWrapper(regularFileWithContents: csv(projectRows)),
            "monthly-summary.csv": FileWrapper(regularFileWithContents: csv(monthlyRows)),
            "receipts.csv": FileWrapper(regularFileWithContents: csv(rows)),
            "missing-items.csv": FileWrapper(regularFileWithContents: csv(missing)),
            "README.txt": FileWrapper(regularFileWithContents: Data(summary.utf8)),
            "Attachments": FileWrapper(directoryWithFileWrappers: files)
        ])
    }
}
