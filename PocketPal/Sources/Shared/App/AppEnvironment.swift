import SwiftUI

private struct ServiceContainerKey: EnvironmentKey {
    static let defaultValue = ServiceContainer()
}

extension EnvironmentValues {
    var serviceContainer: ServiceContainer {
        get { self[ServiceContainerKey.self] }
        set { self[ServiceContainerKey.self] = newValue }
    }
}
