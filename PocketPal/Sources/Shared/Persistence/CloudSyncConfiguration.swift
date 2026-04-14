import Foundation

enum CloudSyncConfiguration {
    static let containerIdentifier = "iCloud.com.lumilux.pocketpal"
    static let userDefaultsKey = "PocketPalCloudSyncEnabled"

    static var isEnabled: Bool {
        if let override = ProcessInfo.processInfo.environment["POCKETPAL_ENABLE_CLOUDKIT"] {
            return override == "1" || override.lowercased() == "true"
        }

        return UserDefaults.standard.bool(forKey: userDefaultsKey)
    }
}
