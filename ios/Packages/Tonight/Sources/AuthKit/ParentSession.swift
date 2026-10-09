import Foundation

/// A parent session. The Keychain stores this record and nothing a child could guess.
public struct ParentSession: Codable, Equatable, Sendable, Identifiable {
    public static let defaultLifetime: TimeInterval = 12 * 60 * 60

    public var id: UUID
    public var parentID: String
    public var issuedAt: Date
    public var expiresAt: Date

    public init(id: UUID = UUID(), parentID: String, issuedAt: Date, expiresAt: Date) {
        self.id = id
        self.parentID = parentID
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    public static func issue(
        parentID: String,
        at date: Date,
        lifetime: TimeInterval = ParentSession.defaultLifetime,
        id: UUID = UUID()
    ) -> ParentSession {
        ParentSession(id: id, parentID: parentID, issuedAt: date, expiresAt: date.addingTimeInterval(lifetime))
    }

    public func isValid(at date: Date) -> Bool {
        date >= issuedAt && date < expiresAt
    }
}

public protocol ParentSessionStoring: Sendable {
    func save(_ session: ParentSession) throws
    func load() throws -> ParentSession?
    func clear() throws
}

/// Used by tests and by previews. The app uses `KeychainSessionStore`.
public final class InMemorySessionStore: ParentSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var session: ParentSession?

    public init() {}

    public func save(_ session: ParentSession) throws {
        lock.lock()
        self.session = session
        lock.unlock()
    }

    public func load() throws -> ParentSession? {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    public func clear() throws {
        lock.lock()
        session = nil
        lock.unlock()
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
