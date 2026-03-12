import Foundation
import UniformTypeIdentifiers

struct ImportedReceiptDocument: Sendable {
    let data: Data
    let suggestedFilename: String
    let contentType: UTType
}

enum ReceiptImportInput: Sendable {
    case file(URL)
    case inMemory(ImportedReceiptDocument)
}
