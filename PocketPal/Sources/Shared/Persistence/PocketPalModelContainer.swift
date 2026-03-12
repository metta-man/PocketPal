import Foundation
import SwiftData

enum PocketPalModelContainer {
    static let schema = Schema([
        Receipt.self,
        ReceiptAsset.self,
        OCRResult.self
    ])
    private static let storeDirectoryName = "PocketPal"
    private static let storeFilename = "PocketPal.store"

    static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration

        if isStoredInMemoryOnly {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
        } else {
            let storeURL = try persistentStoreURL()
            configuration = ModelConfiguration(
                schema: schema,
                url: storeURL
            )
        }

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            guard !isStoredInMemoryOnly else {
                throw error
            }

            try resetPersistentStore()
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }

    private static func persistentStoreURL(fileManager: FileManager = .default) throws -> URL {
        let appSupportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let storeDirectory = appSupportDirectory.appending(path: storeDirectoryName, directoryHint: .isDirectory)

        if !fileManager.fileExists(atPath: storeDirectory.path()) {
            try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        }

        return storeDirectory.appending(path: storeFilename, directoryHint: .notDirectory)
    }

    private static func resetPersistentStore(fileManager: FileManager = .default) throws {
        let storeURL = try persistentStoreURL(fileManager: fileManager)
        let cleanupURLs = [
            storeURL,
            storeURL.deletingLastPathComponent().appending(path: "\(storeURL.lastPathComponent)-shm"),
            storeURL.deletingLastPathComponent().appending(path: "\(storeURL.lastPathComponent)-wal")
        ]

        for url in cleanupURLs where fileManager.fileExists(atPath: url.path()) {
            try fileManager.removeItem(at: url)
        }
    }
}
