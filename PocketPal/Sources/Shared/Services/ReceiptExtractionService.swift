import Foundation

protocol ReceiptExtracting {
    func extractFields(from rawText: String) -> ReceiptExtraction
}

struct ReceiptExtractionService: ReceiptExtracting {
    private let categoryClassifier = ReceiptCategoryClassifier()

    func extractFields(from rawText: String) -> ReceiptExtraction {
        let lines = normalizedLines(from: rawText)
        let merchant = extractMerchantName(from: lines)
        let itemDescription = extractItemDescription(from: lines, merchantName: merchant.value)
        let transactionDate = extractDate(from: rawText)
        let currency = extractCurrency(from: rawText)
        let total = extractTotalAmount(from: lines)
        let tax = extractAmount(from: lines, keywords: ["tax", "vat", "gst", "稅", "增值稅", "消費稅"])
        let category = categoryClassifier.category(forMerchant: merchant.value, rawText: rawText)?.rawValue

        var fieldConfidences: [ReceiptExtractionField: Double] = [:]
        var fieldSources: [ReceiptExtractionField: ReceiptExtractionProvider] = [:]

        func record(_ field: ReceiptExtractionField, valueExists: Bool, confidence: Double) {
            guard valueExists else { return }
            fieldConfidences[field] = confidence
            fieldSources[field] = .localRules
        }

        record(.merchantName, valueExists: merchant.value != nil, confidence: merchant.confidence)
        record(.itemDescription, valueExists: itemDescription.value != nil, confidence: itemDescription.confidence)
        record(.transactionDate, valueExists: transactionDate.value != nil, confidence: transactionDate.confidence)
        record(.totalAmount, valueExists: total.value != nil, confidence: total.confidence)
        record(.currencyCode, valueExists: currency.value != nil, confidence: currency.confidence)
        record(.taxAmount, valueExists: tax.value != nil, confidence: tax.confidence)
        record(.category, valueExists: category != nil, confidence: 0.62)

        let confidence = extractionConfidence(
            merchantConfidence: merchant.value == nil ? 0 : merchant.confidence,
            dateConfidence: transactionDate.value == nil ? 0 : transactionDate.confidence,
            totalConfidence: total.value == nil ? 0 : total.confidence,
            currencyConfidence: currency.value == nil ? 0 : currency.confidence,
            categoryConfidence: category == nil ? 0 : 0.62,
            itemConfidence: itemDescription.value == nil ? 0 : itemDescription.confidence
        )
        let decision = ReceiptExtraction.confidenceDecision(
            merchantName: merchant.value,
            transactionDate: transactionDate.value,
            totalAmount: total.value,
            confidence: confidence
        )

        return ReceiptExtraction(
            merchantName: merchant.value,
            itemDescription: itemDescription.value,
            transactionDate: transactionDate.value,
            totalAmount: total.value,
            currencyCode: currency.value,
            taxAmount: tax.value,
            category: category,
            confidence: confidence,
            decision: decision,
            providers: [.visionOCR, .localRules],
            fieldConfidences: fieldConfidences,
            fieldSources: fieldSources
        )
        .validated()
    }

