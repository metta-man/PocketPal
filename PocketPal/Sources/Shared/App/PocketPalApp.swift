import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct PocketPalApp: App {
    private let container: ModelContainer
    private let services: ServiceContainer

    init() {
        do {
            container = try PocketPalModelContainer.make()
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }

        services = ServiceContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.serviceContainer, services)
        }
        #if os(iOS)
        .defaultSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        .windowResizability(.contentMinSize)
        #endif
        .modelContainer(container)
    }
}
