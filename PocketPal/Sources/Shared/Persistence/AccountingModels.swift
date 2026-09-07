import Foundation
import SwiftData

enum AccountType: String, Codable, CaseIterable, Sendable, Identifiable {
    case asset
    case liability
    case equity
    case income
    case expense

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .asset: return "Asset"
        case .liability: return "Liability"
        case .equity: return "Equity"
        case .income: return "Income"
        case .expense: return "Expense"
        }
    }
}

enum AccountingStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case open
    case paid
    case overdue
    case reconciled
    case ignored

    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .open: return "Open"
        case .paid: return "Paid"
        case .overdue: return "Overdue"
        case .reconciled: return "Reconciled"
        case .ignored: return "Ignored"
        }
    }
}

enum RecurringInterval: String, Codable, CaseIterable, Sendable, Identifiable {
    case weekly
    case monthly
    case quarterly
    case yearly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly: return "Yearly"
        }
    }
}

@Model
final class AccountingAccount {
    var id: UUID
    var code: String
    var name: String
    var accountTypeRawValue: String
    var openingBalanceHKD: Double
    var isActive: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        code: String,
        name: String,
        accountType: AccountType,
        openingBalanceHKD: Double = 0,
        isActive: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.accountTypeRawValue = accountType.rawValue
        self.openingBalanceHKD = openingBalanceHKD
        self.isActive = isActive
        self.createdAt = createdAt
    }

    var accountType: AccountType {
        get { AccountType(rawValue: accountTypeRawValue) ?? .expense }
        set { accountTypeRawValue = newValue.rawValue }
    }
}

@Model
final class BankTransaction {
    var id: UUID
    var accountName: String
    var postedAt: Date
    var descriptionText: String
    var amountHKD: Double
    var statusRawValue: String
    var matchedReceiptID: String?
    var suggestedCategory: String?
    var importedAt: Date

    init(
        id: UUID = UUID(),
        accountName: String,
        postedAt: Date = .now,
        descriptionText: String,
        amountHKD: Double,
        status: AccountingStatus = .open,
        matchedReceiptID: String? = nil,
        suggestedCategory: String? = nil,
        importedAt: Date = .now
    ) {
        self.id = id
        self.accountName = accountName
        self.postedAt = postedAt
        self.descriptionText = descriptionText
        self.amountHKD = amountHKD
        self.statusRawValue = status.rawValue
        self.matchedReceiptID = matchedReceiptID
        self.suggestedCategory = suggestedCategory
        self.importedAt = importedAt
    }

    var status: AccountingStatus {
        get { AccountingStatus(rawValue: statusRawValue) ?? .open }
        set { statusRawValue = newValue.rawValue }
    }
}

@Model
final class ClientRecord {
    var id: UUID
    var name: String
    var email: String?
    var notes: String?
    var createdAt: Date

    init(id: UUID = UUID(), name: String, email: String? = nil, notes: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.email = email
        self.notes = notes
        self.createdAt = createdAt
    }
}

@Model
final class ProjectRecord {
    var id: UUID
    var name: String
    var clientName: String
    var budgetHKD: Double
    var isActive: Bool
    var createdAt: Date