    private func normalizedLines(from rawText: String) -> [String] {
        rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func extractMerchantName(from lines: [String]) -> (value: String?, confidence: Double) {
        let candidates = lines.prefix(10).enumerated().compactMap { offset, line -> (String, Double)? in
            let lowered = line.lowercased()
            guard line.rangeOfCharacter(from: .letters) != nil else { return nil }
            guard !isMostlyDigits(line) else { return nil }
            guard !looksLikeReceiptMetadata(lowered) else { return nil }
            guard !looksLikeAddressOrContact(lowered) else { return nil }
            guard !amounts(in: line).contains(where: { $0 > 0 }) else { return nil }

            var score = 0.72
            if line.count <= 34 { score += 0.08 }
            if containsKnownHongKongMerchant(lowered) { score += 0.12 }
            if containsBusinessKeyword(lowered) { score += 0.14 }
            if uppercaseLetterRatio(in: line) > 0.5 { score += 0.08 }
            if lowered == line && !containsBusinessKeyword(lowered) { score -= 0.2 }
            score -= Double(offset) * 0.02
            return (cleanMerchant(line), min(score, 0.94))
        }

        return candidates.max(by: { $0.1 < $1.1 }) ?? (nil, 0)
    }

    private func extractItemDescription(from lines: [String], merchantName: String?) -> (value: String?, confidence: Double) {
        let normalizedMerchant = merchantName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        for line in lines.dropFirst().prefix(14) {
            let lowered = line.lowercased()
            let containsLetters = line.rangeOfCharacter(from: .letters) != nil
            let looksLikeMerchant = normalizedMerchant != nil && lowered == normalizedMerchant
            let looksLikeMeta = looksLikeReceiptMetadata(lowered)
                || lowered.contains("subtotal")
                || lowered.contains("total")
                || lowered.contains("change")
                || lowered.contains("cash")
                || lowered.contains("visa")
                || lowered.contains("mastercard")
                || lowered.contains("octopus")
                || lowered.contains("八達通")
                || lowered.contains("合計")
                || lowered.contains("總計")
            let mostlyDigits = isMostlyDigits(line)

            if containsLetters && !looksLikeMerchant && !looksLikeMeta && !mostlyDigits {
                return (line, 0.52)
            }
        }

        return (nil, 0)
    }

    private func extractDate(from rawText: String) -> (value: Date?, confidence: Double) {
        let patterns = [
            #"\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b"#,
            #"\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
            guard let match = regex.firstMatch(in: rawText, range: range),
                  let matchRange = Range(match.range, in: rawText) else {
                continue
            }

            let rawDate = String(rawText[matchRange])
            if let date = parseDate(rawDate) {
                return (date, 0.74)
            }
        }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let range = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
            if let date = detector.matches(in: rawText, options: [], range: range).compactMap(\.date).first {
                return (date, 0.68)
            }
        }

        return (nil, 0)
    }

    private func extractCurrency(from rawText: String) -> (value: String?, confidence: Double) {
        let uppercased = rawText.uppercased()
        let codes = ["HKD", "USD", "CNY", "RMB"]
        if let code = codes.first(where: uppercased.contains) {
            return (code == "RMB" ? "CNY" : code, 0.88)
        }

        if rawText.contains("HK$") || rawText.contains("港幣") || rawText.contains("香港") { return ("HKD", 0.84) }
        if rawText.contains("US$") { return ("USD", 0.84) }
        if rawText.contains("¥") || rawText.contains("人民幣") { return ("CNY", 0.78) }
        if rawText.contains("$") { return (AppPreferences.defaultCurrency.rawValue, 0.58) }

        return (AppPreferences.defaultCurrency.rawValue, 0.42)
    }

    private func extractTotalAmount(from lines: [String]) -> (value: Double?, confidence: Double) {
        if let stackedTotal = extractStackedTotalAmount(from: lines) {
            return stackedTotal
        }

        var candidates: [(amount: Double, score: Double)] = []

        for line in lines {
            let lowered = line.lowercased()
            let lineAmounts = amounts(in: line)
            guard !lineAmounts.isEmpty,
                  !looksLikeAmountTrap(lowered),
                  !looksLikeAddressOrContact(lowered) else {
                continue
            }

            var score = 0.28
            if containsAny(lowered, ["grand total", "amount due", "amount paid", "total due", "balance due", "total", "paid", "sale"]) {
                score += 0.48
            }
            if containsAny(lowered, ["總額", "總計", "合計", "應付", "實付", "消費", "付款", "總數"]) {
                score += 0.46
            }
            if containsAny(lowered, ["subtotal", "sub total", "小計"]) {
                score -= 0.28
            }
            if lineAmounts.count > 1 {
                score += 0.04
            }

            if let amount = lineAmounts.last, amount > 0 {
                candidates.append((amount, min(max(score, 0.1), 0.94)))
            }
        }

        if let bestKeywordCandidate = candidates.max(by: { $0.score == $1.score ? $0.amount < $1.amount : $0.score < $1.score }),
           bestKeywordCandidate.score >= 0.55 {
            return (bestKeywordCandidate.amount, bestKeywordCandidate.score)
        }

        let fallbackAmounts = lines
            .filter {
                let lowered = $0.lowercased()
                return !looksLikeAmountTrap(lowered) && !looksLikeAddressOrContact(lowered)
            }
            .flatMap(amounts)
            .filter { $0 > 0 && $0 < 1_000_000 }

        guard let largest = fallbackAmounts.max() else {
            return (nil, 0)
        }

        return (largest, 0.48)
    }

