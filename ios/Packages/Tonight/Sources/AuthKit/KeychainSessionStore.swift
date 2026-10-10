import Foundation
import Security

public struct KeychainSessionError: Error, Equatable {
    public var status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }
}

/// Names the keychain item. The account is a session, never a PIN.
public enum KeychainSessionQuery {
    public static let service = "com.tonight.homework.parent-session"
    public static let account = "session"
    public static let storesPIN = false

    public static func lookup() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Writes the encoded parent session, including its access token, and no other secret.
public struct KeychainSessionStore: ParentSessionStoring {
    public init() {}

    public func save(_ session: ParentSession) throws {
        let data = try SessionCodec.encode(session)
        let base = KeychainSessionQuery.lookup()
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainSessionError(status: status) }
    }

    public func load() throws -> ParentSession? {
        var query = KeychainSessionQuery.lookup()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainSessionError(status: status)
        }
        return try SessionCodec.decode(data)
    }

    public func clear() throws {
        let status = SecItemDelete(KeychainSessionQuery.lookup() as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw KeychainSessionError(status: status)
    }
}
