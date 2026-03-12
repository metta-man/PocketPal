import Foundation

struct ReceiptCategoryClassifier {
    func category(forMerchant merchantName: String?, rawText: String) -> ReceiptCategory? {
        let normalizedMerchant = normalize(merchantName)
        let normalizedText = normalize(rawText)
        let haystack = [normalizedMerchant, normalizedText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !haystack.isEmpty else {
            return nil
        }

        for rule in rules {
            if rule.keywords.contains(where: { haystack.contains($0) }) {
                return rule.category
            }
        }

        return nil
    }

    private var rules: [(category: ReceiptCategory, keywords: [String])] {
        [
            (.groceries, [
                "supermarket", "grocery", "groceries", "fresh market", "market", "produce",
                "vegetable", "veg", "fruit", "bakery", "butcher", "dairy", "whole foods",
                "trader joes", "costco"
            ]),
            (.meals, [
                "restaurant", "cafe", "coffee", "tea", "bar", "bistro", "diner", "food",
                "lunch", "dinner", "breakfast", "meal", "ubereats", "doordash", "deliveroo"
            ]),
            (.travel, [
                "airlines", "airways", "flight", "airport", "booking", "expedia", "trip",
                "travel", "tour", "vacation"
            ]),
            (.transport, [
                "metro", "transit", "mtr", "octopus", "taxi", "uber", "lyft", "bus",
                "train", "rail", "ferry", "parking", "toll", "shell", "esso", "petrol", "gas station"
            ]),
            (.office, [
                "stationery", "office", "printer", "paper", "toner", "notebook", "staples",
                "officedepot", "office depot", "workspace", "supplies"
            ]),
            (.shopping, [
                "mall", "store", "shop", "retail", "uniqlo", "zara", "h&m", "ikea",
                "amazon", "target", "walmart", "purchase"
            ]),
            (.utilities, [
                "electric", "electricity", "water bill", "internet", "broadband", "utility",
                "phone bill", "mobile", "telecom", "subscription"
            ]),
            (.entertainment, [
                "cinema", "movie", "theatre", "theater", "concert", "museum", "game",
                "netflix", "spotify", "disney", "playstation", "nintendo"
            ]),
            (.health, [
                "hospital", "clinic", "pharmacy", "medical", "doctor", "dental", "dentist",
                "health", "wellness", "drugstore", "watsons", "mannings"
            ]),
            (.lodging, [
                "hotel", "hostel", "inn", "resort", "airbnb", "accommodation", "lodging"
            ])
        ]
    }

    private func normalize(_ value: String?) -> String {
        guard let value else { return "" }

        return value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
