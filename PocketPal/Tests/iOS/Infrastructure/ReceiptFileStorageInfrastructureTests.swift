import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import PocketPal

final class ReceiptFileStorageInfrastructureTests: XCTestCase {
    func testDefaultReceiptFileStorageStaysLocalWhenICloudIsAvailable() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "ReceiptFileStorageInfrastructureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let localDocumentsURL = rootURL.appending(path: "LocalDocuments", directoryHint: .isDirectory)
        let ubiquityContainerURL = rootURL.appending(path: "iCloudContainer", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let fileManager = UbiquityAvailableFileManager(
            localDocumentsURL: localDocumentsURL,
            ubiquityContainerURL: ubiquityContainerURL
        )
        let service = ReceiptFileStorageService(fileManager: fileManager)
        let receiptID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000201"))

        let storedFile = try service.storeImportedData(
            ImportedReceiptDocument(
                data: Data("PocketPal local storage test".utf8),
                suggestedFilename: "receipt.txt",
                contentType: .plainText
            ),
            receiptID: receiptID
        )

        let expectedLocalURL = localDocumentsURL
            .appending(path: "PocketPal", directoryHint: .isDirectory)
            .appending(path: "Receipts", directoryHint: .isDirectory)
            .appending(path: receiptID.uuidString, directoryHint: .isDirectory)
            .appending(path: "original.txt")
        let unexpectedICloudURL = ubiquityContainerURL
            .appending(path: "Documents", directoryHint: .isDirectory)
            .appending(path: "PocketPal", directoryHint: .isDirectory)
            .appending(path: "Receipts", directoryHint: .isDirectory)
            .appending(path: receiptID.uuidString, directoryHint: .isDirectory)
            .appending(path: "original.txt")

        XCTAssertEqual(fileManager.ubiquityContainerLookupCount, 0)
        XCTAssertEqual(storedFile.relativePath, "\(receiptID.uuidString)/original.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedLocalURL.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unexpectedICloudURL.path(percentEncoded: false)))
        XCTAssertEqual(
            service.fileURL(forRelativePath: storedFile.relativePath).path(percentEncoded: false),
            expectedLocalURL.path(percentEncoded: false)
        )
    }
}

private final class UbiquityAvailableFileManager: FileManager {
    private let localDocumentsURL: URL
    private let ubiquityContainerURL: URL
    private(set) var ubiquityContainerLookupCount = 0

    init(localDocumentsURL: URL, ubiquityContainerURL: URL) {
        self.localDocumentsURL = localDocumentsURL
        self.ubiquityContainerURL = ubiquityContainerURL
        super.init()
    }

    override var ubiquityIdentityToken: (any NSCoding & NSCopying & NSObjectProtocol)? {
        "signed-in" as NSString
    }

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        guard directory == .documentDirectory, domainMask == .userDomainMask else {
            return try super.url(
                for: directory,
                in: domainMask,
                appropriateFor: url,
                create: shouldCreate
            )
        }

        if shouldCreate {
            try FileManager.default.createDirectory(at: localDocumentsURL, withIntermediateDirectories: true)
        }
        return localDocumentsURL
    }

    override func url(forUbiquityContainerIdentifier containerIdentifier: String?) -> URL? {
        ubiquityContainerLookupCount += 1
        return ubiquityContainerURL
    }
}
