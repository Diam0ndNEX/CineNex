import Foundation
import Security

enum TMDBTokenStore {
    private static let service = "com.diam0ndnex.cinenex.tmdb"
    private static let account = "read-access-token"
    private static let legacyDefaultsKey = "cinenex.tmdb.readAccessToken"

    static func load() -> String? {
        if let token = try? readKeychain(), !token.isEmpty {
            return token
        }

        guard let legacyToken = UserDefaults.standard.string(forKey: legacyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !legacyToken.isEmpty else {
            return nil
        }

        do {
            try writeKeychain(legacyToken)
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        } catch {
            return legacyToken
        }
        return legacyToken
    }

    static func save(_ token: String) throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            try delete()
            return
        }

        try writeKeychain(normalizedToken)
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TMDBTokenStoreError.keychain(status)
        }
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    private static func readKeychain() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw TMDBTokenStoreError.keychain(status)
        }
        return token
    }

    private static func writeKeychain(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw TMDBTokenStoreError.encoding
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insertion = query
            attributes.forEach { insertion[$0.key] = $0.value }
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw TMDBTokenStoreError.keychain(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw TMDBTokenStoreError.keychain(updateStatus)
        }
    }
}

enum TMDBTokenStoreError: LocalizedError {
    case keychain(OSStatus)
    case encoding

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain operation failed (error \(status))."
        case .encoding:
            return "The TMDB token could not be encoded for secure storage."
        }
    }
}
