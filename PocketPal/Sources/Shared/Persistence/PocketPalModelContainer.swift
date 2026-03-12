import Foundation
import SwiftData

enum PocketPalModelContainer {
    static let schema = Schema([
        Receipt.self,
        ReceiptAsset.self,
        OCRResult.self
    ])

    static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
