import Foundation
import Security

public enum KeychainStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.gazitofu.Dama.pyannote",
         kSecAttrAccount as String: "personal-api-key"]
    }
    public static func read() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { throw ManagedFailure.missingKey }
        return key
    }
    public static func save(_ key: String) throws {
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else { throw ManagedFailure.missingKey }
        let value = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = Data(key.utf8)
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw ManagedFailure.missingKey }
        } else if status != errSecSuccess { throw ManagedFailure.missingKey }
    }
    public static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ManagedFailure.missingKey }
    }
}
