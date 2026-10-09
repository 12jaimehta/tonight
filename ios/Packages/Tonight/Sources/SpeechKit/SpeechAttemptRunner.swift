import Foundation
import os

public struct ProxyRequest: Sendable, Equatable {
    public var url: URL
    public var body: Data
    public var headers: [String: String]
    public var timeout: TimeInterval

    public init(url: URL, body: Data, headers: [String: String], timeout: TimeInterval) {
        self.url = url
        self.body = body
        self.headers = headers
        self.timeout = timeout
    }
}

public struct ProxyResponse: Sendable, Equatable {
    public var transcript: String
    public var words: [RecognizedWord]
    public var latency: TimeInterval
    public var cost: Decimal?

    public init(transcript: String, words: [RecognizedWord], latency: TimeInterval, cost: Decimal?) {
        self.transcript = transcript
        self.words = words
        self.latency = latency
        self.cost = cost
    }
}

public protocol ProxyTransporting: Sendable {
    func post(_ request: ProxyRequest) async throws -> ProxyResponse
    func cancelAll() async
}

public protocol SpeechSleeper: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

public struct TaskSpeechSleeper: SpeechSleeper {
    public init() {}
    public func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

public struct SpeechCallLog: Sendable, Equatable {
    public var engineID: SpeechEngineID
    public var latency: TimeInterval
    public var cost: Decimal?
    public var byteCount: Int

    public init(engineID: SpeechEngineID, latency: TimeInterval, cost: Decimal?, byteCount: Int) {
        self.engineID = engineID
        self.latency = latency
        self.cost = cost
        self.byteCount = byteCount
    }
}

public struct SpeechAuditEntry: Codable, Sendable, Equatable {
    public var ts: Date
    public var attemptID: UUID
    public var childProfileID: UUID
    public var engine: String
    public var reason: String
    public var consentRecordID: UUID?
    public var consentVersion: String?
    public var flag: Bool
    public var online: Bool
    public var bytesSent: Int
    public var cancelledAfterBytes: Int?

    public init(
        ts: Date,
        attemptID: UUID,
        childProfileID: UUID,
        engine: String,
        reason: String,
        consentRecordID: UUID?,
        consentVersion: String?,
        flag: Bool,
        online: Bool,
        bytesSent: Int,
        cancelledAfterBytes: Int? = nil
    ) {
        self.ts = ts
        self.attemptID = attemptID
        self.childProfileID = childProfileID
        self.engine = engine
        self.reason = reason
        self.consentRecordID = consentRecordID
        self.consentVersion = consentVersion
        self.flag = flag
        self.online = online
        self.bytesSent = bytesSent
        self.cancelledAfterBytes = cancelledAfterBytes
    }
}

public final class SpeechAuditLog: @unchecked Sendable {
    private let entries = OSAllocatedUnfairLock(initialState: [SpeechAuditEntry]())
    public init() {}
    public func append(_ entry: SpeechAuditEntry) {
        entries.withLock { $0.append(entry) }
    }
    public func snapshot() -> [SpeechAuditEntry] {
        entries.withLock { $0 }
    }
}

public enum ArtefactKind: String, Codable, Sendable {
    case audio
    case transcript
    case alignment
}

public struct AudioArtefact: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var childProfileID: UUID
    public var kind: ArtefactKind
    public var serverPath: Bool
    public var deletedAt: Date?

    public init(id: UUID = UUID(), childProfileID: UUID, kind: ArtefactKind, serverPath: Bool, deletedAt: Date? = nil) {
        self.id = id
        self.childProfileID = childProfileID
        self.kind = kind
        self.serverPath = serverPath
        self.deletedAt = deletedAt
    }
}

public final class AudioArtefactRegistry: @unchecked Sendable {
    private let items = OSAllocatedUnfairLock(initialState: [AudioArtefact]())
    public init() {}

    public func register(_ item: AudioArtefact) {
        items.withLock { $0.append(item) }
    }

    public func delete(childProfileID: UUID, serverPathOnly: Bool, at date: Date) {
        items.withLock { items in
            for index in items.indices where items[index].childProfileID == childProfileID {
                if serverPathOnly && !items[index].serverPath { continue }
                items[index].deletedAt = date
            }
        }
    }

    public func live(childProfileID: UUID) -> [AudioArtefact] {
        items.withLock { items in
            items.filter { $0.childProfileID == childProfileID && $0.deletedAt == nil }
        }
    }
}

public struct SpeechAttemptOutcome: Sendable, Equatable {
    public var engine: SpeechEngineID?
    public var transcript: String?
    public var words: [RecognizedWord]
    public var fallbackReason: String?
    public var parentMarking: Bool
    public var bytesSent: Int
    public var usedSameBuffer: Bool

