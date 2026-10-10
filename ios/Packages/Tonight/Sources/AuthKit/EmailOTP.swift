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
    func save(token: String, expiresAt: Date, refreshToken: String?) throws
    func load() throws -> String?
    func loadExpiry() throws -> Date?
    func loadRefreshToken() throws -> String?
    func clear() throws
}

public final class InMemoryAccessTokenStore: AccessTokenStoring, @unchecked Sendable {
    private struct Record {
        var token: String
        var expiresAt: Date
        var refreshToken: String?
    }

    private let state = OSAllocatedUnfairLock<Record?>(initialState: nil)
    public init() {}
    public func save(token: String, expiresAt: Date) throws {
        try save(token: token, expiresAt: expiresAt, refreshToken: loadRefreshToken())
    }
    public func save(token: String, expiresAt: Date, refreshToken: String?) throws {
        state.withLock { $0 = Record(token: token, expiresAt: expiresAt, refreshToken: refreshToken) }
    }
    public func load() throws -> String? { state.withLock { $0?.token } }
    public func loadExpiry() throws -> Date? { state.withLock { $0?.expiresAt } }
    public func loadRefreshToken() throws -> String? { state.withLock { $0?.refreshToken } }
    public func clear() throws { state.withLock { $0 = nil } }
}

/// The access token lives beside the session, not inside the session JSON.
public struct KeychainAccessTokenStore: AccessTokenStoring {
    public static let account = "access-token"

    public init() {}

    public func save(token: String, expiresAt: Date) throws {
        try save(token: token, expiresAt: expiresAt, refreshToken: loadRefreshToken())
    }

    public func save(token: String, expiresAt: Date, refreshToken: String?) throws {
        let payload = try JSONEncoder().encode(StoredToken(token: token, expiresAt: expiresAt, refreshToken: refreshToken))
        var query = base()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = payload
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainSessionError(status: status) }
    }

    public func load() throws -> String? {
        try loadData().map { try stored($0).token }
    }

    public func loadExpiry() throws -> Date? {
        try loadData().map { try stored($0).expiresAt }
    }

    public func loadRefreshToken() throws -> String? {
        try loadData().flatMap { try stored($0).refreshToken }
    }

    private func loadData() throws -> Data? {
        var query = base()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainSessionError(status: status) }
        return data
    }

    private func stored(_ data: Data) throws -> StoredToken {
        try JSONDecoder().decode(StoredToken.self, from: data)
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
        var refreshToken: String?
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
        try tokens.save(token: parsed.accessToken, expiresAt: session.expiresAt, refreshToken: parsed.refreshToken)
        return session
    }

    /// Exchanges a saved refresh token after the access token expires, then the caller retries the queue.
    @discardableResult
    public func refreshSession() async throws -> String {
        if let current = try tokens.load(),
           let expiry = try tokens.loadExpiry(),
           expiry > now().addingTimeInterval(60) {
            return current
        }
        guard let refresh = try tokens.loadRefreshToken(), !refresh.isEmpty else { throw EmailOTPError.malformed }
        let url = try Self.refreshURL(config.baseURL)
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": refresh])
        let (data, http) = try await transport.send(request(url: url, body: body))
        guard (200..<300).contains(http.statusCode) else { throw EmailOTPError.rejected(http.statusCode) }
        let parsed = try Self.parseVerify(data, issuedAt: now())
        let expires = now().addingTimeInterval(parsed.lifetime)
        try tokens.save(token: parsed.accessToken, expiresAt: expires, refreshToken: parsed.refreshToken ?? refresh)
        return parsed.accessToken
    }

    public static func refreshURL(_ base: URL) throws -> URL {
        let url = try endpoint(base, path: "token")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw EmailOTPError.hostNotAllowed }
        components.query = "grant_type=refresh_token"
        guard let refresh = components.url else { throw EmailOTPError.hostNotAllowed }
        return refresh
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

    private static func parseVerify(_ data: Data, issuedAt: Date) throws -> (parentID: String, accessToken: String, lifetime: TimeInterval, refreshToken: String?) {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let token = object?["access_token"] as? String
        let user = object?["user"] as? [String: Any]
        let parentID = user?["id"] as? String
        guard let token, !token.isEmpty, let parentID, !parentID.isEmpty else { throw EmailOTPError.malformed }
        let lifetime = Self.lifetime(from: object?["expires_in"])
        guard lifetime > 0 else { throw EmailOTPError.malformed }
        _ = issuedAt
        let refresh = object?["refresh_token"] as? String
        return (parentID, token, lifetime, refresh)
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
