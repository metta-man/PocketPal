#if os(macOS)
import AppKit
import Foundation
import SwiftData
import SwiftUI
import XCTest
@testable import PocketPal

@MainActor
final class MacCoreSettingsInfrastructureTests: XCTestCase {
    func testCollapsedSettingsDoesNotReadCloudAIKeychainState() throws {
        var container: ModelContainer? = try PocketPalModelContainer.make(
            isStoredInMemoryOnly: true,
            cloudSyncEnabled: false
        )
        let keychainService = SpyKeychainService()
        let services = ServiceContainer(keychainService: keychainService)

        let view = SettingsView()
            .environment(\.serviceContainer, services)
            .modelContainer(try XCTUnwrap(container))

        var host: NSHostingView<AnyView>? = NSHostingView(rootView: AnyView(view))
        host?.frame = NSRect(x: 0, y: 0, width: 560, height: 640)
        host?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host?.layoutSubtreeIfNeeded()

        XCTAssertEqual(keychainService.retrieveSecureStringCount, 0)

        host = nil
        container = nil
    }
}

private final class SpyKeychainService: KeychainServicing, @unchecked Sendable {
    private(set) var retrieveSecureStringCount = 0

    func store(key: String, data: Data) throws {}

    func retrieve(key: String) throws -> Data? {
        nil
    }

    func delete(key: String) throws {}

    func storeSecureString(key: String, value: String) throws {}

    func retrieveSecureString(key: String) throws -> String? {
        retrieveSecureStringCount += 1
        return nil
    }
}
#endif