    public init(
        engine: SpeechEngineID?,
        transcript: String?,
        words: [RecognizedWord] = [],
        fallbackReason: String? = nil,
        parentMarking: Bool = false,
        bytesSent: Int,
        usedSameBuffer: Bool = false
    ) {
        self.engine = engine
        self.transcript = transcript
        self.words = words
        self.fallbackReason = fallbackReason
        self.parentMarking = parentMarking
        self.bytesSent = bytesSent
        self.usedSameBuffer = usedSameBuffer
    }
}

public struct SarvamProxyConfiguration: Sendable, Equatable {
    public var baseURL: URL
    public init(baseURL: URL = TonightEndpoints.proxyBaseURL) {
        self.baseURL = baseURL
    }

    /// Placeholder Edge Function name. The Sarvam key stays in the function, not in the app.
    public static let functionName = "sarvam-proxy"

    public func speechURL() throws -> URL {
        let url = baseURL
            .appending(path: "functions")
            .appending(path: "v1")
            .appending(path: Self.functionName)
        try TonightEndpoints.validate(url)
        return url
    }
}

enum SarvamRequestBody {
    static func encode(audio: SpeechAudio, locale: String, consent: AudioConsentRecord) -> Data {
        let payload: [String: String] = [
            "locale": locale,
            "audioBase64": audio.samples.base64EncodedString(),
            "contentType": "audio/wav",
            "consentRecordId": consent.id.uuidString,
            "consentVersion": consent.version,
        ]
        return try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}

public struct SpeechAttemptRunner: Sendable {
    public var transport: any ProxyTransporting
    public var onDevice: any SpeechRecognizing
    public var sleeper: any SpeechSleeper
    public var audit: SpeechAuditLog
    public var callLogs: CallLogStore
    public var now: @Sendable () -> Date

    public init(
        transport: any ProxyTransporting,
        onDevice: any SpeechRecognizing,
        sleeper: any SpeechSleeper = TaskSpeechSleeper(),
        audit: SpeechAuditLog = SpeechAuditLog(),
        callLogs: CallLogStore = CallLogStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.onDevice = onDevice
        self.sleeper = sleeper
        self.audit = audit
        self.callLogs = callLogs
        self.now = now
    }

    public func run(
        audio: SpeechAudio,
        input: SelectionInput,
        attemptID: UUID,
        locale: String = OnDeviceRequestPolicy.localeIdentifier
    ) async -> SpeechAttemptOutcome {
        let selection = SpeechEngineSelector.select(input)
        switch selection.engine {
        case .none:
            audit(selection, input: input, attemptID: attemptID, bytes: 0, cancelled: nil)
            return SpeechAttemptOutcome(engine: nil, transcript: nil, bytesSent: 0)
        case .parentMarking:
            audit(selection, input: input, attemptID: attemptID, bytes: 0, cancelled: nil)
            return SpeechAttemptOutcome(engine: .parentMarking, transcript: nil, parentMarking: true, bytesSent: 0)
        case .appleOnDevice:
            let outcome = await transcribeOnDevice(audio: audio, locale: locale, fallback: nil)
            audit(selection, input: input, attemptID: attemptID, bytes: 0, cancelled: nil, engineOverride: outcome.engine)
            return outcome
        case .sarvam:
            return await transcribeServer(audio: audio, input: input, attemptID: attemptID, locale: locale, selection: selection)
        }
    }

    /// CG-33 / LAT-10. Cancels the foreground task. Nothing is queued to finish later.
    public func suspend() async {
        await transport.cancelAll()
    }

    private func transcribeServer(
        audio: SpeechAudio,
        input: SelectionInput,
        attemptID: UUID,
        locale: String,
        selection: EngineSelection
    ) async -> SpeechAttemptOutcome {
        guard let record = input.record else {
            return SpeechAttemptOutcome(engine: nil, transcript: nil, bytesSent: 0)
        }
        let configuration = SarvamProxyConfiguration()
        let url: URL
        do {
            url = try configuration.speechURL()
        } catch {
            return await fallbackOnDevice(audio: audio, input: input, attemptID: attemptID, locale: locale, reason: .serverError, bytesSent: 0)
        }
        let body = SarvamRequestBody.encode(audio: audio, locale: locale, consent: record)
        let request = ProxyRequest(
            url: url,
            body: body,
            headers: ["Content-Type": "application/json"],
            timeout: OnDeviceRequestPolicy.serverTimeout
        )
        let post = Task { try await transport.post(request) }
        let timeout = Task {
            try await sleeper.sleep(seconds: OnDeviceRequestPolicy.serverTimeout)
            post.cancel()
            await transport.cancelAll()
        }
        let result = await post.result
        timeout.cancel()
        switch result {
        case .success(let response):
            callLogs.append(SpeechCallLog(engineID: .sarvam, latency: response.latency, cost: response.cost, byteCount: body.count))
            audit(selection, input: input, attemptID: attemptID, bytes: body.count, cancelled: nil)
            return SpeechAttemptOutcome(
                engine: .sarvam,
                transcript: response.transcript,
                words: response.words,
                bytesSent: body.count
            )
        case .failure:
            return await fallbackOnDevice(
                audio: audio,
                input: input,
                attemptID: attemptID,
                locale: locale,
                reason: .timeout,
                bytesSent: 0,
                cancelledAfterBytes: body.count
            )
        }
    }

