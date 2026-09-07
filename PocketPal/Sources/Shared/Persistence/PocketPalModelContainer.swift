import Foundation
import SwiftData
import OSLog
import SQLite3

enum PocketPalModelContainer {
    private static let receiptLedgerModels: [any PersistentModel.Type] = [
        Receipt.self,
        ReceiptAsset.self,
        OCRResult.self
    ]

    private static let connectionExperimentModels: [any PersistentModel.Type] = [
        Connection.self,
        SyncLog.self
    ]

    // Keep these in the store schema so existing local data is not destroyed,
    // but keep their UI feature-flagged until the receipt ledger is proven.
    private static let advancedAccountingModels: [any PersistentModel.Type] = [
        AccountingAccount.self,
        BankTransaction.self,
        ClientRecord.self,
        ProjectRecord.self,
        InvoiceRecord.self,
        BillRecord.self,
        TimeEntryRecord.self,
        MileageTripRecord.self,
        RecurringRuleRecord.self,
        AccountingRuleRecord.self,
        JournalEntryRecord.self,
        PayrollRunRecord.self,
        InventoryItemRecord.self
    ]

    private static let experimentModels = connectionExperimentModels + advancedAccountingModels

    private static let receiptLedgerSchema = Schema(receiptLedgerModels)
    private static let experimentsSchema = Schema(experimentModels)
    private static let legacyCombinedSchema = Schema(receiptLedgerModels + experimentModels)
    private static let experimentTableNames = [
        "ZCONNECTION",
        "ZSYNCLOG",
        "ZACCOUNTINGACCOUNT",
        "ZBANKTRANSACTION",
        "ZCLIENTRECORD",
        "ZPROJECTRECORD",
        "ZINVOICERECORD",
        "ZBILLRECORD",
        "ZTIMEENTRYRECORD",
        "ZMILEAGETRIPRECORD",
        "ZRECURRINGRULERECORD",
        "ZACCOUNTINGRULERECORD",
        "ZJOURNALENTRYRECORD",
        "ZPAYROLLRUNRECORD",
        "ZINVENTORYITEMRECORD"
    ]
    private static let experimentEntityNames = [
        "Connection",
        "SyncLog",
        "AccountingAccount",
        "BankTransaction",
        "ClientRecord",
        "ProjectRecord",
        "InvoiceRecord",
        "BillRecord",
        "TimeEntryRecord",
        "MileageTripRecord",
        "RecurringRuleRecord",
        "AccountingRuleRecord",
        "JournalEntryRecord",
        "PayrollRunRecord",
        "InventoryItemRecord"
    ]
    private static let receiptLedgerTableNames = [
        "ZRECEIPT",
        "ZRECEIPTASSET",
        "ZOCRRESULT"
    ]

    static let schema = receiptLedgerSchema
    private static let storeDirectoryName = "PocketPal"
    private static let receiptLedgerStoreFilename = "PocketPal.store"
    private static let experimentsStoreFilename = "PocketPalExperiments.store"
    private static let migrationBackupDirectoryName = "MigrationBackups"
    private static let storeRootOverrideEnvironmentKey = "POCKETPAL_STORE_ROOT_OVERRIDE"
    private static let logger = Logger(subsystem: "com.lumilux.pocketpal", category: "SwiftData")

    static func make(isStoredInMemoryOnly: Bool = false, cloudSyncEnabled: Bool = true) throws -> ModelContainer {
        do {
            if !isStoredInMemoryOnly {
                try migrateLegacyCombinedStoreIfNeeded()
            }

            let configuration = try makeReceiptLedgerConfiguration(
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                cloudSyncEnabled: cloudSyncEnabled
            )
            return try ModelContainer(for: receiptLedgerSchema, configurations: [configuration])
        } catch {
            if cloudSyncEnabled && !isStoredInMemoryOnly {
                logger.error("CloudKit-backed SwiftData store failed to open: \(String(describing: error), privacy: .public)")
                return try make(isStoredInMemoryOnly: false, cloudSyncEnabled: false)
            }

            guard !isStoredInMemoryOnly else {
                throw error
            }

            logger.error("Split SwiftData stores failed to open: \(String(describing: error), privacy: .public)")
            return try makeLegacyCombinedStoreContainer()
        }
    }

