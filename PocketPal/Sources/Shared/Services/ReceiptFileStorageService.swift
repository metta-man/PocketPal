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
    private let storageRootName = "PocketPal"
    private let receiptsFolderName = "Receipts"
    private let cloudContainerIdentifier: String

    init(
        fileManager: FileManager = .default,
        cloudContainerIdentifier: String = CloudSyncConfiguration.containerIdentifier
    ) {
        self.fileManager = fileManager
        self.cloudContainerIdentifier = cloudContainerIdentifier
    }

    func storeImportedFile(from sourceURL: URL, receiptID: UUID) throws -> StoredReceiptFile {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let contentType = try resolvedContentType(for: sourceURL)
        let originalFilename = sourceURL.lastPathComponent
        let storedContentType = storageContentType(for: contentType)
        let fileExtension = preferredFileExtension(for: storedContentType, fallback: sourceURL.pathExtension)
        let destinationURL = try receiptDirectory(for: receiptID).appending(path: "original.\(fileExtension)")

        if fileManager.fileExists(atPath: destinationURL.path()) {
            try fileManager.removeItem(at: destinationURL)
        }

        try writeImportedFile(from: sourceURL, detectedContentType: contentType, to: destinationURL)
        guard fileManager.fileExists(atPath: destinationURL.path()) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let thumbnailRelativePath = try generateThumbnailIfPossible(sourceURL: destinationURL, receiptID: receiptID)
        let fileSizeBytes = try fileSize(for: destinationURL)

        return StoredReceiptFile(
            relativePath: relativePath(for: destinationURL),
            thumbnailRelativePath: thumbnailRelativePath,
            originalFilename: originalFilename,
            contentType: storedContentType,
            kind: assetKind(for: storedContentType),
            fileSizeBytes: fileSizeBytes
        )
    }

    func storeImportedData(_ document: ImportedReceiptDocument, receiptID: UUID) throws -> StoredReceiptFile {
        let contentType = resolvedContentType(for: document)
        let storedContentType = storageContentType(for: contentType)
        let fileExtension = preferredFileExtension(
            for: storedContentType,
            fallback: URL(filePath: document.suggestedFilename).pathExtension
        )
        let receiptDirectory = try receiptDirectory(for: receiptID)
        let destinationURL = receiptDirectory.appending(path: "original.\(fileExtension)")

        try writeImportedData(document.data, detectedContentType: contentType, to: destinationURL)
        guard fileManager.fileExists(atPath: destinationURL.path()) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let thumbnailRelativePath = try generateThumbnailIfPossible(sourceURL: destinationURL, receiptID: receiptID)
        let fileSizeBytes = try fileSize(for: destinationURL)

        return StoredReceiptFile(
            relativePath: relativePath(for: destinationURL),
            thumbnailRelativePath: thumbnailRelativePath,
            originalFilename: document.suggestedFilename,
            contentType: storedContentType,
            kind: assetKind(for: storedContentType),
            fileSizeBytes: fileSizeBytes
        )
    }

    func fileURL(forRelativePath relativePath: String) -> URL {
        if relativePath.hasPrefix("/") {
            let legacyURL = URL(filePath: relativePath)
            if fileManager.fileExists(atPath: legacyURL.path()) {
                return legacyURL
            }

            if let migratedRelativePath = migratedRelativePath(fromLegacyAbsolutePath: relativePath) {
                return baseDirectory().appending(path: migratedRelativePath)
            }

            return legacyURL
        }

        return baseDirectory().appending(path: relativePath)
    }

    private func receiptDirectory(for receiptID: UUID) throws -> URL {
        let directory = baseDirectory().appending(path: receiptID.uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func baseDirectory() -> URL {
        let localBase = localBaseDirectory()
        let base = preferredBaseDirectory() ?? localBase

        guard let base else {
            return URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
                .appending(path: storageRootName, directoryHint: .isDirectory)
                .appending(path: receiptsFolderName, directoryHint: .isDirectory)
        }

        if let localBase, base != localBase {
            migrateLocalFilesIfNeeded(from: localBase, to: base)
        }

        ensureDirectoryExists(at: base)
        return base
    }

    private func preferredBaseDirectory() -> URL? {
        guard let ubiquityContainer = iCloudBaseDirectory() else {
            return nil
        }

        return ubiquityContainer
            .appending(path: storageRootName, directoryHint: .isDirectory)
            .appending(path: receiptsFolderName, directoryHint: .isDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    private func iCloudBaseDirectory() -> URL? {
        guard fileManager.ubiquityIdentityToken != nil else {
            return nil
        }

        guard let ubiquityContainer = fileManager.url(forUbiquityContainerIdentifier: cloudContainerIdentifier) else {
            return nil
        }

        return ubiquityContainer
            .appending(path: "Documents", directoryHint: .isDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    private func localBaseDirectory() -> URL? {
        guard let appSupport = try? fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }

        return appSupport
            .appending(path: storageRootName, directoryHint: .isDirectory)
            .appending(path: receiptsFolderName, directoryHint: .isDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    private func ensureDirectoryExists(at url: URL) {
        if !fileManager.fileExists(atPath: url.path()) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func migrateLocalFilesIfNeeded(from sourceBase: URL, to destinationBase: URL) {
        guard fileManager.fileExists(atPath: sourceBase.path()) else {
            return
        }

        ensureDirectoryExists(at: destinationBase)

        guard let enumerator = fileManager.enumerator(
            at: sourceBase,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let sourceURL as URL in enumerator {
            let relativePath = sourceURL.path.replacingOccurrences(of: sourceBase.path + "/", with: "")
            let destinationURL = destinationBase.appending(path: relativePath)
            let isDirectory = (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDirectory {
                ensureDirectoryExists(at: destinationURL)
                continue
            }

            guard !fileManager.fileExists(atPath: destinationURL.path()) else {
                continue
            }

            ensureDirectoryExists(at: destinationURL.deletingLastPathComponent())
            try? fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private func relativePath(for absoluteURL: URL) -> String {
        let normalizedAbsoluteURL = absoluteURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let normalizedBaseURL = baseDirectory()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let basePath = normalizedBaseURL.path()
        let absolutePath = normalizedAbsoluteURL.path()

        guard absolutePath.hasPrefix(basePath) else {
            return absolutePath
        }

        let relativePath = String(absolutePath.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relativePath.isEmpty ? normalizedAbsoluteURL.lastPathComponent : relativePath
    }

    private func migratedRelativePath(fromLegacyAbsolutePath absolutePath: String) -> String? {
        let marker = "/\(storageRootName)/\(receiptsFolderName)/"
        guard let markerRange = absolutePath.range(of: marker) else {
            return nil
        }

        let suffix = absolutePath[markerRange.upperBound...]
        let relativePath = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relativePath.isEmpty ? nil : String(relativePath)
    }

    private func contentType(for sourceURL: URL) throws -> UTType {
        if let contentType = try sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType,
           !contentType.isAbstractImageType {
            return contentType
        }

        if let contentType = UTType(filenameExtension: sourceURL.pathExtension) {
            return contentType
        }

        throw CocoaError(.fileReadUnknown)
    }

    private func resolvedContentType(for sourceURL: URL) throws -> UTType {
        let fallbackType = try contentType(for: sourceURL)
        guard fallbackType.isAbstractImageType || sourceURL.pathExtension.isEmpty else {
            return fallbackType
        }

        if let sniffedType = sniffedContentType(for: sourceURL) {
            return sniffedType
        }

        return fallbackType
    }

    private func resolvedContentType(for document: ImportedReceiptDocument) -> UTType {
        if !document.contentType.isAbstractImageType {
            return document.contentType
        }

        if let sniffedType = sniffedContentType(for: document.data) {
            return sniffedType
        }

        return document.contentType
    }

    private func assetKind(for contentType: UTType) -> ReceiptAssetKind {
        if contentType.conforms(to: .pdf) {
            return .pdf
        }

        return .image
    }

    private func preferredFileExtension(for contentType: UTType, fallback: String) -> String {
        contentType.preferredFilenameExtension ?? (fallback.isEmpty ? "bin" : fallback)
    }

    private func storageContentType(for contentType: UTType) -> UTType {
        if contentType.conforms(to: .image) {
            return .jpeg
        }

        return contentType
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

    private func writeImportedFile(from sourceURL: URL, detectedContentType: UTType, to destinationURL: URL) throws {
        guard detectedContentType.conforms(to: .image) else {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return
        }

        let source = try imageSource(from: sourceURL)
        try writeJPEGImage(from: source, to: destinationURL)
    }

    private func writeImportedData(_ data: Data, detectedContentType: UTType, to destinationURL: URL) throws {
        guard detectedContentType.conforms(to: .image) else {
            try data.write(to: destinationURL, options: .atomic)
            return
        }

        let source = try imageSource(from: data)
        try writeJPEGImage(from: source, to: destinationURL)
    }

    private func writeJPEGImage(from source: CGImageSource, to destinationURL: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92
        ]

        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func sniffedContentType(for sourceURL: URL) -> UTType? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String? else {
            return nil
        }

        return UTType(typeIdentifier)
    }

    private func sniffedContentType(for data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String? else {
            return nil
        }

        return UTType(typeIdentifier)
    }

    private func imageSource(from sourceURL: URL) throws -> CGImageSource {
        if let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) {
            return source
        }

        let data = try Data(contentsOf: sourceURL)
        return try imageSource(from: data)
    }

    private func imageSource(from data: Data) throws -> CGImageSource {
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            return source
        }

        throw CocoaError(.fileReadCorruptFile)
    }
}

private extension UTType {
    var isAbstractImageType: Bool {
        self == .image
    }
}
