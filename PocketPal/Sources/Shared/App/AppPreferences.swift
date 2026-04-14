import Foundation

enum AppPreferences {
    static let defaultCurrencyCodeKey = "settings.defaultCurrencyCode"
    static let defaultExpenseTypeKey = "settings.defaultExpenseType"
    static let taxYearStartMonthKey = "settings.taxYearStartMonth"

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
