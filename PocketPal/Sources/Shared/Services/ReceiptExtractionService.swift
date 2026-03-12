import Foundation

protocol ReceiptExtracting {
    func extractFields(from rawText: String) -> ReceiptExtraction
}

struct ReceiptExtractionService: ReceiptExtracting {
    func extractFields(from rawText: String) -> ReceiptExtraction {
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let merchantName = extractMerchantName(from: lines)
        let transactionDate = extractDate(from: rawText)
        let currencyCode = extractCurrency(from: rawText)
        let totalAmount = extractAmount(
            from: lines,
            keywords: ["grand total", "amount due", "total due", "total", "balance due"]
        ) ?? largestAmount(in: lines)
        let taxAmount = extractAmount(from: lines, keywords: ["tax", "vat", "gst"])
        let confidence = extractionConfidence(
            merchantName: merchantName,
            transactionDate: transactionDate,
            totalAmount: totalAmount,
            currencyCode: currencyCode,
            taxAmount: taxAmount
        )

        return ReceiptExtraction(
            merchantName: merchantName,
            transactionDate: transactionDate,
            totalAmount: totalAmount,
            currencyCode: currencyCode,
            taxAmount: taxAmount,
            category: nil,
            confidence: confidence
        )
    }

    private func extractMerchantName(from lines: [String]) -> String? {
        lines.first(where: { line in
            let lowered = line.lowercased()
            let containsLetters = line.rangeOfCharacter(from: .letters) != nil
            let containsMostlyDigits = line.filter(\.isNumber).count > line.count / 2
            let looksLikeMetadata = lowered.contains("receipt") || lowered.contains("invoice") || lowered.contains("tax")
            return containsLetters && !containsMostlyDigits && !looksLikeMetadata
        })
    }

    private func extractDate(from rawText: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }

        let range = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
        return detector.matches(in: rawText, options: [], range: range).compactMap(\.date).first
    }

    private func extractCurrency(from rawText: String) -> String? {
        let uppercased = rawText.uppercased()
        let codes = ["USD", "EUR", "GBP", "HKD", "JPY", "CNY", "RMB", "AUD", "CAD", "SGD"]
        if let code = codes.first(where: uppercased.contains) {
            return code == "RMB" ? "CNY" : code
        }

        if rawText.contains("HK$") { return "HKD" }
        if rawText.contains("US$") || rawText.contains("$") { return "USD" }
        if rawText.contains("€") { return "EUR" }
        if rawText.contains("£") { return "GBP" }
        if rawText.contains("¥") { return "JPY" }

        return nil
    }

    private func extractAmount(from lines: [String], keywords: [String]) -> Double? {
        let keywordSet = keywords.map { $0.lowercased() }
        let matchingLines = lines.filter { line in
            let lowered = line.lowercased()
            return keywordSet.contains(where: lowered.contains)
        }

        for line in matchingLines {
            if let amount = amounts(in: line).last {
                return amount
            }
        }

        return nil
    }

    private func largestAmount(in lines: [String]) -> Double? {
        lines.flatMap(amounts).max()
    }

    private func amounts(in line: String) -> [Double] {
        let pattern = #"-?\d{1,3}(?:[,\s]\d{3})*(?:[.,]\d{2})|-?\d+(?:[.,]\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)

        return regex.matches(in: line, options: [], range: range)
            .compactMap { match in
                guard let range = Range(match.range, in: line) else { return nil }
                return AmountParser.parse(String(line[range]))
            }
    }

    private func extractionConfidence(
        merchantName: String?,
        transactionDate: Date?,
        totalAmount: Double?,
        currencyCode: String?,
        taxAmount: Double?
    ) -> Double {
        let hits = [
            merchantName != nil,
            transactionDate != nil,
            totalAmount != nil,
            currencyCode != nil,
            taxAmount != nil
        ]
        .filter { $0 }
        .count

        return Double(hits) / 5.0
    }
}
