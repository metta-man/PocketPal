import Foundation

enum AmountParser {
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let cleaned = trimmed.replacingOccurrences(of: "[^0-9,.-]", with: "", options: .regularExpression)
        guard !cleaned.isEmpty else { return nil }

        let decimalSeparator: Character
        if let lastDot = cleaned.lastIndex(of: "."),
           let lastComma = cleaned.lastIndex(of: ",") {
            decimalSeparator = lastDot > lastComma ? "." : ","
        } else if cleaned.contains(",") && !cleaned.contains(".") {
            decimalSeparator = ","
        } else {
            decimalSeparator = "."
        }

        let normalized: String
        switch decimalSeparator {
        case ",":
            normalized = cleaned
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        default:
            normalized = cleaned.replacingOccurrences(of: ",", with: "")
        }

        return Double(normalized)
    }
}
