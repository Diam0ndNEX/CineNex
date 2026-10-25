import Foundation
import Security

enum StremioAddonConfigurationStore {
    private static let service = "com.diam0ndnex.cinenex.stremio-addons"
    private static let account = "manifest-urls"
    private static let legacyDefaultsKey = "cinenex.stremioAddonManifestURLs"
    private static let keychain = KeychainStringStore(service: service, account: account)

    static func load() throws -> String? {
        if let value = try keychain.load() {
            return value
        }

        guard let legacyValue = UserDefaults.standard.string(forKey: legacyDefaultsKey) else {
            return nil
        }

        try keychain.save(legacyValue)
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        return legacyValue
    }

    static func save(_ value: String) throws {
        try keychain.save(value)
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }
}

struct KeychainStringStore {
    let service: String
    let account: String

    func load() throws -> String? {
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
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw StremioAddonConfigurationStoreError.keychain(status)
        }
        return value
    }

    func save(_ value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw StremioAddonConfigurationStoreError.encoding
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insertion = query
            attributes.forEach { insertion[$0.key] = $0.value }
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw StremioAddonConfigurationStoreError.keychain(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw StremioAddonConfigurationStoreError.keychain(updateStatus)
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StremioAddonConfigurationStoreError.keychain(status)
        }
    }
}

enum StremioAddonConfigurationStoreError: LocalizedError {
    case keychain(OSStatus)
    case encoding

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "The iOS Keychain operation failed (error \(status))."
        case .encoding:
            return "The add-on configuration could not be encoded for secure storage."
        }
    }
}
