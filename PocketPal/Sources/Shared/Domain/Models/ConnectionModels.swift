import Foundation

// MARK: - Connection Provider

enum ConnectionProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    // Email providers
    case gmail
    case outlook

    // E-commerce providers
    case amazon
    case taobao
    case ebay
    case temu

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gmail: return "Gmail"
        case .outlook: return "Outlook"
        case .amazon: return "Amazon"
        case .taobao: return "Taobao"
        case .ebay: return "eBay"
        case .temu: return "Temu"
        }
    }

    var providerType: ProviderType {
        switch self {
        case .gmail, .outlook:
            return .email
        case .amazon, .taobao, .ebay, .temu:
            return .ecommerce
        }
    }

    var systemImage: String {
        switch self {
        case .gmail: return "envelope.fill"
        case .outlook: return "envelope.fill"
        case .amazon: return "cart.fill"
        case .taobao: return "cart.fill"
        case .ebay: return "cart.fill"
        case .temu: return "cart.fill"
        }
    }

    var tintColor: ColorShade {
        switch self {
        case .gmail: return .red
        case .outlook: return .blue
        case .amazon: return .orange
        case .taobao: return .orange
        case .ebay: return .blue
        case .temu: return .orange
        }
    }

    /// Whether this provider has a public API available
    var hasPublicAPI: Bool {
        switch self {
        case .gmail, .outlook, .ebay:
            return true
        case .amazon, .taobao:
            return true // Limited API access
        case .temu:
            return false // No public API - must use email detection
        }
    }
}

enum ProviderType: String, Codable, Sendable {
    case email
    case ecommerce
}

enum ColorShade: String, Codable, Sendable {
    case red
    case blue
    case orange
    case green
    case purple
    case gray
}

// MARK: - Expense Type

enum ExpenseType: String, Codable, CaseIterable, Sendable {
    case personal
    case business
    case reimbursable

    var displayName: String {
        switch self {
        case .personal: return "Personal"
        case .business: return "Business"
        case .reimbursable: return "Reimbursable"
        }
    }

    var systemImage: String {
        switch self {
        case .personal: return "person.fill"
        case .business: return "building.2.fill"
        case .reimbursable: return "arrowshape.turn.up.left.fill"
        }
    }

    var isTaxDeductible: Bool {
        switch self {
        case .personal:
            return false
        case .business, .reimbursable:
            return true
        }
    }
}

// MARK: - Tax Category

enum TaxCategory: String, Codable, CaseIterable, Sendable {
    case deductible
    case nonDeductible
    case travel
    case meals
    case office
    case equipment
    case utilities
    case professionalServices
    case uncategorized

    var displayName: String {
        switch self {
        case .deductible: return "Deductible Expense"
        case .nonDeductible: return "Non-Deductible"
        case .travel: return "Travel"
        case .meals: return "Meals & Entertainment"
        case .office: return "Office Supplies"
        case .equipment: return "Equipment"
        case .utilities: return "Utilities"
        case .professionalServices: return "Professional Services"
        case .uncategorized: return "Uncategorized"
        }
    }

    var description: String {
        switch self {
        case .deductible:
            return "General tax-deductible business expense"
        case .nonDeductible:
            return "Not eligible for tax deduction"
        case .travel:
            return "Transportation, lodging, and travel expenses"
        case .meals:
            return "Business meals and client entertainment"
        case .office:
            return "Office supplies and equipment under threshold"
        case .equipment:
            return "Business equipment and machinery"
        case .utilities:
            return "Phone, internet, and utility bills"
        case .professionalServices:
            return "Legal, accounting, and consulting fees"
        case .uncategorized:
            return "Needs categorization"
        }
    }

    var systemImage: String {
        switch self {
        case .deductible: return "checkmark.seal.fill"
        case .nonDeductible: return "xmark.seal.fill"
        case .travel: return "airplane.fill"
        case .meals: return "fork.knife"
        case .office: return "paperclip"
        case .equipment: return "desktopcomputer"
        case .utilities: return "lightbulb.fill"
        case .professionalServices: return "briefcase.fill"
        case .uncategorized: return "questionmark.circle.fill"
        }
    }
}

// MARK: - Sync Status

enum SyncStatus: String, Codable, Sendable {
    case idle
    case syncing
    case completed
    case failed

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .syncing: return "Syncing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "circle"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }
}
