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
}

enum ReceiptAssetKind: String, Codable, CaseIterable, Sendable {
    case image
    case pdf
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
