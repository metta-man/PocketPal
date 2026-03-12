import SwiftData
import SwiftUI

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
        .modelContainer(container)
    }
}
