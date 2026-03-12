import Foundation

enum OCRLanguageOption: String, CaseIterable, Identifiable {
    case englishUS = "en-US"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .englishUS:
            return "English"
        case .simplifiedChinese:
            return "Chinese (Simplified)"
        case .traditionalChinese:
            return "Chinese (Traditional)"
        }
    }

    var detail: String {
        switch self {
        case .englishUS:
            return "Better for Latin receipts and mixed English totals."
        case .simplifiedChinese:
            return "Use for Simplified Chinese receipts and invoices."
        case .traditionalChinese:
            return "Use for Traditional Chinese receipts and invoices."
        }
    }
}

enum OCRPreferences {
    static let selectedLanguageCodesKey = "ocr.selectedRecognitionLanguages"
    static let defaultLanguageCodes = OCRLanguageOption.allCases.map(\.rawValue)

    static func selectedRecognitionLanguages(userDefaults: UserDefaults = .standard) -> [String] {
        let storedCodes = parseStoredLanguageCodes(userDefaults.string(forKey: selectedLanguageCodesKey))
        return storedCodes.isEmpty ? defaultLanguageCodes : storedCodes
    }

    static func updateSelectedRecognitionLanguages(
        _ languageCodes: [String],
        userDefaults: UserDefaults = .standard
    ) {
        let validCodes = normalizedLanguageCodes(languageCodes)
        let resolvedCodes = validCodes.isEmpty ? defaultLanguageCodes : validCodes
        userDefaults.set(resolvedCodes.joined(separator: ","), forKey: selectedLanguageCodesKey)
    }

    private static func parseStoredLanguageCodes(_ rawValue: String?) -> [String] {
        guard let rawValue else {
            return []
        }

        let parsed = rawValue
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        return normalizedLanguageCodes(parsed)
    }

    private static func normalizedLanguageCodes(_ languageCodes: [String]) -> [String] {
        var seen = Set<String>()

        return languageCodes.compactMap { code in
            guard OCRLanguageOption(rawValue: code) != nil else {
                return nil
            }

            guard seen.insert(code).inserted else {
                return nil
            }

            return code
        }
    }
}
