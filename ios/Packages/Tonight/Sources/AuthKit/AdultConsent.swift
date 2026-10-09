import Foundation

/// The parent confirmed they are the adult. This is not the per-child audio consent in SpeechKit.
/// The consent screen itself is a stub until design (T-008).
public struct AdultConsentRecord: Codable, Equatable, Sendable, Identifiable {
    public static let currentVersion = "2026-10-09"

    public var id: UUID
    public var parentID: String
    public var version: String
    public var acceptedAt: Date
    public var method: String

    public init(
        id: UUID = UUID(),
        parentID: String,
        version: String = AdultConsentRecord.currentVersion,
        acceptedAt: Date,
        method: String
    ) {
        self.id = id
        self.parentID = parentID
        self.version = version
        self.acceptedAt = acceptedAt
        self.method = method
    }
}

public final class InMemoryAdultConsentStore: @unchecked Sendable {
    private let lock = NSLock()
    private var record: AdultConsentRecord?

    public init() {}

    public func save(_ record: AdultConsentRecord) {
        lock.lock()
        self.record = record
        lock.unlock()
    }

    public func current() -> AdultConsentRecord? {
        lock.lock()
        defer { lock.unlock() }
        return record
    }

    public func clear() {
        lock.lock()
        record = nil
        lock.unlock()
    }
}
