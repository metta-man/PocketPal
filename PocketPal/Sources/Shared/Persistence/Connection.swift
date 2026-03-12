import Foundation
import SwiftData

@Model
final class Connection {
    @Attribute(.unique) var id: UUID
    var providerRawValue: String
    var createdAt: Date
    var lastSyncAt: Date?
    var syncEnabled: Bool
    var credentialsID: String  // Keychain item identifier for OAuth tokens
    var refreshTokenID: String?  // Separate keychain ID for refresh token
    var syncIntervalSeconds: Int
    var lastError: String?
    var lastSyncStatusRawValue: String

    @Relationship(deleteRule: .cascade, inverse: \SyncLog.connection) var syncLogs: [SyncLog]

    init(
        id: UUID = UUID(),
        provider: ConnectionProvider,
        createdAt: Date = .now,
        lastSyncAt: Date? = nil,
        syncEnabled: Bool = true,
        credentialsID: String,
        refreshTokenID: String? = nil,
        syncIntervalSeconds: Int = 3600, // Default: 1 hour
        lastError: String? = nil,
        lastSyncStatus: SyncStatus = .idle
    ) {
        self.id = id
        self.providerRawValue = provider.rawValue
        self.createdAt = createdAt
        self.lastSyncAt = lastSyncAt
        self.syncEnabled = syncEnabled
        self.credentialsID = credentialsID
        self.refreshTokenID = refreshTokenID
        self.syncIntervalSeconds = syncIntervalSeconds
        self.lastError = lastError
        self.lastSyncStatusRawValue = lastSyncStatus.rawValue
        self.syncLogs = []
    }

    var provider: ConnectionProvider {
        get { ConnectionProvider(rawValue: providerRawValue) ?? .gmail }
        set { providerRawValue = newValue.rawValue }
    }

    var lastSyncStatus: SyncStatus {
        get { SyncStatus(rawValue: lastSyncStatusRawValue) ?? .idle }
        set { lastSyncStatusRawValue = newValue.rawValue }
    }

    var syncInterval: TimeInterval {
        get { TimeInterval(syncIntervalSeconds) }
        set { syncIntervalSeconds = Int(newValue) }
    }

    var displayName: String {
        provider.displayName
    }

    var isConnected: Bool {
        lastError == nil && lastSyncStatus != .failed
    }
}