    init(id: UUID = UUID(), name: String, clientName: String, budgetHKD: Double = 0, isActive: Bool = true, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.clientName = clientName
        self.budgetHKD = budgetHKD
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

@Model
final class InvoiceRecord {
    var id: UUID
    var invoiceNumber: String
    var clientName: String
    var projectName: String?
    var issueDate: Date
    var dueDate: Date
    var amountHKD: Double
    var statusRawValue: String
    var paidAt: Date?
    var notes: String?

    init(
        id: UUID = UUID(),
        invoiceNumber: String,
        clientName: String,
        projectName: String? = nil,
        issueDate: Date = .now,
        dueDate: Date = .now.addingTimeInterval(1_209_600),
        amountHKD: Double,
        status: AccountingStatus = .open,
        paidAt: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.invoiceNumber = invoiceNumber
        self.clientName = clientName
        self.projectName = projectName
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.amountHKD = amountHKD
        self.statusRawValue = status.rawValue
        self.paidAt = paidAt
        self.notes = notes
    }

    var status: AccountingStatus {
        get { AccountingStatus(rawValue: statusRawValue) ?? .open }
        set { statusRawValue = newValue.rawValue }
    }
}

@Model
final class BillRecord {
    var id: UUID
    var vendorName: String
    var billNumber: String?
    var dueDate: Date
    var amountHKD: Double
    var category: String
    var statusRawValue: String
    var paidAt: Date?
    var notes: String?

    init(
        id: UUID = UUID(),
        vendorName: String,
        billNumber: String? = nil,
        dueDate: Date = .now,
        amountHKD: Double,
        category: String = "Uncategorized",
        status: AccountingStatus = .open,
        paidAt: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.vendorName = vendorName
        self.billNumber = billNumber
        self.dueDate = dueDate
        self.amountHKD = amountHKD
        self.category = category
        self.statusRawValue = status.rawValue
        self.paidAt = paidAt
        self.notes = notes
    }

    var status: AccountingStatus {
        get { AccountingStatus(rawValue: statusRawValue) ?? .open }
        set { statusRawValue = newValue.rawValue }
    }
}

@Model
final class TimeEntryRecord {
    var id: UUID
    var projectName: String
    var workDate: Date
    var hours: Double
    var hourlyRateHKD: Double
    var notes: String?
    var isBilled: Bool

    init(id: UUID = UUID(), projectName: String, workDate: Date = .now, hours: Double, hourlyRateHKD: Double, notes: String? = nil, isBilled: Bool = false) {
        self.id = id
        self.projectName = projectName
        self.workDate = workDate
        self.hours = hours
        self.hourlyRateHKD = hourlyRateHKD
        self.notes = notes
        self.isBilled = isBilled
    }

    var billableAmountHKD: Double { hours * hourlyRateHKD }
}

@Model
final class MileageTripRecord {
    var id: UUID
    var projectName: String?
    var tripDate: Date
    var distanceKM: Double
    var ratePerKMHKD: Double
    var purpose: String
    var isReimbursed: Bool

    init(id: UUID = UUID(), projectName: String? = nil, tripDate: Date = .now, distanceKM: Double, ratePerKMHKD: Double = 3, purpose: String, isReimbursed: Bool = false) {
        self.id = id
        self.projectName = projectName
        self.tripDate = tripDate
        self.distanceKM = distanceKM
        self.ratePerKMHKD = ratePerKMHKD
        self.purpose = purpose
        self.isReimbursed = isReimbursed
    }

    var reimbursableHKD: Double { distanceKM * ratePerKMHKD }
}

@Model
final class RecurringRuleRecord {
    var id: UUID
    var title: String
    var transactionKindRawValue: String
    var amountHKD: Double
    var category: String
    var intervalRawValue: String
    var nextRunAt: Date
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        title: String,
        transactionKind: TransactionKind = .expense,
        amountHKD: Double,
        category: String,
        interval: RecurringInterval = .monthly,
        nextRunAt: Date = .now,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.transactionKindRawValue = transactionKind.rawValue
        self.amountHKD = amountHKD
        self.category = category
        self.intervalRawValue = interval.rawValue
        self.nextRunAt = nextRunAt
        self.isEnabled = isEnabled
    }

    var transactionKind: TransactionKind {
        get { TransactionKind(rawValue: transactionKindRawValue) ?? .expense }
        set { transactionKindRawValue = newValue.rawValue }
    }

    var interval: RecurringInterval {
        get { RecurringInterval(rawValue: intervalRawValue) ?? .monthly }
        set { intervalRawValue = newValue.rawValue }
    }
}

@Model
final class AccountingRuleRecord {
    var id: UUID
    var merchantContains: String
    var category: String
    var expenseTypeRawValue: String
    var taxCategoryRawValue: String?
    var isEnabled: Bool

    init(id: UUID = UUID(), merchantContains: String, category: String, expenseType: ExpenseType = .business, taxCategory: TaxCategory? = nil, isEnabled: Bool = true) {
        self.id = id
        self.merchantContains = merchantContains
        self.category = category
        self.expenseTypeRawValue = expenseType.rawValue
        self.taxCategoryRawValue = taxCategory?.rawValue
        self.isEnabled = isEnabled
    }

    var expenseType: ExpenseType {
        get { ExpenseType(rawValue: expenseTypeRawValue) ?? .business }
        set { expenseTypeRawValue = newValue.rawValue }
    }

    var taxCategory: TaxCategory? {
        get {
            guard let taxCategoryRawValue else { return nil }
            return TaxCategory(rawValue: taxCategoryRawValue)
        }
        set { taxCategoryRawValue = newValue?.rawValue }
    }
}

@Model
final class JournalEntryRecord {
    var id: UUID
    var entryDate: Date
    var memo: String
    var debitAccountName: String
    var creditAccountName: String
    var amountHKD: Double
    var createdAt: Date

    init(id: UUID = UUID(), entryDate: Date = .now, memo: String, debitAccountName: String, creditAccountName: String, amountHKD: Double, createdAt: Date = .now) {
        self.id = id
        self.entryDate = entryDate
        self.memo = memo
        self.debitAccountName = debitAccountName
        self.creditAccountName = creditAccountName
        self.amountHKD = amountHKD
        self.createdAt = createdAt
    }
}

@Model
final class PayrollRunRecord {
    var id: UUID
    var payDate: Date
    var employeeName: String
    var grossPayHKD: Double
    var employerCostHKD: Double
    var statusRawValue: String
    var notes: String?

    init(id: UUID = UUID(), payDate: Date = .now, employeeName: String, grossPayHKD: Double, employerCostHKD: Double = 0, status: AccountingStatus = .open, notes: String? = nil) {
        self.id = id
        self.payDate = payDate
        self.employeeName = employeeName
        self.grossPayHKD = grossPayHKD
        self.employerCostHKD = employerCostHKD
        self.statusRawValue = status.rawValue
        self.notes = notes
    }

    var status: AccountingStatus {
        get { AccountingStatus(rawValue: statusRawValue) ?? .open }
        set { statusRawValue = newValue.rawValue }
    }
}

@Model
final class InventoryItemRecord {
    var id: UUID
    var sku: String
    var name: String
    var quantityOnHand: Double
    var unitCostHKD: Double
    var reorderPoint: Double
    var isActive: Bool

    init(id: UUID = UUID(), sku: String, name: String, quantityOnHand: Double = 0, unitCostHKD: Double = 0, reorderPoint: Double = 0, isActive: Bool = true) {
        self.id = id
        self.sku = sku
        self.name = name
        self.quantityOnHand = quantityOnHand
        self.unitCostHKD = unitCostHKD
        self.reorderPoint = reorderPoint
        self.isActive = isActive
    }

    var inventoryValueHKD: Double { quantityOnHand * unitCostHKD }
    var needsReorder: Bool { quantityOnHand <= reorderPoint }
}
