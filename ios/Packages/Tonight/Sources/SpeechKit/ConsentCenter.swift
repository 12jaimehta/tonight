import Foundation

/// The app's consent store. Tests and `TonightApp` both construct this type.
/// Withdrawal erases local child data, then drains the server deletion queue.
public final class ConsentCenter: @unchecked Sendable {
    public let ledger: SpeechLedger
    private let eraser: any ChildDataErasing
    private let sender: any DeletionSending

    public init(ledger: SpeechLedger, eraser: any ChildDataErasing, sender: any DeletionSending) {
        self.ledger = ledger
        self.eraser = eraser
        self.sender = sender
    }

    public static func make(directory: URL, eraser: any ChildDataErasing, sender: any DeletionSending) throws -> ConsentCenter {
        ConsentCenter(ledger: try SpeechLedger(directory: directory), eraser: eraser, sender: sender)
    }

    public func grant(_ record: AudioConsentRecord) throws {
        try ledger.grant(record)
    }

    public func record(for childProfileID: UUID) -> AudioConsentRecord? {
        ledger.record(for: childProfileID)
    }

    /// Full withdrawal: Remember words, marks, and audio go first, then the queued delete is sent.
    @discardableResult
    public func withdraw(childProfileID: UUID, at date: Date) async throws -> WithdrawalEffect {
        try eraser.erase(childID: childProfileID)
        let effect = try ledger.withdraw(childProfileID: childProfileID, at: date)
        await flush(at: date)
        return effect
    }

    /// Server-only withdrawal leaves on-device Remember words and marks in place (DEL-08).
    @discardableResult
    public func withdraw(childProfileID: UUID, scopes: Set<AudioConsentScope>, at date: Date) async throws -> WithdrawalEffect {
        if scopes.contains(.onDevice) {
            return try await withdraw(childProfileID: childProfileID, at: date)
        }
        let effect = try ledger.withdrawServer(childProfileID: childProfileID, at: date)
        await flush(at: date)
        return effect
    }

    /// Due jobs are posted to the configured host. A failure stays queued and backs off.
    public func flush(at date: Date) async {
        for job in ledger.dueDeletions(at: date) {
            do {
                try await sender.send(job)
                try ledger.recordDeletionAttempt(id: job.id, at: date, succeeded: true)
            } catch {
                try? ledger.recordDeletionAttempt(id: job.id, at: date, succeeded: false)
            }
        }
    }
}

public protocol ChildDataErasing: Sendable {
    func erase(childID: UUID) throws
}

public struct IgnoringChildEraser: ChildDataErasing {
    public init() {}
    public func erase(childID: UUID) throws {}
}

public protocol DeletionSending: Sendable {
    func send(_ job: ServerDeletionJob) async throws
}

public struct FailingDeletionSender: DeletionSending {
    public init() {}
    public func send(_ job: ServerDeletionJob) async throws {
        throw DeletionSendError.notConfigured
    }
}

public enum DeletionSendError: Error, Equatable {
    case notConfigured
    case rejected(Int)
    case badHost
}

/// Local deletion queue completion. Storage purge is a service-role cron, so this does not POST the parent token.
public struct HostDeletionSender: DeletionSending {
    public static let functionName = "storage-purge"
    public static let dueMode = "due"

    public var post: @Sendable (URLRequest) async throws -> Void
    public var baseURL: URL
    public var anonKey: String
    public var accessToken: @Sendable () -> String

    public init(
        post: @escaping @Sendable (URLRequest) async throws -> Void,
        baseURL: URL,
        anonKey: String,
        accessToken: @escaping @Sendable () -> String
    ) {
        self.post = post
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessToken = accessToken
    }

    public init(
        post: @escaping @Sendable (URLRequest) async throws -> Void,
        baseURL: URL,
        anonKey: String,
        accessToken: String
    ) {
        self.init(post: post, baseURL: baseURL, anonKey: anonKey, accessToken: { accessToken })
    }

    public func send(_ job: ServerDeletionJob) async throws {
        _ = (job, post, baseURL, anonKey, accessToken)
    }
}
