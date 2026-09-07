import Foundation
import SQLite3
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import PocketPal

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
final class LegacyStoreMigrationInfrastructureTests: XCTestCase {
    func testLegacyCombinedStoreSplitsReceiptLedgerAndExperimentModels() throws {
        let fileManager = FileManager.default
        let storeRootDirectory = fileManager.temporaryDirectory
            .appending(path: "PocketPalStoreMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        setenv("POCKETPAL_STORE_ROOT_OVERRIDE", storeRootDirectory.path(percentEncoded: false), 1)
        addTeardownBlock {
            unsetenv("POCKETPAL_STORE_ROOT_OVERRIDE")
            try? Self.removeStoreDirectory(storeRootDirectory, fileManager: fileManager)
        }

        let storeDirectory = storeRootDirectory.appending(path: "PocketPal", directoryHint: .isDirectory)
        let receiptStoreURL = storeDirectory.appending(path: "PocketPal.store", directoryHint: .notDirectory)
        let experimentsStoreURL = storeDirectory.appending(path: "PocketPalExperiments.store", directoryHint: .notDirectory)
        let backupDirectory = storeDirectory.appending(path: "MigrationBackups", directoryHint: .isDirectory)
        let receiptID = UUID()
        let assetID = UUID()
        let ocrID = UUID()
        let connectionID = UUID()

        try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

        try Self.createLegacyCombinedStore(
            at: receiptStoreURL,
            receiptID: receiptID,
            assetID: assetID,
            ocrID: ocrID,
            connectionID: connectionID
        )

        var receiptContainer: ModelContainer? = try PocketPalModelContainer.make(
            isStoredInMemoryOnly: false,
            cloudSyncEnabled: false
        )
        var receiptContext = receiptContainer.map(ModelContext.init)
        let receipts = try XCTUnwrap(receiptContext).fetch(FetchDescriptor<Receipt>())

        XCTAssertEqual(receipts.count, 1)
        let receipt = try XCTUnwrap(receipts.first)
        XCTAssertEqual(receipt.id, receiptID)
        XCTAssertEqual(receipt.merchantName, "Legacy Store")
        XCTAssertEqual(receipt.totalAmount, 88.8)
        XCTAssertEqual(receipt.asset?.id, assetID)
        XCTAssertEqual(receipt.asset?.storageRelativePath, "\(receiptID.uuidString)/original.jpg")
        XCTAssertEqual(receipt.ocrResult?.id, ocrID)
        XCTAssertEqual(receipt.ocrResult?.rawText, "Legacy Store\nTOTAL HKD 88.80")

        var experimentsContainer: ModelContainer? = try PocketPalModelContainer.makeExperiments()
        var experimentsContext = experimentsContainer.map(ModelContext.init)
        let connections = try XCTUnwrap(experimentsContext).fetch(FetchDescriptor<Connection>())
        let syncLogs = try XCTUnwrap(experimentsContext).fetch(FetchDescriptor<SyncLog>())

        XCTAssertEqual(connections.count, 1)
        let connection = try XCTUnwrap(connections.first)
        XCTAssertEqual(connection.id, connectionID)
        XCTAssertEqual(connection.provider, .gmail)
        XCTAssertEqual(connection.credentialsID, "legacy-credentials")
        XCTAssertEqual(connection.lastSyncStatus, .completed)
        XCTAssertEqual(syncLogs.count, 1)
        XCTAssertEqual(syncLogs.first?.connectionID, connectionID)
        XCTAssertEqual(syncLogs.first?.connection?.id, connectionID)

        XCTAssertTrue(fileManager.fileExists(atPath: backupDirectory.path(percentEncoded: false)))
        XCTAssertTrue(Self.sqliteTableExists("ZRECEIPT", at: receiptStoreURL))
        XCTAssertFalse(Self.sqliteTableExists("ZCONNECTION", at: receiptStoreURL))
        XCTAssertTrue(Self.sqliteTableExists("ZCONNECTION", at: experimentsStoreURL))
        XCTAssertFalse(Self.sqliteTableExists("ZRECEIPT", at: experimentsStoreURL))

        receiptContext = nil
        receiptContainer = nil
        experimentsContext = nil
        experimentsContainer = nil
    }

    private static let legacyCombinedSchema = Schema([
        Receipt.self,
        ReceiptAsset.self,
        OCRResult.self,
        Connection.self,
        SyncLog.self,
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
    ])

    private static func createLegacyCombinedStore(
        at storeURL: URL,
        receiptID: UUID,
        assetID: UUID,
        ocrID: UUID,
        connectionID: UUID
    ) throws {
        var container: ModelContainer? = try ModelContainer(
            for: legacyCombinedSchema,
            configurations: [
                ModelConfiguration(
                    schema: legacyCombinedSchema,
                    url: storeURL,
                    cloudKitDatabase: .none
                )
            ]
        )
        var context: ModelContext? = container.map(ModelContext.init)
        let importedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let receipt = Receipt(
            id: receiptID,
            importedAt: importedAt,
            updatedAt: importedAt,
            reviewStatus: .reviewed,
            importSource: .files,
            transactionKind: .expense,
            processingState: .ready,
            merchantName: "Legacy Store",
            itemDescription: "Migrated receipt",
            transactionDate: importedAt,
            totalAmount: 88.8,
            currencyCode: Currency.hkd.rawValue,
            taxAmount: nil,
            category: ReceiptCategory.office.rawValue,
            notes: "Created by legacy migration test",
            extractionConfidence: 0.91,
            extractionProvider: .localRules,
            extractionDecision: .acceptedLocal,
            searchText: "Legacy Store\nMigrated receipt"
        )
        let asset = ReceiptAsset(
            id: assetID,
            receiptID: receiptID,
            createdAt: importedAt,
            kind: .image,
            originalFilename: "legacy.jpg",
            contentTypeIdentifier: UTType.jpeg.identifier,
            fileSizeBytes: 12_345,
            storageRelativePath: "\(receiptID.uuidString)/original.jpg",
            thumbnailRelativePath: "\(receiptID.uuidString)/thumbnail.jpg"
        )
        let ocrResult = OCRResult(
            id: ocrID,
            createdAt: importedAt,
            rawText: "Legacy Store\nTOTAL HKD 88.80",
            confidence: 0.89
        )
        let connection = Connection(
            id: connectionID,
            provider: .gmail,
            createdAt: importedAt,
            lastSyncAt: importedAt,
            syncEnabled: true,
            credentialsID: "legacy-credentials",
            refreshTokenID: "legacy-refresh",
            syncIntervalSeconds: 1_800,
            lastError: nil,
            lastSyncStatus: .completed
        )
        let syncLog = SyncLog(
            connectionID: connectionID,
            startedAt: importedAt,
            completedAt: importedAt.addingTimeInterval(3),
            status: .completed,
            itemsFound: 2,
            itemsImported: 1
        )

        asset.receipt = receipt
        receipt.asset = asset
        ocrResult.receipt = receipt
        receipt.ocrResult = ocrResult
        syncLog.connection = connection
        connection.syncLogs = [syncLog]

        context?.insert(receipt)
        context?.insert(asset)
        context?.insert(ocrResult)
        context?.insert(connection)
        context?.insert(syncLog)
        try context?.save()

        context = nil
        container = nil
    }

    private static func removeStoreDirectory(_ url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return
        }

        try fileManager.removeItem(at: url)
    }

    private static func sqliteTableExists(_ tableName: String, at storeURL: URL) -> Bool {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            storeURL.path(percentEncoded: false),
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return false
        }
        defer { sqlite3_close(database) }

        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return false
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, tableName, -1, sqliteTransient)
        return sqlite3_step(statement) == SQLITE_ROW
    }
}
