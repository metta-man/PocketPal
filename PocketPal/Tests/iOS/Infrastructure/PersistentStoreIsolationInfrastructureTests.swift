import Foundation
import SQLite3
import SwiftData
import XCTest
@testable import PocketPal

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
final class PersistentStoreIsolationInfrastructureTests: XCTestCase {
    func testProductionReceiptAndExperimentContainersUseSeparateStores() throws {
        let fileManager = FileManager.default
        let storeRootDirectory = fileManager.temporaryDirectory
            .appending(path: "PocketPalStoreIsolation-\(UUID().uuidString)", directoryHint: .isDirectory)
        setenv("POCKETPAL_STORE_ROOT_OVERRIDE", storeRootDirectory.path(percentEncoded: false), 1)
        addTeardownBlock {
            unsetenv("POCKETPAL_STORE_ROOT_OVERRIDE")
            try? Self.removeStoreDirectory(storeRootDirectory, fileManager: fileManager)
        }

        let storeDirectory = storeRootDirectory.appending(path: "PocketPal", directoryHint: .isDirectory)
        let receiptStoreURL = storeDirectory.appending(path: "PocketPal.store", directoryHint: .notDirectory)
        let experimentsStoreURL = storeDirectory.appending(path: "PocketPalExperiments.store", directoryHint: .notDirectory)
        let receiptID = UUID()
        let connectionID = UUID()
        let accountID = UUID()

        var receiptContainer: ModelContainer? = try PocketPalModelContainer.make(
            isStoredInMemoryOnly: false,
            cloudSyncEnabled: false
        )
        var receiptContext = receiptContainer.map(ModelContext.init)
        let receipt = Receipt(
            id: receiptID,
            importSource: .manual,
            processingState: .ready,
            merchantName: "Receipt Ledger",
            totalAmount: 12,
            currencyCode: Currency.hkd.rawValue
        )
        receiptContext?.insert(receipt)
        try receiptContext?.save()

        var experimentsContainer: ModelContainer? = try PocketPalModelContainer.makeExperiments()
        var experimentsContext = experimentsContainer.map(ModelContext.init)
        let connection = Connection(
            id: connectionID,
            provider: .gmail,
            syncEnabled: false,
            credentialsID: "experiment-credentials",
            lastSyncStatus: .idle
        )
        let account = AccountingAccount(
            id: accountID,
            code: "6000",
            name: "Experimental Expense",
            accountType: .expense,
            openingBalanceHKD: 1
        )
        experimentsContext?.insert(connection)
        experimentsContext?.insert(account)
        try experimentsContext?.save()

        XCTAssertEqual(try XCTUnwrap(receiptContext).fetch(FetchDescriptor<Receipt>()).map(\.id), [receiptID])
        XCTAssertEqual(try XCTUnwrap(experimentsContext).fetch(FetchDescriptor<Connection>()).map(\.id), [connectionID])
        XCTAssertEqual(try XCTUnwrap(experimentsContext).fetch(FetchDescriptor<AccountingAccount>()).map(\.id), [accountID])

        receiptContext = nil
        receiptContainer = nil
        experimentsContext = nil
        experimentsContainer = nil

        XCTAssertTrue(fileManager.fileExists(atPath: receiptStoreURL.path(percentEncoded: false)))
        XCTAssertTrue(fileManager.fileExists(atPath: experimentsStoreURL.path(percentEncoded: false)))
        XCTAssertTrue(Self.sqliteTableExists("ZRECEIPT", at: receiptStoreURL))
        XCTAssertFalse(Self.sqliteTableExists("ZCONNECTION", at: receiptStoreURL))
        XCTAssertFalse(Self.sqliteTableExists("ZACCOUNTINGACCOUNT", at: receiptStoreURL))
        XCTAssertTrue(Self.sqliteTableExists("ZCONNECTION", at: experimentsStoreURL))
        XCTAssertTrue(Self.sqliteTableExists("ZACCOUNTINGACCOUNT", at: experimentsStoreURL))
        XCTAssertFalse(Self.sqliteTableExists("ZRECEIPT", at: experimentsStoreURL))
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
