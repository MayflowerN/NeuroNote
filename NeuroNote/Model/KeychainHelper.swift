//
//  KeychainHelper.swift
//  NeuroNote
//
//  Created by Ellie on 7/5/25.
//

import Foundation
import Security

/// Utility for securely storing and retrieving strings using Keychain Services API.
enum KeychainHelper {
    /// Saves a value under a key in the iOS Keychain. Overwrites any existing item.
    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Loads a value from Keychain by key, returning `nil` if not found or corrupted.
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }

        return value
    }
}
