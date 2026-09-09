import Foundation

enum AppPreferences {
    static let defaultCurrencyCodeKey = "settings.defaultCurrencyCode"
    static let defaultExpenseTypeKey = "settings.defaultExpenseType"
    static let taxYearStartMonthKey = "settings.taxYearStartMonth"
    static let cloudReceiptEnhancementEnabledKey = "settings.geminiReceiptExtractionEnabled"
    static let cloudReceiptUploadConsentKey = "settings.geminiReceiptUploadConsent"
    static let geminiAPIKeyKey = "credentials.gemini.apiKey"
    static let openAIAPIKeyKey = "credentials.openai.apiKey"

    static var defaultCurrency: Currency {
        get {
            Currency.from(code: UserDefaults.standard.string(forKey: defaultCurrencyCodeKey)) ?? .hkd
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultCurrencyCodeKey)
        }
    }

    static var defaultExpenseType: ExpenseType {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: defaultExpenseTypeKey),
                  let value = ExpenseType(rawValue: rawValue) else {
                return .personal
            }

            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultExpenseTypeKey)
        }
    }

    static var taxYearStartMonth: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: taxYearStartMonthKey)
            return (1...12).contains(value) ? value : 4
        }
        set {
            UserDefaults.standard.set(max(1, min(12, newValue)), forKey: taxYearStartMonthKey)
        }
    }

    static var cloudReceiptEnhancementEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: cloudReceiptEnhancementEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: cloudReceiptEnhancementEnabledKey) }
    }

    static var cloudReceiptUploadConsentGranted: Bool {
        get { UserDefaults.standard.bool(forKey: cloudReceiptUploadConsentKey) }
        set { UserDefaults.standard.set(newValue, forKey: cloudReceiptUploadConsentKey) }
    }

    static func taxYearDescription(referenceDate: Date = .now) -> String {
        let calendar = Calendar.current
        let startMonth = taxYearStartMonth
        let year = calendar.component(.year, from: referenceDate)
        let month = calendar.component(.month, from: referenceDate)
        let startYear = month >= startMonth ? year : year - 1

        guard let startDate = calendar.date(from: DateComponents(year: startYear, month: startMonth, day: 1)),
              let nextStartDate = calendar.date(byAdding: .year, value: 1, to: startDate),
              let endDate = calendar.date(byAdding: .day, value: -1, to: nextStartDate) else {
            return "Tax year"
        }

        return "\(startDate.formatted(.dateTime.day().month(.wide).year())) to \(endDate.formatted(.dateTime.day().month(.wide).year()))"
    }
}

enum InfrastructureFeatureFlags {
    static let accountingWorkspaceEnabledKey = "features.accountingWorkspaceEnabled"

    static var accountingWorkspaceEnabled: Bool {
        if let override = ProcessInfo.processInfo.environment["POCKETPAL_ENABLE_ACCOUNTING_WORKSPACE"] {
            return override == "1" || override.lowercased() == "true"
        }

        return UserDefaults.standard.bool(forKey: accountingWorkspaceEnabledKey)
    }
}


enum ReceiptLedger: String, CaseIterable, Identifiable {
    case personal, business
    var id: String { rawValue }
    var title: String { self == .personal ? "個人" : "業務" }
    var expenseType: ExpenseType { self == .personal ? .personal : .business }
    func includes(_ receipt: Receipt) -> Bool {
        !receipt.finance.isTemplate && (self == .personal ? receipt.expenseType == .personal : receipt.expenseType != .personal)
    }
}
