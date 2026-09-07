#if os(macOS)
import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import PocketPal

@MainActor
final class MacAccountingWorkspaceInfrastructureTests: XCTestCase {
    func testPersonalAndBusinessWindowsRenderIndependently() async throws {
        let container = try PocketPalModelContainer.make(isStoredInMemoryOnly: true, cloudSyncEnabled: false)
        var hosts: [NSHostingView<AnyView>] = []
        let sessions = [ReceiptWorkspaceSession(), ReceiptWorkspaceSession()]
        for (index, ledger) in ReceiptLedger.allCases.enumerated() {
            for dark in [false, true] {
                let view = MacWorkspaceContentView(
                    selectedDestinationRaw: .constant("overview"), ledger: .constant(ledger), workspace: sessions[index])
                    .modelContainer(container)
                    .environment(\.colorScheme, dark ? .dark : .light)
                let host = NSHostingView(rootView: AnyView(view))
                host.frame = NSRect(x: 0, y: 0, width: 1080, height: 760)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds: 300_000_000)
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let image = NSImage(size: host.bounds.size); image.addRepresentation(bitmap)
                let attachment = XCTAttachment(image: image)
                attachment.name = "mac-\(ledger.rawValue)-\(dark ? "dark" : "light")"
                attachment.lifetime = .keepAlways; add(attachment)
                hosts.append(host)
                window.orderOut(nil)
                window.contentView = nil
                window.close()
            }
        }
        sessions[0].filters[.personal] = .pending
        XCTAssertTrue(sessions[1].filters.isEmpty)
        hosts.removeAll()
    }

    func testDefaultWorkspaceIgnoresAccountingDestinationsAndRendersReceiptLedger() throws {
        setenv("POCKETPAL_ENABLE_ACCOUNTING_WORKSPACE", "0", 1)
        addTeardownBlock {
            unsetenv("POCKETPAL_ENABLE_ACCOUNTING_WORKSPACE")
        }

        XCTAssertFalse(InfrastructureFeatureFlags.accountingWorkspaceEnabled)
        XCTAssertEqual(MacWorkspaceDestination.enabledDestinations, [.overview, .receipts, .archive, .insights, .tax, .settings])
        XCTAssertFalse(MacWorkspaceDestination.enabledDestinations.contains(.banking))

        var receiptContainer: ModelContainer? = try PocketPalModelContainer.make(
            isStoredInMemoryOnly: true,
            cloudSyncEnabled: false
        )

        let view = MacWorkspaceContentView(
            experimentsContainer: nil,
            experimentsLoadError: nil,
            selectedDestinationRaw: .constant(MacWorkspaceDestination.banking.rawValue),
            selectedDestinationOverride: .banking
        )
        .modelContainer(try XCTUnwrap(receiptContainer))

        var host: NSHostingView<AnyView>? = NSHostingView(rootView: AnyView(view))
        host?.frame = NSRect(x: 0, y: 0, width: 1_080, height: 760)
        host?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host?.layoutSubtreeIfNeeded()

        host = nil
        receiptContainer = nil
    }

    func testFlagOnAccountingWorkspaceRendersWithExperimentStoreContainer() throws {
        setenv("POCKETPAL_ENABLE_ACCOUNTING_WORKSPACE", "1", 1)
        addTeardownBlock {
            unsetenv("POCKETPAL_ENABLE_ACCOUNTING_WORKSPACE")
        }

        XCTAssertTrue(InfrastructureFeatureFlags.accountingWorkspaceEnabled)
        XCTAssertTrue(MacWorkspaceDestination.enabledDestinations.contains(.banking))

        var receiptContainer: ModelContainer? = try PocketPalModelContainer.make(
            isStoredInMemoryOnly: true,
            cloudSyncEnabled: false
        )
        var experimentsContainer: ModelContainer? = try PocketPalModelContainer.makeExperiments(
            isStoredInMemoryOnly: true
        )
        var experimentsContext: ModelContext? = try XCTUnwrap(experimentsContainer).mainContext
        let accountID = UUID()
        experimentsContext?.insert(AccountingAccount(
            id: accountID,
            code: "6000",
            name: "Flag-On Workspace Expense",
            accountType: .expense
        ))
        try experimentsContext?.save()

        let view = MacWorkspaceContentView(
            experimentsContainer: try XCTUnwrap(experimentsContainer),
            experimentsLoadError: nil,
            selectedDestinationRaw: .constant(MacWorkspaceDestination.banking.rawValue),
            selectedDestinationOverride: .banking
        )
        .modelContainer(try XCTUnwrap(receiptContainer))

        var host: NSHostingView<AnyView>? = NSHostingView(rootView: AnyView(view))
        host?.frame = NSRect(x: 0, y: 0, width: 1_080, height: 760)
        host?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host?.layoutSubtreeIfNeeded()

        let accounts = try XCTUnwrap(experimentsContext).fetch(FetchDescriptor<AccountingAccount>())
        XCTAssertEqual(accounts.map(\.id), [accountID])

        host = nil
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        experimentsContext = nil
        receiptContainer = nil
        experimentsContainer = nil
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
}
#endif
