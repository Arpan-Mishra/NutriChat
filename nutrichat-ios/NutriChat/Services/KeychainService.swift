import Foundation
import OSLog
import Security

private let logger = Logger(subsystem: "app.nutrichat", category: "KeychainService")

/// Thin wrapper around iOS Keychain for storing JWT tokens.
/// Never use UserDefaults for tokens — Keychain only.
enum KeychainService {

    // MARK: - Public API

    /// Save a string value to the Keychain.
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: App.bundleID,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain save failed for \(key, privacy: .public): \(status)")
        }
        return status == errSecSuccess
    }

    /// Load a string value from the Keychain.
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: App.bundleID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Delete a value from the Keychain.
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: App.bundleID,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Token Convenience

    static var accessToken: String? {
        get { load(key: Keychain.accessTokenKey) }
        set {
            if let newValue {
                save(key: Keychain.accessTokenKey, value: newValue)
            } else {
                delete(key: Keychain.accessTokenKey)
            }
        }
    }

    static var refreshToken: String? {
        get { load(key: Keychain.refreshTokenKey) }
        set {
            if let newValue {
                save(key: Keychain.refreshTokenKey, value: newValue)
            } else {
                delete(key: Keychain.refreshTokenKey)
            }
        }
    }

    /// Remove all stored tokens (used on logout).
    static func clearTokens() {
        delete(key: Keychain.accessTokenKey)
        delete(key: Keychain.refreshTokenKey)
        logger.info("All tokens cleared from Keychain")
    }
}
