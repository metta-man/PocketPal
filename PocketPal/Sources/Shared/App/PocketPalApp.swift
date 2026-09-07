import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct PocketPalApp: App {
    private let container: ModelContainer?
    private let experimentsContainer: ModelContainer?
    private let loadError: Error?
    private let experimentsLoadError: Error?
    private let services: ServiceContainer

    init() {
        services = ServiceContainer()
        do {
            container = try PocketPalModelContainer.make(cloudSyncEnabled: CloudSyncConfiguration.isEnabled)
            loadError = nil
        } catch {
            // Do NOT silently fall back to an editable in-memory store for
            // production launches — that would hide the failure and risk
            // presenting an empty app as if real data were gone. Instead,
            // surface a blocking recovery state.
            container = nil
            loadError = error
        }

        #if os(macOS)
        if InfrastructureFeatureFlags.accountingWorkspaceEnabled {
            do {
                experimentsContainer = try PocketPalModelContainer.makeExperiments()
                experimentsLoadError = nil
            } catch {
                experimentsContainer = nil
                experimentsLoadError = error
            }
        } else {
            experimentsContainer = nil
            experimentsLoadError = nil
        }
        #else
        experimentsContainer = nil
        experimentsLoadError = nil
        #endif
    }

    var body: some Scene {
        WindowGroup {
            appRoot
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        #endif
        #if os(iOS)
        .defaultSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        .windowResizability(.contentMinSize)
        #endif

        #if os(macOS)
        Settings {
            settingsRoot
        }
        #endif
    }

    @ViewBuilder
    private var appRoot: some View {
        if let container {
            #if os(macOS)
            MacWorkspaceView(
                experimentsContainer: experimentsContainer,
                experimentsLoadError: experimentsLoadError
            )
                .environment(\.serviceContainer, services)
                .modelContainer(container)
            #else
            RootTabView()
                .environment(\.serviceContainer, services)
                .modelContainer(container)
            #endif
        } else {
            PersistentStoreErrorView(error: loadError)
                .environment(\.serviceContainer, services)
        }
    }

    #if os(macOS)
    @ViewBuilder
    private var settingsRoot: some View {
        if let container {
            SettingsView()
                .environment(\.serviceContainer, services)
                .modelContainer(container)
        } else {
            PersistentStoreErrorView(error: loadError)
                .environment(\.serviceContainer, services)
        }
    }
    #endif
}
