import Foundation

enum ReceiptReviewStatus: String, Codable, CaseIterable, Sendable {
    case inbox
    case reviewed
}

enum ReceiptImportSource: String, Codable, CaseIterable, Sendable {
    case files
    case photos
    case scanner
    case dragDrop
    case manual
}

enum ReceiptAssetKind: String, Codable, CaseIterable, Sendable {
    case image
    case pdf
}

enum TransactionKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case expense
    case income

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .expense:
            return "Expense"
        case .income:
            return "Income"
        }
    }

    var systemImage: String {
        switch self {
        case .expense:
            return "arrow.down.circle.fill"
        case .income:
            return "arrow.up.circle.fill"
        }
    }
}

enum ReceiptCategory: String, Codable, CaseIterable, Sendable {
    case groceries = "Groceries"
    case meals = "Meals"
    case travel = "Travel"
    case transport = "Transport"
    case office = "Office"
    case shopping = "Shopping"
    case utilities = "Utilities"
    case entertainment = "Entertainment"
    case health = "Health"
    case lodging = "Lodging"
    case uncategorized = "Uncategorized"
}

enum Currency: String, Codable, CaseIterable, Sendable, Identifiable {
    case hkd = "HKD"
    case cny = "CNY"
    case usd = "USD"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hkd:
            return "Hong Kong Dollar"
        case .cny:
            return "Chinese Yuan"
        case .usd:
            return "US Dollar"
        }
    }

    var symbol: String {
        switch self {
        case .hkd:
            return "HK$"
        case .cny:
            return "CN¥"
        case .usd:
            return "$"
        }
    }

    var flag: String {
        switch self {
        case .hkd:
            return "🇭🇰"
        case .cny:
            return "🇨🇳"
        case .usd:
            return "🇺🇸"
        }
    }

    var pickerTitle: String {
        "\(flag) \(rawValue)"
    }

    static func from(code: String?) -> Currency? {
        guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else {
            return nil
        }

        return Currency(rawValue: code)
    }

    static func amountString(_ amount: Double, currencyCode: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = from(code: currencyCode)?.rawValue ?? AppPreferences.defaultCurrency.rawValue
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

struct ExchangeRate: Codable, Sendable {
    let currency: Currency
    let hkdPerUnit: Double
    let updatedAt: Date
}

enum ExchangeRateTable {
    static let rates: [Currency: ExchangeRate] = [
        .hkd: ExchangeRate(currency: .hkd, hkdPerUnit: 1.0, updatedAt: .now),
        .cny: ExchangeRate(currency: .cny, hkdPerUnit: 1.09, updatedAt: .now),
        .usd: ExchangeRate(currency: .usd, hkdPerUnit: 7.82, updatedAt: .now)
    ]

    static func convertToHKD(amount: Double, from currency: Currency) -> Double {
        amount * (rates[currency]?.hkdPerUnit ?? 1.0)
    }
}
