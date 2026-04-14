import Foundation
import SwiftData
import OSLog

enum PocketPalModelContainer {
    static let schema = Schema([
        Receipt.self,
        ReceiptAsset.self,
        OCRResult.self,
        Connection.self,
        SyncLog.self
    ])
    private static let storeDirectoryName = "PocketPal"
    private static let storeFilename = "PocketPal.store"
    private static let logger = Logger(subsystem: "com.lumilux.pocketpal", category: "SwiftData")

    static func make(isStoredInMemoryOnly: Bool = false, cloudSyncEnabled: Bool = true) throws -> ModelContainer {
        let configuration = try makeConfiguration(
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudSyncEnabled: cloudSyncEnabled
        )
        let storeLocation = isStoredInMemoryOnly ? "<memory>" : configuration.url.path(percentEncoded: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            if cloudSyncEnabled && !isStoredInMemoryOnly {
                logger.error("CloudKit-backed SwiftData store failed to open at \(storeLocation, privacy: .public): \(String(describing: error), privacy: .public)")
                return try make(isStoredInMemoryOnly: false, cloudSyncEnabled: false)
            }

            guard !isStoredInMemoryOnly else {
                throw error
            }

            logger.error("SwiftData store failed to open at \(storeLocation, privacy: .public): \(String(describing: error), privacy: .public)")
            try resetPersistentStore()

            let resetConfiguration = try makeConfiguration(
                isStoredInMemoryOnly: false,
                cloudSyncEnabled: false
            )
            return try ModelContainer(for: schema, configurations: [resetConfiguration])
        }
    }

    static func makeWithFallback() -> ModelContainer {
        do {
            return try make(cloudSyncEnabled: CloudSyncConfiguration.isEnabled)
        } catch {
            logger.fault("Falling back to in-memory SwiftData store after persistent store recovery failed: \(String(describing: error), privacy: .public)")

            do {
                return try make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
            } catch {
                fatalError("Failed to initialize SwiftData container: \(error)")
            }
        }
    }

    private static func makeConfiguration(
        isStoredInMemoryOnly: Bool,
        cloudSyncEnabled: Bool
    ) throws -> ModelConfiguration {
        if isStoredInMemoryOnly {
            return ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        }

        let storeURL = try persistentStoreURL()
        if cloudSyncEnabled {
            return ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .automatic
            )
        }

        return ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
    }

    private static func persistentStoreURL(fileManager: FileManager = .default) throws -> URL {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.lumilux.pocketpal"
        let appSupportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let storeDirectory = appSupportDirectory
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
            .appending(path: storeDirectoryName, directoryHint: .isDirectory)

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