    static func makeExperiments(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = try makeExperimentsConfiguration(isStoredInMemoryOnly: isStoredInMemoryOnly)
        return try ModelContainer(for: experimentsSchema, configurations: [configuration])
    }

    private static func makeLegacyCombinedStoreContainer() throws -> ModelContainer {
        let configuration = try makeLegacyCombinedStoreConfiguration(cloudSyncEnabled: false)
        let storeLocation = configuration.url.path(percentEncoded: false)

        do {
            logger.fault("Opening legacy combined SwiftData store at \(storeLocation, privacy: .public) after split-store open failed")
            return try ModelContainer(for: legacyCombinedSchema, configurations: [configuration])
        } catch {
            logger.error("Legacy combined SwiftData store also failed to open at \(storeLocation, privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Convenience for dev/preview paths that want a guaranteed container.
    ///
    /// Production launches should use `make(cloudSyncEnabled:)` directly and
    /// surface a blocking error state on failure (see `PocketPalApp` and
    /// `PersistentStoreErrorView`). This method silently falls back to an
    /// in-memory store which is unsafe for real app sessions.
    static func makeWithFallback() -> ModelContainer {
        do {
            return try make(cloudSyncEnabled: CloudSyncConfiguration.isEnabled)
        } catch {
            logger.fault("Falling back to in-memory SwiftData store after persistent store open failed: \(String(describing: error), privacy: .public)")

            do {
                return try make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
            } catch {
                fatalError("Failed to initialize SwiftData container: \(error)")
            }
        }
    }

    private static func makeReceiptLedgerConfiguration(
        isStoredInMemoryOnly: Bool,
        cloudSyncEnabled: Bool
    ) throws -> ModelConfiguration {
        if isStoredInMemoryOnly {
            return ModelConfiguration(
                "ReceiptLedger",
                schema: receiptLedgerSchema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        }

        let receiptLedgerStoreURL = try persistentStoreURL(filename: receiptLedgerStoreFilename)

        return ModelConfiguration(
            "ReceiptLedger",
            schema: receiptLedgerSchema,
            url: receiptLedgerStoreURL,
            cloudKitDatabase: cloudSyncEnabled ? .automatic : .none
        )
    }

    private static func makeExperimentsConfiguration(isStoredInMemoryOnly: Bool) throws -> ModelConfiguration {
        if isStoredInMemoryOnly {
            return ModelConfiguration(
                "Experiments",
                schema: experimentsSchema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        }

        let experimentsStoreURL = try persistentStoreURL(filename: experimentsStoreFilename)
        return ModelConfiguration(
            "Experiments",
            schema: experimentsSchema,
            url: experimentsStoreURL,
            cloudKitDatabase: .none
        )
    }

    private static func makeLegacyCombinedStoreConfiguration(cloudSyncEnabled: Bool) throws -> ModelConfiguration {
        let storeURL = try persistentStoreURL(filename: receiptLedgerStoreFilename)
        return makeLegacyCombinedStoreConfiguration(storeURL: storeURL, cloudSyncEnabled: cloudSyncEnabled)
    }

    private static func makeLegacyCombinedStoreConfiguration(
        storeURL: URL,
        cloudSyncEnabled: Bool
    ) -> ModelConfiguration {
        return ModelConfiguration(
            schema: legacyCombinedSchema,
            url: storeURL,
            cloudKitDatabase: cloudSyncEnabled ? .automatic : .none
        )
    }

    private static func persistentStoreURL(
        filename: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let storeRootDirectory = try persistentStoreRootDirectory(fileManager: fileManager)
        let storeDirectory = storeRootDirectory
            .appending(path: storeDirectoryName, directoryHint: .isDirectory)

        if !fileManager.fileExists(atPath: storeDirectory.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        }

        return storeDirectory.appending(path: filename, directoryHint: .notDirectory)
    }

    private static func persistentStoreRootDirectory(fileManager: FileManager) throws -> URL {
        if let override = getenv(storeRootOverrideEnvironmentKey) {
            let overridePath = String(cString: override)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !overridePath.isEmpty {
                let overrideURL = URL(filePath: overridePath, directoryHint: .isDirectory)
                if !fileManager.fileExists(atPath: overrideURL.path(percentEncoded: false)) {
                    try fileManager.createDirectory(at: overrideURL, withIntermediateDirectories: true)
                }
                return overrideURL
            }
        }

        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.lumilux.pocketpal"
        return try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
    }

    private static func migrateLegacyCombinedStoreIfNeeded(
        fileManager: FileManager = .default
    ) throws {
        let receiptStoreURL = try persistentStoreURL(filename: receiptLedgerStoreFilename, fileManager: fileManager)
        let experimentsStoreURL = try persistentStoreURL(filename: experimentsStoreFilename, fileManager: fileManager)

        guard fileManager.fileExists(atPath: receiptStoreURL.path(percentEncoded: false)) else {
            return
        }

        guard legacyCombinedStoreNeedsSplit(storeURL: receiptStoreURL, fileManager: fileManager) else {
            removeEmptyStaleExperimentsStoreIfNeeded(
                experimentsStoreURL: experimentsStoreURL,
                fileManager: fileManager
            )
            return
        }

        let backupStoreURL = try copyStoreClusterToMigrationBackup(
            storeURL: receiptStoreURL,
            fileManager: fileManager
        )

        let experimentsStoreExistedBeforeMigration = fileManager.fileExists(atPath: experimentsStoreURL.path(percentEncoded: false))
        let temporaryReceiptStoreURL = backupStoreURL
            .deletingLastPathComponent()
            .appending(path: "ReceiptLedger.store", directoryHint: .notDirectory)
        let temporaryExperimentsStoreURL = backupStoreURL
            .deletingLastPathComponent()
            .appending(path: "Experiments.store", directoryHint: .notDirectory)
        let existingExperimentsBackupURL = experimentsStoreExistedBeforeMigration
            ? backupStoreURL
                .deletingLastPathComponent()
                .appending(path: experimentsStoreURL.lastPathComponent, directoryHint: .notDirectory)
            : nil

        if let existingExperimentsBackupURL {
            try copyStoreCluster(from: experimentsStoreURL, to: existingExperimentsBackupURL, fileManager: fileManager)
        }

        do {
            let receiptCount: Int
            let migratedCount: Int

            do {
                let legacyConfiguration = makeLegacyCombinedStoreConfiguration(
                    storeURL: backupStoreURL,
                    cloudSyncEnabled: false
                )
                let legacyContainer = try ModelContainer(for: legacyCombinedSchema, configurations: [legacyConfiguration])
                let legacyContext = ModelContext(legacyContainer)
                let receiptConfiguration = ModelConfiguration(
                    "ReceiptLedger",
                    schema: receiptLedgerSchema,
                    url: temporaryReceiptStoreURL,
                    cloudKitDatabase: .none
                )
                let receiptContainer = try ModelContainer(
                    for: receiptLedgerSchema,
                    configurations: [receiptConfiguration]
                )
                let experimentsConfiguration = ModelConfiguration(
                    "Experiments",
                    schema: experimentsSchema,
                    url: temporaryExperimentsStoreURL,
                    cloudKitDatabase: .none
                )
                let experimentsContainer = try ModelContainer(
                    for: experimentsSchema,
                    configurations: [experimentsConfiguration]
                )

                receiptCount = try copyReceiptLedgerModels(
                    from: legacyContext,
                    to: ModelContext(receiptContainer)
                )
                migratedCount = try copyExperimentModels(
                    from: legacyContext,
                    to: ModelContext(experimentsContainer)
                )
            }

            try replaceStoreCluster(
                sourceStoreURL: temporaryReceiptStoreURL,
                destinationStoreURL: receiptStoreURL,
                restoreStoreURL: backupStoreURL,
                fileManager: fileManager
            )
            if fileManager.fileExists(atPath: temporaryExperimentsStoreURL.path(percentEncoded: false)) {
                try replaceStoreCluster(
                    sourceStoreURL: temporaryExperimentsStoreURL,
                    destinationStoreURL: experimentsStoreURL,
                    restoreStoreURL: existingExperimentsBackupURL,
                    fileManager: fileManager
                )
            } else {
                removeEmptyStaleExperimentsStoreIfNeeded(
                    experimentsStoreURL: experimentsStoreURL,
                    fileManager: fileManager
                )
            }
            removeStoreCluster(storeURL: temporaryReceiptStoreURL, fileManager: fileManager)
            removeStoreCluster(storeURL: temporaryExperimentsStoreURL, fileManager: fileManager)

            logger.notice("Split legacy combined SwiftData store into \(receiptCount, privacy: .public) receipt records and \(migratedCount, privacy: .public) experiment records")
        } catch {
            removeStoreCluster(storeURL: temporaryReceiptStoreURL, fileManager: fileManager)
            removeStoreCluster(storeURL: temporaryExperimentsStoreURL, fileManager: fileManager)
            if !experimentsStoreExistedBeforeMigration {
                removeStoreCluster(storeURL: experimentsStoreURL, fileManager: fileManager)
            }
            logger.error("Legacy combined-store split failed; restored receipt store backup when possible and removed partial experiment store at \(experimentsStoreURL.path(percentEncoded: false), privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private static func legacyCombinedStoreNeedsSplit(
        storeURL: URL,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: storeURL.path(percentEncoded: false)) else {
            return false
        }

        return sqliteStoreContainsAnyTable(
            named: experimentTableNames,
            at: storeURL
        ) || sqliteStoreMetadataContainsAnyEntity(
            named: experimentEntityNames,
            at: storeURL
        )
    }

    private static func removeEmptyStaleExperimentsStoreIfNeeded(
        experimentsStoreURL: URL,
        fileManager: FileManager
    ) {
        guard fileManager.fileExists(atPath: experimentsStoreURL.path(percentEncoded: false)),
              sqliteStoreContainsAnyTable(named: receiptLedgerTableNames, at: experimentsStoreURL),
              !sqliteStoreContainsAnyRow(in: experimentTableNames, at: experimentsStoreURL) else {
            return
        }

        removeStoreCluster(storeURL: experimentsStoreURL, fileManager: fileManager)
        logger.notice("Removed empty stale experiments store at \(experimentsStoreURL.path(percentEncoded: false), privacy: .public)")
    }

    private static func sqliteStoreContainsAnyTable(
        named tableNames: [String],
        at storeURL: URL
    ) -> Bool {
        guard !tableNames.isEmpty else {
            return false
        }

        var database: OpaquePointer?
        let path = storeURL.path(percentEncoded: false)
        let openResult = sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard openResult == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return false
        }
        defer { sqlite3_close(database) }

        let quotedNames = tableNames
            .map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
            .joined(separator: ",")
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name IN (\(quotedNames)) LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return false
        }
        defer { sqlite3_finalize(statement) }

        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func sqliteStoreContainsAnyRow(
        in tableNames: [String],
        at storeURL: URL
    ) -> Bool {
        guard !tableNames.isEmpty else {
            return false
        }

        var database: OpaquePointer?
        let path = storeURL.path(percentEncoded: false)
        let openResult = sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard openResult == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return false
        }
        defer { sqlite3_close(database) }

        for tableName in tableNames {
            let sql = "SELECT 1 FROM \(tableName) LIMIT 1"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                if let statement {
                    sqlite3_finalize(statement)
                }
                continue
            }
            defer { sqlite3_finalize(statement) }

            if sqlite3_step(statement) == SQLITE_ROW {
                return true
            }
        }

        return false
    }

    private static func sqliteStoreMetadataContainsAnyEntity(
        named entityNames: [String],
        at storeURL: URL
    ) -> Bool {
        guard !entityNames.isEmpty else {
            return false
        }

        var database: OpaquePointer?
        let path = storeURL.path(percentEncoded: false)
        let openResult = sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard openResult == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return false
        }
        defer { sqlite3_close(database) }

        let sql = "SELECT Z_PLIST FROM Z_METADATA LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return false
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 0) else {
            return false
        }

        let byteCount = Int(sqlite3_column_bytes(statement, 0))
        let metadata = Data(bytes: bytes, count: byteCount)
        return entityNames.contains { entityName in
            metadata.range(of: Data(entityName.utf8)) != nil
        }
    }

    private static func copyStoreClusterToMigrationBackup(
        storeURL: URL,
        fileManager: FileManager
    ) throws -> URL {
        let backupRoot = storeURL
            .deletingLastPathComponent()
            .appending(path: migrationBackupDirectoryName, directoryHint: .isDirectory)
            .appending(path: "LegacyCombined-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)", directoryHint: .isDirectory)

        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        let backupStoreURL = backupRoot.appending(path: storeURL.lastPathComponent, directoryHint: .notDirectory)
        try copyStoreCluster(from: storeURL, to: backupStoreURL, fileManager: fileManager)

        return backupStoreURL
    }

    private static func replaceStoreCluster(
        sourceStoreURL: URL,
        destinationStoreURL: URL,
        restoreStoreURL: URL?,
        fileManager: FileManager
    ) throws {
        do {
            removeStoreCluster(storeURL: destinationStoreURL, fileManager: fileManager)
            try copyStoreCluster(from: sourceStoreURL, to: destinationStoreURL, fileManager: fileManager)
        } catch {
            removeStoreCluster(storeURL: destinationStoreURL, fileManager: fileManager)
            if let restoreStoreURL {
                try? copyStoreCluster(from: restoreStoreURL, to: destinationStoreURL, fileManager: fileManager)
            }
            throw error
        }
    }

    private static func copyStoreCluster(
        from sourceStoreURL: URL,
        to destinationStoreURL: URL,
        fileManager: FileManager
    ) throws {
        for suffix in storeClusterSuffixes {
            let sourceURL = storeClusterURL(for: sourceStoreURL, suffix: suffix)
            guard fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false)) else {
                continue
            }

            let destinationURL = storeClusterURL(for: destinationStoreURL, suffix: suffix)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func storeClusterURLs(for storeURL: URL) -> [URL] {
        storeClusterSuffixes.map { storeClusterURL(for: storeURL, suffix: $0) }
    }

    private static let storeClusterSuffixes = ["", "-shm", "-wal"]

    private static func storeClusterURL(for storeURL: URL, suffix: String) -> URL {
        guard !suffix.isEmpty else {
            return storeURL
        }

        return storeURL
            .deletingLastPathComponent()
            .appending(path: "\(storeURL.lastPathComponent)\(suffix)", directoryHint: .notDirectory)
    }

    private static func removeStoreCluster(
        storeURL: URL,
        fileManager: FileManager
    ) {
        for url in storeClusterURLs(for: storeURL) where fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            try? fileManager.removeItem(at: url)
        }
    }