    private func extractStackedTotalAmount(from lines: [String]) -> (value: Double?, confidence: Double)? {
        var candidates: [(amount: Double, score: Double, index: Int)] = []

        for (index, line) in lines.enumerated() {
            let lowered = line.lowercased()
            guard let labelScore = totalLabelScore(for: lowered) else { continue }

            let endIndex = min(lines.count, index + 10)
            guard index + 1 < endIndex else { continue }
            var blockAmounts: [Double] = []

            for lookahead in lines[(index + 1)..<endIndex] {
                let loweredLookahead = lookahead.lowercased()
                guard !looksLikeAddressOrContact(loweredLookahead),
                      !looksLikeReceiptMetadata(loweredLookahead) else {
                    continue
                }

                blockAmounts.append(contentsOf: amounts(in: lookahead).filter { abs($0) < 1_000_000 })
            }

            guard let amount = roundedTotalCandidate(from: blockAmounts) else { continue }
            candidates.append((amount, labelScore, index))
        }

        guard let best = candidates.max(by: {
            $0.score == $1.score ? $0.index < $1.index : $0.score < $1.score
        }) else {
            return nil
        }

        return (best.amount, best.score)
    }

    private func roundedTotalCandidate(from amounts: [Double]) -> Double? {
        let relevantAmounts = amounts.filter { abs($0) > 0 && abs($0) < 1_000_000 }
        guard let firstPositiveIndex = relevantAmounts.firstIndex(where: { $0 > 0 }) else {
            return nil
        }

        let firstPositive = relevantAmounts[firstPositiveIndex]
        let followingAmounts = relevantAmounts.dropFirst(firstPositiveIndex + 1)
        if let adjustment = followingAmounts.first(where: { $0 < 0 && abs($0) <= max(1, firstPositive * 0.1) }) {
            let rounded = firstPositive + adjustment
            if let matchingRoundedAmount = followingAmounts.first(where: { $0 > 0 && abs($0 - rounded) < 0.011 }) {
                return matchingRoundedAmount
            }
        }

        return firstPositive
    }

    private func totalLabelScore(for lowered: String) -> Double? {
        guard !containsAny(lowered, ["subtotal", "sub total", "小計"]) else { return nil }
        guard !containsAny(lowered, ["total includes", "total included"]) else { return nil }

        if containsAny(lowered, [
            "grand total", "amount due", "amount paid", "total due", "total rounded",
            "total round", "rounded total", "total amount", "total amt", "takeout total",
            "total incl", "round", "總額", "總計", "合計", "應付", "實付"
        ]) {
            return 0.86
        }

        if containsAny(lowered, ["total", "paid", "sale"]) {
            return 0.66
        }

        return nil
    }

    private func extractAmount(from lines: [String], keywords: [String]) -> (value: Double?, confidence: Double) {
        let keywordSet = keywords.map { $0.lowercased() }
        let matchingLines = lines.filter { line in
            let lowered = line.lowercased()
            return keywordSet.contains(where: lowered.contains) && !looksLikeAmountTrap(lowered)
        }

        for line in matchingLines {
            if let amount = amounts(in: line).last, amount >= 0 {
                return (amount, 0.72)
            }
        }

        return (nil, 0)
    }

