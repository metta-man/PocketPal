import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct StoredReceiptFile {
    let relativePath: String
    let thumbnailRelativePath: String?
    let originalFilename: String
    let contentType: UTType
    let kind: ReceiptAssetKind
    let fileSizeBytes: Int64
}

protocol ReceiptFileStorageServicing {
    func storeImportedFile(from sourceURL: URL, receiptID: UUID) throws -> StoredReceiptFile
    func storeImportedData(_ document: ImportedReceiptDocument, receiptID: UUID) throws -> StoredReceiptFile
    func fileURL(forRelativePath relativePath: String) -> URL
}

final class ReceiptFileStorageService: ReceiptFileStorageServicing {
    private let fileManager: FileManager
    private let applicationSupportName = "PocketPal"
    private let receiptsFolderName = "Receipts"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func storeImportedFile(from sourceURL: URL, receiptID: UUID) throws -> StoredReceiptFile {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let contentType = try contentType(for: sourceURL)
        let originalFilename = sourceURL.lastPathComponent
        let fileExtension = preferredFileExtension(for: contentType, fallback: sourceURL.pathExtension)
        let destinationURL = try receiptDirectory(for: receiptID).appending(path: "original.\(fileExtension)")

        if fileManager.fileExists(atPath: destinationURL.path()) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        let thumbnailRelativePath = try generateThumbnailIfPossible(sourceURL: destinationURL, receiptID: receiptID)
        let fileSizeBytes = try fileSize(for: destinationURL)

        return StoredReceiptFile(
            relativePath: relativePath(for: destinationURL),
            thumbnailRelativePath: thumbnailRelativePath,
            originalFilename: originalFilename,
            contentType: contentType,
            kind: assetKind(for: contentType),
            fileSizeBytes: fileSizeBytes
        )
    }

    func storeImportedData(_ document: ImportedReceiptDocument, receiptID: UUID) throws -> StoredReceiptFile {
        let fileExtension = preferredFileExtension(for: document.contentType, fallback: "bin")
        let receiptDirectory = try receiptDirectory(for: receiptID)
        let destinationURL = receiptDirectory.appending(path: "original.\(fileExtension)")

        try document.data.write(to: destinationURL, options: .atomic)
        let thumbnailRelativePath = try generateThumbnailIfPossible(sourceURL: destinationURL, receiptID: receiptID)
        let fileSizeBytes = try fileSize(for: destinationURL)

        return StoredReceiptFile(
            relativePath: relativePath(for: destinationURL),
            thumbnailRelativePath: thumbnailRelativePath,
            originalFilename: document.suggestedFilename,
            contentType: document.contentType,
            kind: assetKind(for: document.contentType),
            fileSizeBytes: fileSizeBytes
        )
    }

    func fileURL(forRelativePath relativePath: String) -> URL {
        baseDirectory().appending(path: relativePath)
    }

    private func receiptDirectory(for receiptID: UUID) throws -> URL {
        let directory = baseDirectory().appending(path: receiptID.uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func baseDirectory() -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = appSupport
            .appending(path: applicationSupportName, directoryHint: .isDirectory)
            .appending(path: receiptsFolderName, directoryHint: .isDirectory)

        if !fileManager.fileExists(atPath: base.path()) {
            try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        }

        return base
    }

    private func relativePath(for absoluteURL: URL) -> String {
        absoluteURL.path().replacingOccurrences(of: baseDirectory().path() + "/", with: "")
    }

    private func contentType(for sourceURL: URL) throws -> UTType {
        if let contentType = try sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType
        }

        if let contentType = UTType(filenameExtension: sourceURL.pathExtension) {
            return contentType
        }

        throw CocoaError(.fileReadUnknown)
    }

    private func assetKind(for contentType: UTType) -> ReceiptAssetKind {
        if contentType.conforms(to: .pdf) {
            return .pdf
        }

        return .image
    }

    private func preferredFileExtension(for contentType: UTType, fallback: String) -> String {
        contentType.preferredFilenameExtension ?? fallback
    }

    private func generateThumbnailIfPossible(sourceURL: URL, receiptID: UUID) throws -> String? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 600
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let thumbnailURL = try receiptDirectory(for: receiptID).appending(path: "thumbnail.jpg")
        guard let destination = CGImageDestinationCreateWithURL(thumbnailURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }

        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return relativePath(for: thumbnailURL)
    }

    private func fileSize(for url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }
}