    @discardableResult
    private static func copyReceiptLedgerModels(
        from legacyContext: ModelContext,
        to receiptContext: ModelContext
    ) throws -> Int {
        var migratedCount = 0

        let legacyReceipts = try legacyContext.fetch(FetchDescriptor<Receipt>())
        for legacyReceipt in legacyReceipts {
            let receipt = Receipt(
                id: legacyReceipt.id,
                importedAt: legacyReceipt.importedAt,
                updatedAt: legacyReceipt.updatedAt,
                reviewStatus: legacyReceipt.reviewStatus,
                importSource: legacyReceipt.importSource,
                transactionKind: legacyReceipt.transactionKind,
                processingState: legacyReceipt.processingState,
                merchantName: legacyReceipt.merchantName,
                itemDescription: legacyReceipt.itemDescription,
                transactionDate: legacyReceipt.transactionDate,
                totalAmount: legacyReceipt.totalAmount,
                currencyCode: legacyReceipt.currencyCode,
                taxAmount: legacyReceipt.taxAmount,
                category: legacyReceipt.category,
                notes: legacyReceipt.notes,
                extractionConfidence: legacyReceipt.extractionConfidence,
                extractionProvider: legacyReceipt.extractionProvider,
                extractionDecision: legacyReceipt.extractionDecision,
                cloudExtractionAttemptedAt: legacyReceipt.cloudExtractionAttemptedAt,
                cloudExtractionErrorMessage: legacyReceipt.cloudExtractionErrorMessage,
                searchText: legacyReceipt.searchText,
                expenseType: legacyReceipt.expenseType,
                taxCategory: legacyReceipt.taxCategory,
                sourceProvider: legacyReceipt.sourceProvider,
                sourceOrderID: legacyReceipt.sourceOrderID,
                sourceEmailID: legacyReceipt.sourceEmailID
            )
            receipt.reviewedAt = legacyReceipt.reviewedAt
            receipt.reviewStatusRawValue = legacyReceipt.reviewStatusRawValue
            receipt.importSourceRawValue = legacyReceipt.importSourceRawValue
            receipt.transactionKindRawValue = legacyReceipt.transactionKindRawValue
            receipt.processingStateRawValue = legacyReceipt.processingStateRawValue
            receipt.processingErrorMessage = legacyReceipt.processingErrorMessage
            receipt.extractionProviderRawValue = legacyReceipt.extractionProviderRawValue
            receipt.extractionDecisionRawValue = legacyReceipt.extractionDecisionRawValue
            receipt.expenseTypeRawValue = legacyReceipt.expenseTypeRawValue
            receipt.taxCategoryRawValue = legacyReceipt.taxCategoryRawValue
            receipt.sourceProviderRawValue = legacyReceipt.sourceProviderRawValue

            receiptContext.insert(receipt)

            if let legacyAsset = legacyReceipt.asset {
                let asset = ReceiptAsset(
                    id: legacyAsset.id,
                    receiptID: legacyAsset.receiptID,
                    createdAt: legacyAsset.createdAt,
                    kind: legacyAsset.kind,
                    originalFilename: legacyAsset.originalFilename,
                    contentTypeIdentifier: legacyAsset.contentTypeIdentifier,
                    fileSizeBytes: legacyAsset.fileSizeBytes,
                    storageRelativePath: legacyAsset.storageRelativePath,
                    thumbnailRelativePath: legacyAsset.thumbnailRelativePath
                )
                asset.kindRawValue = legacyAsset.kindRawValue
                asset.receipt = receipt
                receipt.asset = asset
                receiptContext.insert(asset)
            }

            if let legacyOCRResult = legacyReceipt.ocrResult {
                let ocrResult = OCRResult(
                    id: legacyOCRResult.id,
                    createdAt: legacyOCRResult.createdAt,
                    rawText: legacyOCRResult.rawText,
                    confidence: legacyOCRResult.confidence
                )
                ocrResult.receipt = receipt
                receipt.ocrResult = ocrResult
                receiptContext.insert(ocrResult)
            }

            migratedCount += 1
        }

        try receiptContext.save()
        return migratedCount
    }

