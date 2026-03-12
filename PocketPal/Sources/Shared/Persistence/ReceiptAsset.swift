import Foundation
import SwiftData

@Model
final class ReceiptAsset {
    @Attribute(.unique) var id: UUID
    var receiptID: UUID
    var createdAt: Date
    var kindRawValue: String
    var originalFilename: String
    var contentTypeIdentifier: String
    var fileSizeBytes: Int64
    var storageRelativePath: String
    var thumbnailRelativePath: String?

    var receipt: Receipt?

    init(
        id: UUID = UUID(),
        receiptID: UUID,
        createdAt: Date = .now,
        kind: ReceiptAssetKind,
        originalFilename: String,
        contentTypeIdentifier: String,
        fileSizeBytes: Int64,
        storageRelativePath: String,
        thumbnailRelativePath: String? = nil
    ) {
        self.id = id
        self.receiptID = receiptID
        self.createdAt = createdAt
        self.kindRawValue = kind.rawValue
        self.originalFilename = originalFilename
        self.contentTypeIdentifier = contentTypeIdentifier
        self.fileSizeBytes = fileSizeBytes
        self.storageRelativePath = storageRelativePath
        self.thumbnailRelativePath = thumbnailRelativePath
    }

    var kind: ReceiptAssetKind {
        get { ReceiptAssetKind(rawValue: kindRawValue) ?? .image }
        set { kindRawValue = newValue.rawValue }
    }
}
