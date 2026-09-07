import CoreGraphics
import Foundation
import PDFKit
import UniformTypeIdentifiers
@preconcurrency import Vision

enum BankStatementImportError: LocalizedError {
    case unsupportedFile
    case noTransactionsFound

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "PocketPal can import CSV, TSV, TXT, and text-based or scanned PDF bank statements."
        case .noTransactionsFound:
            return "No bank transactions were found in this statement."
        }
    }
}

struct BankStatementTransactionDraft: Hashable, Sendable {
    let accountName: String
    let postedAt: Date
    let descriptionText: String
    let amountHKD: Double
    let suggestedCategory: String?

    var duplicateKey: String {
        let day = Self.keyDateFormatter.string(from: postedAt)
        let normalizedDescription = descriptionText
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9\p{Han}]+"#, with: "", options: .regularExpression)
        return "\(day)|\(normalizedDescription)|\(String(format: "%.2f", amountHKD))"
    }

    private static let keyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct BankStatementImportResult: Sendable {
    let transactions: [BankStatementTransactionDraft]
    let skippedRowCount: Int
}

struct BankStatementImportService: Sendable {
    func parseStatement(at url: URL, accountName: String = "Cash and Bank") async throws -> BankStatementImportResult {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
            return try await parsePDFStatement(at: url, accountName: accountName)
        }

        if type?.conforms(to: .text) == true
            || type?.conforms(to: .commaSeparatedText) == true
            || ["csv", "tsv", "txt"].contains(url.pathExtension.lowercased()) {
            let text = try String(contentsOf: url, encoding: .utf8)
            return parseDelimitedOrPlainText(text, accountName: accountName)
        }

