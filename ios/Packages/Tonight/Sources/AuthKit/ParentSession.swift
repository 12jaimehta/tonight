import Foundation
import os

/// A parent session. The Keychain stores this record and nothing a child could guess.
public struct ParentSession: Codable, Equatable, Sendable, Identifiable {
    public static let defaultLifetime: TimeInterval = 12 * 60 * 60

    public var id: UUID
    public var parentID: String
    public var issuedAt: Date
    public var expiresAt: Date
    /// Parent Supabase access token. The server-speech request sends it as a bearer token.
    public var accessToken: String

    public init(id: UUID = UUID(), parentID: String, issuedAt: Date, expiresAt: Date, accessToken: String = "") {
        self.id = id
        self.parentID = parentID
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.accessToken = accessToken
    }

    public static func issue(
        parentID: String,
        at date: Date,
        lifetime: TimeInterval = ParentSession.defaultLifetime,
        id: UUID = UUID(),
        accessToken: String = ""
    ) -> ParentSession {
        ParentSession(
            id: id,
            parentID: parentID,
            issuedAt: date,
            expiresAt: date.addingTimeInterval(lifetime),
            accessToken: accessToken
        )
    }

    public func isValid(at date: Date) -> Bool {
        date >= issuedAt && date < expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, parentID, issuedAt, expiresAt, accessToken
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(parentID, forKey: .parentID)
        try container.encode(issuedAt, forKey: .issuedAt)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(accessToken, forKey: .accessToken)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        parentID = try container.decode(String.self, forKey: .parentID)
        issuedAt = try container.decode(Date.self, forKey: .issuedAt)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
    }
}

public protocol ParentSessionStoring: Sendable {
    func save(_ session: ParentSession) throws
    func load() throws -> ParentSession?
    func clear() throws
}

/// Used by tests and by previews. The app uses `KeychainSessionStore`.
public final class InMemorySessionStore: ParentSessionStoring, @unchecked Sendable {
    private let session = OSAllocatedUnfairLock<ParentSession?>(initialState: nil)

    public init() {}

    public func save(_ session: ParentSession) throws {
        self.session.withLock { $0 = session }
    }

    public func load() throws -> ParentSession? {
        session.withLock { $0 }
    }

    public func clear() throws {
        session.withLock { $0 = nil }
    }
}

public enum SessionCodec {
    public static func encode(_ session: ParentSession) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(session)
    }

    public static func decode(_ data: Data) throws -> ParentSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ParentSession.self, from: data)
    }
}