    private func amounts(in line: String) -> [Double] {
        let pattern = #"-?\s*(?:RM|HK\$|US\$|\$)?\s*\d{1,3}(?:[,\s]\d{3})*(?:[.,]\d{2})|-?\s*(?:RM|HK\$|US\$|\$)?\s*\d+(?:[.,]\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)

        return regex.matches(in: line, options: [], range: range)
            .compactMap { match in
                guard let range = Range(match.range, in: line) else { return nil }
                return AmountParser.parse(String(line[range]))
            }
    }

    private func parseDate(_ rawDate: String) -> Date? {
        let components = rawDate
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

    private func extractionConfidence(
        merchantConfidence: Double,
        dateConfidence: Double,
        totalConfidence: Double,
        currencyConfidence: Double,
        categoryConfidence: Double,
        itemConfidence: Double
    ) -> Double {
        let weighted = merchantConfidence * 0.18
            + dateConfidence * 0.22
            + totalConfidence * 0.32
            + currencyConfidence * 0.12
            + categoryConfidence * 0.08
            + itemConfidence * 0.08

        return min(1, max(0, weighted))
    }

    private func cleanMerchant(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\*+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\*+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsKnownHongKongMerchant(_ lowered: String) -> Bool {
        containsAny(lowered, [
            "wellcome", "parknshop", "park n shop", "mannings", "watsons", "7-eleven",
            "circle k", "mtr", "octopus", "citysuper", "aeon", "don don donki",
            "惠康", "百佳", "萬寧", "屈臣氏", "港鐵", "八達通"
        ])
    }

    private func containsBusinessKeyword(_ lowered: String) -> Bool {
        containsAny(lowered, [
            "limited", "ltd", "sdn", "bhd", "enterprise", "trading", "restaurant",
            "restaurants", "store", "market", "supermarket", "deco", "gift", "machinery",
            "motor", "company", "co.", "llc", "inc", "pte", "有限公司", "公司"
        ])
    }

    private func looksLikeReceiptMetadata(_ lowered: String) -> Bool {
        containsAny(lowered, [
            "receipt", "invoice", "tax invoice", "sales slip", "customer copy", "merchant copy",
            "order no", "transaction", "approval", "auth", "terminal", "trace", "ref no",
            "收據", "發票", "單據", "交易", "訂單", "授權碼", "客戶存根"
        ])
    }

    private func looksLikeAddressOrContact(_ lowered: String) -> Bool {
        containsAny(lowered, [
            "tel", "phone", "fax", "www.", ".com", "http", "road", "street", "floor",
            "shop", "unit", "address", "mall", "centre", "center", "tel:", "電話",
            "地址", "商場", "中心", "地下", "樓", "號"
        ])
    }

    private func looksLikeAmountTrap(_ lowered: String) -> Bool {
        containsAny(lowered, [
            "subtotal", "sub total", "change", "cash tendered", "tender", "balance b/f",
            "opening balance", "closing balance", "card", "visa", "mastercard", "american express",
            "approval", "auth", "terminal", "trace", "tel", "phone", "fax", "octopus balance",
            "cash received", "cash", "小計", "找續", "餘額", "卡號", "電話", "授權碼", "八達通餘額"
        ])
    }

    private func isMostlyDigits(_ line: String) -> Bool {
        let digits = line.filter(\.isNumber).count
        return digits > max(3, line.count / 2)
    }

    private func uppercaseLetterRatio(in line: String) -> Double {
        let letters = line.filter(\.isLetter)
        guard !letters.isEmpty else { return 0 }
        let uppercaseLetters = letters.filter { String($0).uppercased() == String($0) }.count
        return Double(uppercaseLetters) / Double(letters.count)
    }

    private func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }
}
