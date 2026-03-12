import Foundation
import SwiftData

@Model
final class SyncLog {
    var id: UUID
    var connectionID: UUID
    var startedAt: Date
    var completedAt: Date?
    var statusRawValue: String
    var itemsFound: Int
    var itemsImported: Int
    var errorMessage: String?

    var connection: Connection?

    init(
        id: UUID = UUID(),
        connectionID: UUID,
        startedAt: Date = .now,
        completedAt: Date? = nil,
        status: SyncStatus = .syncing,
        itemsFound: Int = 0,
        itemsImported: Int = 0,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.connectionID = connectionID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.statusRawValue = status.rawValue
        self.itemsFound = itemsFound
        self.itemsImported = itemsImported
        self.errorMessage = errorMessage
    }

    var status: SyncStatus {
        get { SyncStatus(rawValue: statusRawValue) ?? .idle }
        set { statusRawValue = newValue.rawValue }
    }

    var duration: TimeInterval? {
        guard let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }

    var isComplete: Bool {
        completedAt != nil
    }
}
