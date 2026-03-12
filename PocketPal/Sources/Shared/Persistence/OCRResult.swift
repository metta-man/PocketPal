import Foundation
import SwiftData

@Model
final class OCRResult {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var rawText: String
    var confidence: Double?

    var receipt: Receipt?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        rawText: String,
        confidence: Double? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rawText = rawText
        self.confidence = confidence
    }
}
