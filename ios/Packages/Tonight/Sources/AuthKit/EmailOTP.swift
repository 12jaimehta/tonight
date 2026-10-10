import Foundation
import os
import Security

/// Supabase email OTP. The anon key and host come from the app config, never a second host.
public struct SupabaseAuthConfig: Sendable, Equatable {
    public var baseURL: URL
    public var anonKey: String

    public init(baseURL: URL, anonKey: String) {
        self.baseURL = baseURL
        self.anonKey = anonKey
    }

    public static func load(from bundle: Bundle) -> SupabaseAuthConfig? {
        guard
            let urlString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            !urlString.contains("$("),
            let baseURL = URL(string: urlString),
            baseURL.scheme?.lowercased() == "https",
            let host = baseURL.host,
            !host.isEmpty,
            let anonKey = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !anonKey.isEmpty,
            !anonKey.contains("$(")
        else { return nil }
        return SupabaseAuthConfig(baseURL: baseURL, anonKey: anonKey)
    }
}

public enum EmailOTPError: Error, Equatable {
    case invalidEmail
    case invalidCode
    case hostNotAllowed
    case rejected(Int)
    case malformed
}

public protocol OTPTransporting: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionOTPTransport: OTPTransporting {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EmailOTPError.rejected(0) }
        return (data, http)
    }
}

public protocol AccessTokenStoring: Sendable {
    func save(token: String, expiresAt: Date) throws
    func load() throws -> String?
    func clear() throws
}

public final class InMemoryAccessTokenStore: AccessTokenStoring, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<(String, Date)?>(initialState: nil)
    public init() {}
    public func save(token: String, expiresAt: Date) throws { state.withLock { $0 = (token, expiresAt) } }
    public func load() throws -> String? { state.withLock { $0?.0 } }
    public func clear() throws { state.withLock { $0 = nil } }
}

/// The access token lives beside the session, not inside the session JSON.
public struct KeychainAccessTokenStore: AccessTokenStoring {
    public static let account = "access-token"

    public init() {}

    public func save(token: String, expiresAt: Date) throws {
        let payload = try JSONEncoder().encode(StoredToken(token: token, expiresAt: expiresAt))
        var query = base()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = payload
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainSessionError(status: status) }
    }

    public func load() throws -> String? {
        var query = base()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainSessionError(status: status) }
        return try JSONDecoder().decode(StoredToken.self, from: data).token
    }

    public func clear() throws {
        let status = SecItemDelete(base() as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw KeychainSessionError(status: status)
    }

    private func base() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainSessionQuery.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    private struct StoredToken: Codable {
        var token: String
        var expiresAt: Date
    }
}

public struct EmailOTPClient: Sendable {
    public var config: SupabaseAuthConfig
    public var transport: any OTPTransporting
    public var sessions: any ParentSessionStoring
    public var tokens: any AccessTokenStoring
    public var now: @Sendable () -> Date

    public init(
        config: SupabaseAuthConfig,
        transport: any OTPTransporting,
        sessions: any ParentSessionStoring,
        tokens: any AccessTokenStoring,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.config = config
        self.transport = transport
        self.sessions = sessions
        self.tokens = tokens
        self.now = now
    }

    public func requestCode(email: String) async throws {
        let address = try Self.normalizedEmail(email)
        let url = try Self.endpoint(config.baseURL, path: "otp")
        let body = try JSONSerialization.data(withJSONObject: ["email": address, "create_user": true])
        let response = try await transport.send(request(url: url, body: body))
        guard (200..<300).contains(response.1.statusCode) else { throw EmailOTPError.rejected(response.1.statusCode) }
    }

    @discardableResult
    public func verify(email: String, code: String, at date: Date? = nil) async throws -> ParentSession {
        let address = try Self.normalizedEmail(email)
        let digits = code.filter(\.isNumber)
        guard digits.count == 6 else { throw EmailOTPError.invalidCode }
        let url = try Self.endpoint(config.baseURL, path: "verify")
        let body = try JSONSerialization.data(withJSONObject: [
            "type": "email",
            "email": address,
            "token": digits,
        ])
        let (data, http) = try await transport.send(request(url: url, body: body))
        guard (200..<300).contains(http.statusCode) else { throw EmailOTPError.rejected(http.statusCode) }
        let issued = date ?? now()
        let parsed = try Self.parseVerify(data, issuedAt: issued)
        let session = ParentSession.issue(parentID: parsed.parentID, at: issued, lifetime: parsed.lifetime)
        try sessions.save(session)
        try tokens.save(token: parsed.accessToken, expiresAt: session.expiresAt)
        return session
    }

    public static func endpoint(_ base: URL, path: String) throws -> URL {
        guard base.scheme?.lowercased() == "https", let host = base.host?.lowercased(), !host.isEmpty else {
            throw EmailOTPError.hostNotAllowed
        }
        guard host != "api.sarvam.ai", !host.contains("sarvam") else { throw EmailOTPError.hostNotAllowed }
        let url = base.appending(path: "auth").appending(path: "v1").appending(path: path)
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == host else {
            throw EmailOTPError.hostNotAllowed
        }
        return url
    }

    private func request(url: URL, body: Data) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "api" + "key")
        request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func normalizedEmail(_ email: String) throws -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains(".") else { throw EmailOTPError.invalidEmail }
        return trimmed
    }

    private static func parseVerify(_ data: Data, issuedAt: Date) throws -> (parentID: String, accessToken: String, lifetime: TimeInterval) {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let token = object?["access_token"] as? String
        let user = object?["user"] as? [String: Any]
        let parentID = user?["id"] as? String
        guard let token, !token.isEmpty, let parentID, !parentID.isEmpty else { throw EmailOTPError.malformed }
        let lifetime = Self.lifetime(from: object?["expires_in"])
        guard lifetime > 0 else { throw EmailOTPError.malformed }
        _ = issuedAt
        return (parentID, token, lifetime)
    }

    private static func lifetime(from value: Any?) -> TimeInterval {
        if let seconds = value as? Int { return TimeInterval(seconds) }
        if let seconds = value as? Double { return seconds }
        return 3600
    }
}

/// Personal Team builds leave this off. There is no Sign in with Apple button unless the flag is set.
public enum SignInWithApple {
    public static var isEnabled: Bool {
        #if SIGN_IN_WITH_APPLE
        true
        #else
        false
        #endif
    }
}
