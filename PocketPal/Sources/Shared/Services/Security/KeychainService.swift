import Foundation
import Security

/// Errors that can occur during Keychain operations
enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case duplicateItem
    case invalidParameter
    case operationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Item not found in keychain"
        case .duplicateItem:
            return "Item already exists in keychain"
        case .invalidParameter:
            return "Invalid parameter provided"
        case .operationFailed(let status):
            return "Keychain operation failed with status: \(status)"
        }
    }
}

/// Protocol for Keychain service operations
protocol KeychainServicing: Sendable {
    /// Store data in the keychain
    func store(key: String, data: Data) throws

    /// Retrieve data from the keychain
    func retrieve(key: String) throws -> Data?

    /// Delete an item from the keychain
    func delete(key: String) throws

    /// Store a string value securely
    func storeSecureString(key: String, value: String) throws

    /// Retrieve a secure string value
    func retrieveSecureString(key: String) throws -> String?
}

/// Service for secure storage of OAuth tokens and other credentials
final class KeychainService: KeychainServicing {
    private let serviceIdentifier: String

    init(serviceIdentifier: String = "com.pocketpal.keychain") {
        self.serviceIdentifier = serviceIdentifier
    }

    // MARK: - Data Storage

    func store(key: String, data: Data) throws {
        // First, try to delete any existing item
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.operationFailed(status)
        }
    }

    func retrieve(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.operationFailed(status)
        }

        guard let data = result as? Data else {
            return nil
        }

        return data
    }

    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.operationFailed(status)
        }
    }

    // MARK: - String Convenience Methods

    func storeSecureString(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidParameter
        }
        try store(key: key, data: data)
    }

    func retrieveSecureString(key: String) throws -> String? {
        guard let data = try retrieve(key: key) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidParameter
        }
        return string
    }
}
