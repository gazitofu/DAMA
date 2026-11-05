import Foundation
import Security
import DamaCore

public enum KeychainStore {
    private static func query(_ provider: TranscriptionProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.gazitofu.Dama.\(provider == .qwen ? "pyannote" : provider.rawValue)",
         kSecAttrAccount as String: "personal-api-key"]
    }
    public static func read(provider: TranscriptionProvider = .pyannote) throws -> String? {
        var q = query(provider)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { throw ManagedFailure.missingKey }
        return key
    }
    /// usage-bundle1: 항목이 있는지만 확인한다. 값을 읽지 않는다(`kSecReturnData` 없음, 반환값은 Bool).
    /// 확인 실패(권한 등)는 «있음»으로 말하지 않는다.
    public static func exists(provider: TranscriptionProvider) -> Bool {
        var q = query(provider)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }
    public static func save(_ key: String, provider: TranscriptionProvider = .pyannote) throws {
        let query = query(provider)
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
    public static func delete(provider: TranscriptionProvider = .pyannote) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ManagedFailure.missingKey }
    }
}
