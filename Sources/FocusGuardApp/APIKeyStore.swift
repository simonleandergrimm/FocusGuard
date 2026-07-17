import Foundation
import Security

enum APIKeyStoreError: LocalizedError {
    case invalidKeyData
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidKeyData:
            "The API key stored in Keychain could not be read. Remove it and save a new key."
        case .keychain(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                "Keychain error: \(message)"
            } else {
                "Keychain returned error \(status)."
            }
        }
    }
}

enum APIKeyStore {
    private static let service = "com.local.FocusGuard.openai"
    private static let account = "openai-api-key"
    private static let legacyDefaultsKey = "openAIAPIKey"

    static func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8)
            else { throw APIKeyStoreError.invalidKeyData }
            return normalized(value)
        case errSecItemNotFound:
            return try migrateLegacyValueIfNeeded()
        default:
            throw APIKeyStoreError.keychain(status)
        }
    }

    static func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw APIKeyStoreError.keychain(status)
            }
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            return
        }

        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw APIKeyStoreError.keychain(updateStatus)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIKeyStoreError.keychain(addStatus)
        }
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func migrateLegacyValueIfNeeded() throws -> String? {
        guard let value = normalized(UserDefaults.standard.string(forKey: legacyDefaultsKey)) else {
            return nil
        }
        try save(value)
        return value
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
