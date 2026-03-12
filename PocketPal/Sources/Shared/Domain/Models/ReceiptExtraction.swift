import Foundation

struct OCRPayload: Sendable {
    let rawText: String
    let confidence: Double?
}

struct ReceiptExtraction: Sendable {
    let merchantName: String?
    let itemDescription: String?
    let transactionDate: Date?
    let totalAmount: Double?
    let currencyCode: String?
    let taxAmount: Double?
    let category: String?
    let confidence: Double?
}