    @discardableResult
    private static func copyExperimentModels(
        from legacyContext: ModelContext,
        to experimentContext: ModelContext
    ) throws -> Int {
        var migratedCount = 0

        let legacyConnections = try legacyContext.fetch(FetchDescriptor<Connection>())
        var connectionByID: [UUID: Connection] = [:]
        for legacyConnection in legacyConnections {
            let connection = Connection(
                id: legacyConnection.id,
                provider: legacyConnection.provider,
                createdAt: legacyConnection.createdAt,
                lastSyncAt: legacyConnection.lastSyncAt,
                syncEnabled: legacyConnection.syncEnabled,
                credentialsID: legacyConnection.credentialsID,
                refreshTokenID: legacyConnection.refreshTokenID,
                syncIntervalSeconds: legacyConnection.syncIntervalSeconds,
                lastError: legacyConnection.lastError,
                lastSyncStatus: legacyConnection.lastSyncStatus
            )
            connection.providerRawValue = legacyConnection.providerRawValue
            connection.lastSyncStatusRawValue = legacyConnection.lastSyncStatusRawValue
            experimentContext.insert(connection)
            connectionByID[connection.id] = connection
            migratedCount += 1
        }

        for legacySyncLog in try legacyContext.fetch(FetchDescriptor<SyncLog>()) {
            let syncLog = SyncLog(
                id: legacySyncLog.id,
                connectionID: legacySyncLog.connectionID,
                startedAt: legacySyncLog.startedAt,
                completedAt: legacySyncLog.completedAt,
                status: legacySyncLog.status,
                itemsFound: legacySyncLog.itemsFound,
                itemsImported: legacySyncLog.itemsImported,
                errorMessage: legacySyncLog.errorMessage
            )
            syncLog.statusRawValue = legacySyncLog.statusRawValue
            syncLog.connection = connectionByID[legacySyncLog.connectionID]
            experimentContext.insert(syncLog)
            migratedCount += 1
        }

        for account in try legacyContext.fetch(FetchDescriptor<AccountingAccount>()) {
            let copy = AccountingAccount(
                id: account.id,
                code: account.code,
                name: account.name,
                accountType: account.accountType,
                openingBalanceHKD: account.openingBalanceHKD,
                isActive: account.isActive,
                createdAt: account.createdAt
            )
            copy.accountTypeRawValue = account.accountTypeRawValue
            experimentContext.insert(copy)
            migratedCount += 1
        }

        for transaction in try legacyContext.fetch(FetchDescriptor<BankTransaction>()) {
            let copy = BankTransaction(
                id: transaction.id,
                accountName: transaction.accountName,
                postedAt: transaction.postedAt,
                descriptionText: transaction.descriptionText,
                amountHKD: transaction.amountHKD,
                status: transaction.status,
                matchedReceiptID: transaction.matchedReceiptID,
                suggestedCategory: transaction.suggestedCategory,
                importedAt: transaction.importedAt
            )
            copy.statusRawValue = transaction.statusRawValue
            experimentContext.insert(copy)
            migratedCount += 1
        }

        for client in try legacyContext.fetch(FetchDescriptor<ClientRecord>()) {
            experimentContext.insert(ClientRecord(
                id: client.id,
                name: client.name,
                email: client.email,
                notes: client.notes,
                createdAt: client.createdAt
            ))
            migratedCount += 1
        }

        for project in try legacyContext.fetch(FetchDescriptor<ProjectRecord>()) {
            experimentContext.insert(ProjectRecord(
                id: project.id,
                name: project.name,
                clientName: project.clientName,
                budgetHKD: project.budgetHKD,
                isActive: project.isActive,
                createdAt: project.createdAt
            ))
            migratedCount += 1
        }

        for invoice in try legacyContext.fetch(FetchDescriptor<InvoiceRecord>()) {
            let copy = InvoiceRecord(
                id: invoice.id,
                invoiceNumber: invoice.invoiceNumber,
                clientName: invoice.clientName,
                projectName: invoice.projectName,
                issueDate: invoice.issueDate,
                dueDate: invoice.dueDate,
                amountHKD: invoice.amountHKD,
                status: invoice.status,
                paidAt: invoice.paidAt,
                notes: invoice.notes
            )
            copy.statusRawValue = invoice.statusRawValue
            experimentContext.insert(copy)
            migratedCount += 1
        }

        for bill in try legacyContext.fetch(FetchDescriptor<BillRecord>()) {
            let copy = BillRecord(
                id: bill.id,
                vendorName: bill.vendorName,
                billNumber: bill.billNumber,
                dueDate: bill.dueDate,
                amountHKD: bill.amountHKD,
                category: bill.category,
                status: bill.status,
                paidAt: bill.paidAt,
                notes: bill.notes
            )
            copy.statusRawValue = bill.statusRawValue
            experimentContext.insert(copy)
            migratedCount += 1
        }

        for timeEntry in try legacyContext.fetch(FetchDescriptor<TimeEntryRecord>()) {
            experimentContext.insert(TimeEntryRecord(
                id: timeEntry.id,
                projectName: timeEntry.projectName,
                workDate: timeEntry.workDate,
                hours: timeEntry.hours,
                hourlyRateHKD: timeEntry.hourlyRateHKD,
                notes: timeEntry.notes,
                isBilled: timeEntry.isBilled
            ))
            migratedCount += 1
        }

        for mileageTrip in try legacyContext.fetch(FetchDescriptor<MileageTripRecord>()) {
            experimentContext.insert(MileageTripRecord(
                id: mileageTrip.id,
                projectName: mileageTrip.projectName,
                tripDate: mileageTrip.tripDate,
                distanceKM: mileageTrip.distanceKM,
                ratePerKMHKD: mileageTrip.ratePerKMHKD,
                purpose: mileageTrip.purpose,
                isReimbursed: mileageTrip.isReimbursed
            ))
            migratedCount += 1
        }

        for recurringRule in try legacyContext.fetch(FetchDescriptor<RecurringRuleRecord>()) {
            let copy = RecurringRuleRecord(
                id: recurringRule.id,
                title: recurringRule.title,
                transactionKind: recurringRule.transactionKind,
                amountHKD: recurringRule.amountHKD,
                category: recurringRule.category,
                interval: recurringRule.interval,
                nextRunAt: recurringRule.nextRunAt,
                isEnabled: recurringRule.isEnabled
            )
            copy.transactionKindRawValue = recurringRule.transactionKindRawValue
            copy.intervalRawValue = recurringRule.intervalRawValue
            experimentContext.insert(copy)
            migratedCount += 1
        }

        for accountingRule in try legacyContext.fetch(FetchDescriptor<AccountingRuleRecord>()) {
            let copy = AccountingRuleRecord(
                id: accountingRule.id,
                merchantContains: accountingRule.merchantContains,
                category: accountingRule.category,
                expenseType: accountingRule.expenseType,
                taxCategory: accountingRule.taxCategory,
                isEnabled: accountingRule.isEnabled
            )
            copy.expenseTypeRawValue = accountingRule.expenseTypeRawValue
            copy.taxCategoryRawValue = accountingRule.taxCategoryRawValue
            experimentContext.insert(copy)
            migratedCount += 1
        }

        for journalEntry in try legacyContext.fetch(FetchDescriptor<JournalEntryRecord>()) {
            experimentContext.insert(JournalEntryRecord(
                id: journalEntry.id,
                entryDate: journalEntry.entryDate,
                memo: journalEntry.memo,
                debitAccountName: journalEntry.debitAccountName,
                creditAccountName: journalEntry.creditAccountName,
                amountHKD: journalEntry.amountHKD,
                createdAt: journalEntry.createdAt
            ))
            migratedCount += 1
        }

        for payrollRun in try legacyContext.fetch(FetchDescriptor<PayrollRunRecord>()) {
            let copy = PayrollRunRecord(
                id: payrollRun.id,
                payDate: payrollRun.payDate,
                employeeName: payrollRun.employeeName,
                grossPayHKD: payrollRun.grossPayHKD,
                employerCostHKD: payrollRun.employerCostHKD,
                status: payrollRun.status,
                notes: payrollRun.notes
            )
            copy.statusRawValue = payrollRun.statusRawValue
            experimentContext.insert(copy)
            migratedCount += 1
        }

        for item in try legacyContext.fetch(FetchDescriptor<InventoryItemRecord>()) {
            experimentContext.insert(InventoryItemRecord(
                id: item.id,
                sku: item.sku,
                name: item.name,
                quantityOnHand: item.quantityOnHand,
                unitCostHKD: item.unitCostHKD,
                reorderPoint: item.reorderPoint,
                isActive: item.isActive
            ))
            migratedCount += 1
        }

        try experimentContext.save()
        return migratedCount
    }

}