        throw BankStatementImportError.unsupportedFile
    }

    private func parsePDFStatement(at url: URL, accountName: String) async throws -> BankStatementImportResult {
        guard let document = PDFDocument(url: url) else {
            throw BankStatementImportError.unsupportedFile
        }

        var text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")

        if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 {
            text = try await recognizeText(in: document)
        }

        return parseDelimitedOrPlainText(text, accountName: accountName)
    }

    private func parseDelimitedOrPlainText(_ text: String, accountName: String) -> BankStatementImportResult {
        let rows = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let delimited = parseDelimitedRows(rows, accountName: accountName), !delimited.transactions.isEmpty {
            return delimited
        }

        return parsePlainTextRows(rows, accountName: accountName)
    }

    private func parseDelimitedRows(_ rows: [String], accountName: String) -> BankStatementImportResult? {
        guard let first = rows.first else { return nil }
        let delimiter: Character
        if first.contains("\t") {
            delimiter = "\t"
        } else if first.contains(",") {
            delimiter = ","
        } else {
            return nil
        }

        let parsedRows = rows.map { parseDelimitedLine($0, delimiter: delimiter) }
        guard let header = parsedRows.first else { return nil }
        let headerMap = StatementHeaderMap(headers: header)
        let dataRows = headerMap.hasUsefulHeaders ? parsedRows.dropFirst() : parsedRows[...]

        var drafts: [BankStatementTransactionDraft] = []
        var skipped = 0

        for row in dataRows {
            guard let draft = makeDraft(fromDelimitedRow: Array(row), headerMap: headerMap, accountName: accountName) else {
                skipped += 1
                continue
            }
            drafts.append(draft)
        }

        return BankStatementImportResult(transactions: drafts, skippedRowCount: skipped)
    }

    private func makeDraft(fromDelimitedRow row: [String], headerMap: StatementHeaderMap, accountName: String) -> BankStatementTransactionDraft? {
        guard row.count >= 3 else { return nil }

        let dateRaw = value(in: row, at: headerMap.dateIndex) ?? row.first
        let description = value(in: row, at: headerMap.descriptionIndex)
            ?? row.dropFirst().dropLast().joined(separator: " ")
        let amount = signedAmount(in: row, headerMap: headerMap)

        guard let dateRaw,
              let postedAt = parseDate(dateRaw),
              let amount,
              amount != 0 else {
            return nil
        }

        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanDescription.isEmpty, !looksLikeStatementSummary(cleanDescription.lowercased()) else {
            return nil
        }

        return BankStatementTransactionDraft(
            accountName: accountName,
            postedAt: postedAt,
            descriptionText: cleanDescription,
            amountHKD: amount,
            suggestedCategory: suggestedCategory(for: cleanDescription)
        )
    }

    private func parsePlainTextRows(_ rows: [String], accountName: String) -> BankStatementImportResult {
        var drafts: [BankStatementTransactionDraft] = []
        var skipped = 0

        for row in rows {
            let lowered = row.lowercased()
            guard !looksLikeStatementSummary(lowered),
                  let dateMatch = firstDateMatch(in: row),
                  let amountMatch = lastAmountMatch(in: row) else {
                skipped += 1
                continue
            }

            let descriptionStart = dateMatch.range.upperBound
            let descriptionEnd = amountMatch.range.lowerBound
            guard descriptionStart < descriptionEnd else {
                skipped += 1
                continue
            }

            let description = String(row[descriptionStart..<descriptionEnd])
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !description.isEmpty,
                  let postedAt = parseDate(dateMatch.value),
                  let amount = parseSignedAmount(amountMatch.value),
                  amount != 0 else {
                skipped += 1
                continue
            }

            drafts.append(BankStatementTransactionDraft(
                accountName: accountName,
                postedAt: postedAt,
                descriptionText: description,
                amountHKD: amount,
                suggestedCategory: suggestedCategory(for: description)
            ))
        }

        return BankStatementImportResult(transactions: drafts, skippedRowCount: skipped)
    }

    private func parseDelimitedLine(_ line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var isInQuotes = false
        var iterator = line.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if isInQuotes, let next = iterator.next() {
                    if next == "\"" {
                        current.append("\"")
                    } else {
                        isInQuotes = false
                        if next == delimiter {
                            fields.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                            current = ""
                        } else {
                            current.append(next)
                        }
                    }
                } else {
                    isInQuotes.toggle()
                }
            } else if character == delimiter && !isInQuotes {
                fields.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(character)
            }
        }

        fields.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return fields
    }

    private func signedAmount(in row: [String], headerMap: StatementHeaderMap) -> Double? {
        if let amountRaw = value(in: row, at: headerMap.amountIndex),
           let amount = parseSignedAmount(amountRaw) {
            return amount
        }

        let debit = value(in: row, at: headerMap.debitIndex).flatMap(parseUnsignedAmount)
        let credit = value(in: row, at: headerMap.creditIndex).flatMap(parseUnsignedAmount)

        if let credit, credit > 0 { return credit }
        if let debit, debit > 0 { return -debit }

        for value in row.reversed() {
            if let amount = parseSignedAmount(value), amount != 0 {
                return amount
            }
        }

        return nil
    }

    private func value(in row: [String], at index: Int?) -> String? {
        guard let index, row.indices.contains(index) else { return nil }
        let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func parseDate(_ rawValue: String) -> Date? {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[^\dA-Za-z]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^\dA-Za-z]+$"#, with: "", options: .regularExpression)

        if let numericDate = parseNumericDate(value) {
            return numericDate
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.isLenient = false

        for format in ["dd MMM yyyy", "d MMM yyyy", "dd MMM yy", "d MMM yy", "MMM dd yyyy", "MMM d yyyy"] {
            formatter.twoDigitStartDate = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1))
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private func parseNumericDate(_ rawValue: String) -> Date? {
        let components = rawValue
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
            year = normalizedYear(third)
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

    private func normalizedYear(_ year: Int) -> Int {
        guard year < 100 else { return year }
        return year >= 70 ? 1900 + year : 2000 + year
    }

    private func parseSignedAmount(_ rawValue: String) -> Double? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let isParenthesized = trimmed.contains("(") && trimmed.contains(")")
        let isDebitMarked = trimmed.localizedCaseInsensitiveContains("dr")
        let isCreditMarked = trimmed.localizedCaseInsensitiveContains("cr")
        guard let unsigned = parseUnsignedAmount(trimmed) else { return nil }

        if isCreditMarked { return unsigned }
        if isParenthesized || isDebitMarked || trimmed.contains("-") {
            return -unsigned
        }
        return unsigned
    }

    private func parseUnsignedAmount(_ rawValue: String) -> Double? {
        let cleaned = rawValue
            .replacingOccurrences(of: #"[^\d,.\-()]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "-", with: "")
        return AmountParser.parse(cleaned)
    }

    private func firstDateMatch(in line: String) -> (value: String, range: Range<String.Index>)? {
        let patterns = [
            #"\b\d{4}[-/.]\d{1,2}[-/.]\d{1,2}\b"#,
            #"\b\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}\b"#,
            #"\b\d{1,2}\s+[A-Za-z]{3}\s+\d{2,4}\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let swiftRange = Range(match.range, in: line) else {
                continue
            }
            return (String(line[swiftRange]), swiftRange)
        }

        return nil
    }

    private func lastAmountMatch(in line: String) -> (value: String, range: Range<String.Index>)? {
        let pattern = #"(?<!\d)[(]?-?(?:HK\$|US\$|\$)?\s?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{2})[)]?\s?(?:CR|DR)?(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: line) else { return nil }
            return (String(line[swiftRange]), swiftRange)
        }
        .last
    }

    private func looksLikeStatementSummary(_ lowered: String) -> Bool {
        [
            "opening balance", "closing balance", "available balance", "current balance",
            "balance brought forward", "ledger balance", "brought forward",
            "statement", "account number", "page ", "total debit", "total credit",
            "結餘", "月結單", "戶口號碼", "總支出", "總收入"
        ].contains { lowered.contains($0) }
    }

    private func suggestedCategory(for description: String) -> String? {
        ReceiptCategoryClassifier()
            .category(forMerchant: description, rawText: description)?
            .rawValue
    }

    private func recognizeText(in document: PDFDocument) async throws -> String {
        var pageTexts: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index),
                  let image = render(page: page) else {
                continue
            }
            let text = try await recognizeText(in: image)
            if !text.isEmpty {
                pageTexts.append(text)
            }
        }

        return pageTexts.joined(separator: "\n")
    }

    private func render(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let maxPixel: CGFloat = 2_200
        let scale = min(2.0, maxPixel / max(bounds.width, bounds.height))
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        return context.makeImage()
    }

    private func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = OCRPreferences.selectedRecognitionLanguages()
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handler = VNImageRequestHandler(cgImage: image)
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private struct StatementHeaderMap {
    let dateIndex: Int?
    let descriptionIndex: Int?
    let amountIndex: Int?
    let debitIndex: Int?
    let creditIndex: Int?

    init(headers: [String]) {
        let normalized = headers.map(Self.normalize)
        dateIndex = Self.index(in: normalized, matching: ["date", "postingdate", "posteddate", "postdate", "transactiondate", "valuedate", "日期", "交易日期", "入賬日期"])
        descriptionIndex = Self.index(in: normalized, matching: ["description", "transactiondescription", "details", "particulars", "merchant", "payee", "narrative", "narration", "memo", "備註", "描述", "交易詳情", "詳情"])
        amountIndex = Self.index(in: normalized, matching: ["amount", "transactionamount", "hkdamount", "金額", "交易金額"])
        debitIndex = Self.index(in: normalized, matching: ["debit", "debits", "withdrawal", "withdrawals", "moneyout", "paidout", "payment", "支出", "提款", "扣賬", "付款"])
        creditIndex = Self.index(in: normalized, matching: ["credit", "credits", "deposit", "deposits", "moneyin", "paidin", "receipt", "receipts", "收入", "存入", "入賬"])
    }

    var hasUsefulHeaders: Bool {
        dateIndex != nil && descriptionIndex != nil && (amountIndex != nil || debitIndex != nil || creditIndex != nil)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9\p{Han}]+"#, with: "", options: .regularExpression)
            .lowercased()
    }

    private static func index(in headers: [String], matching candidates: [String]) -> Int? {
        headers.firstIndex { header in
            candidates.contains { candidate in
                header == normalize(candidate) || header.contains(normalize(candidate))
            }
        }
    }
}