    private func fallbackOnDevice(
        audio: SpeechAudio,
        input: SelectionInput,
        attemptID: UUID,
        locale: String,
        reason: SelectionReason,
        bytesSent: Int,
        cancelledAfterBytes: Int? = nil
    ) async -> SpeechAttemptOutcome {
        var outcome = await transcribeOnDevice(audio: audio, locale: locale, fallback: reason.rawValue)
        outcome.usedSameBuffer = true
        outcome.bytesSent = bytesSent
        let selection = EngineSelection(engine: outcome.parentMarking ? .parentMarking : .appleOnDevice, reason: reason, maySendAudio: false)
        audit(selection, input: input, attemptID: attemptID, bytes: bytesSent, cancelled: cancelledAfterBytes, engineOverride: outcome.engine)
        return outcome
    }

    private func transcribeOnDevice(audio: SpeechAudio, locale: String, fallback: String?) async -> SpeechAttemptOutcome {
        let outcome = await onDevice.transcribe(audio: audio, locale: locale)
        switch outcome {
        case .transcript(let result):
            return SpeechAttemptOutcome(
                engine: .appleOnDevice,
                transcript: result.transcript,
                words: result.words,
                fallbackReason: fallback,
                bytesSent: 0,
                usedSameBuffer: fallback != nil
            )
        case .unavailable:
            return SpeechAttemptOutcome(
                engine: .parentMarking,
                transcript: nil,
                fallbackReason: fallback ?? SelectionReason.onDeviceUnavailable.rawValue,
                parentMarking: true,
                bytesSent: 0,
                usedSameBuffer: fallback != nil
            )
        }
    }

    private func audit(
        _ selection: EngineSelection,
        input: SelectionInput,
        attemptID: UUID,
        bytes: Int,
        cancelled: Int?,
        engineOverride: SpeechEngineID? = nil
    ) {
        let engineName: String = {
            if let engineOverride { return engineOverride.rawValue }
            switch selection.engine {
            case .none: return "none"
            case .appleOnDevice: return SpeechEngineID.appleOnDevice.rawValue
            case .sarvam: return SpeechEngineID.sarvam.rawValue
            case .parentMarking: return SpeechEngineID.parentMarking.rawValue
            }
        }()
        audit.append(SpeechAuditEntry(
            ts: now(),
            attemptID: attemptID,
            childProfileID: input.childProfileID,
            engine: engineName,
            reason: selection.reason.rawValue,
            consentRecordID: input.record?.id,
            consentVersion: input.record?.version,
            flag: input.flagOn,
            online: input.online,
            bytesSent: bytes,
            cancelledAfterBytes: cancelled
        ))
    }
}

public final class CallLogStore: @unchecked Sendable {
    private let logs = OSAllocatedUnfairLock(initialState: [SpeechCallLog]())
    public init() {}
    public func append(_ log: SpeechCallLog) {
        logs.withLock { $0.append(log) }
    }
    public func snapshot() -> [SpeechCallLog] {
        logs.withLock { $0 }
    }
}

/// Foreground session only. Background configurations resume uploads after the app is killed (CG-30).
public enum ProxySessionFactory {
    public static func foreground(timeout: TimeInterval = OnDeviceRequestPolicy.serverTimeout) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        configuration.sessionSendsLaunchEvents = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    public static func isBackground(_ configuration: URLSessionConfiguration) -> Bool {
        configuration.identifier != nil
    }
}

public final class ForegroundProxyTransport: ProxyTransporting, @unchecked Sendable {
    private let session: URLSession
    private let lock = OSAllocatedUnfairLock()
    private var task: URLSessionTask?

    public init(session: URLSession = ProxySessionFactory.foreground()) {
        self.session = session
    }

    public func post(_ request: ProxyRequest) async throws -> ProxyResponse {
        try TonightEndpoints.validate(request.url)
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.body
        request.headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        let (data, _) = try await session.data(for: urlRequest)
        return try Self.decode(data)
    }

    public func cancelAll() async {
        // URLSessionTask is not Sendable, so the scoped critical section uses the unchecked variant.
        lock.withLockUnchecked { self.task?.cancel() }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.getAllTasks { tasks in
                tasks.forEach { $0.cancel() }
                continuation.resume()
            }
        }
    }

    static func decode(_ data: Data) throws -> ProxyResponse {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let transcript = object?["transcript"] as? String ?? ""
        let latency = (object?["latencyMs"] as? Double).map { $0 / 1000 } ?? 0
        let cost = (object?["cost"] as? String).flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        return ProxyResponse(transcript: transcript, words: [], latency: latency, cost: cost)
    }
}
