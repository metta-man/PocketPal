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
