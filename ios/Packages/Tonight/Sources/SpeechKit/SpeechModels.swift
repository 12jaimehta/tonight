import Foundation

/// The only network host the app may contact. The real hostname is not chosen yet.
/// `.invalid` is a reserved TLD and does not resolve. Replace this one value when Engineering names the proxy.
public enum TonightEndpoints {
    public static let proxyBaseURL = URL(string: "https://proxy.tonight.invalid")!
    public static let allowedHosts: Set<String> = ["proxy.tonight.invalid"]

    public static let deniedHostFragments = [
        "fire" + "base", "googleapis.com", "google-analytics", "crashlytics",
        "sentry.io", "bugsnag", "mixpanel", "amplitude", "segment.io",
        "appsflyer", "adjust.com", "branch.io", "doubleclick", "openai.com",
        "sarvam.ai", "supa" + "base.co",
    ]

    public static func validate(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https" else { throw NetworkPolicyError.notHTTPS }
        guard let host = url.host?.lowercased(), allowedHosts.contains(host) else {
            throw NetworkPolicyError.hostNotAllowed(url.host ?? url.absoluteString)
        }
        let lowered = url.absoluteString.lowercased()
        for fragment in deniedHostFragments where lowered.contains(fragment) {
            throw NetworkPolicyError.hostNotAllowed(fragment)
        }
    }
}

public enum NetworkPolicyError: Error, Equatable {
    case notHTTPS
    case hostNotAllowed(String)
}

public enum SpeechEngineID: String, Codable, Sendable, Equatable {
    case appleOnDevice = "apple_on_device"
    case sarvam = "sarvam"
    case parentMarking = "parent_marking"
    case fake = "fake"
}

public enum AudioConsentScope: String, Codable, Sendable, Equatable, Hashable {
    case onDevice = "speech.on_device"
    case server = "speech.server"
}

public struct AudioConsentRecord: Codable, Sendable, Equatable, Identifiable {
    public static let currentVersion = "2026-10-09"

    public var id: UUID
    public var parentID: String
    public var childProfileID: UUID
    public var version: String
    public var scopes: Set<AudioConsentScope>
    public var tappedAt: Date
    public var receivedAt: Date?
    public var withdrawnAt: Date?
    public var withdrawnScopes: Set<AudioConsentScope>
    public var method: String
    public var backendConfirmed: Bool

    public init(
        id: UUID = UUID(),
        parentID: String,
        childProfileID: UUID,
        version: String = AudioConsentRecord.currentVersion,
        scopes: Set<AudioConsentScope>,
        tappedAt: Date,
        receivedAt: Date? = nil,
        withdrawnAt: Date? = nil,
        withdrawnScopes: Set<AudioConsentScope> = [],
        method: String,
        backendConfirmed: Bool
    ) {
        self.id = id
        self.parentID = parentID
        self.childProfileID = childProfileID
        self.version = version
        self.scopes = scopes
        self.tappedAt = tappedAt
        self.receivedAt = receivedAt
        self.withdrawnAt = withdrawnAt
        self.withdrawnScopes = withdrawnScopes
        self.method = method
        self.backendConfirmed = backendConfirmed
    }

    public func scopeIsActive(_ scope: AudioConsentScope) -> Bool {
        withdrawnAt == nil && scopes.contains(scope) && !withdrawnScopes.contains(scope)
    }
}

/// In-memory consent stub. The consent screen waits on design (T-008).
public final class AudioConsentStore: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [UUID: AudioConsentRecord] = [:]

    public init() {}

    public func record(for childProfileID: UUID) -> AudioConsentRecord? {
        lock.lock()
        defer { lock.unlock() }
        return records[childProfileID]
    }

    public func grant(_ record: AudioConsentRecord) {
        lock.lock()
        records[record.childProfileID] = record
        lock.unlock()
    }

    /// Cancelling the consent screen stores nothing (CG-11).
    public func cancelDraft() {}

    public func withdraw(childProfileID: UUID, scopes: Set<AudioConsentScope>, at date: Date) {
        lock.lock()
        defer { lock.unlock() }
        guard var record = records[childProfileID] else { return }
        if scopes.contains(.onDevice) {
            record.withdrawnAt = date
            record.withdrawnScopes.formUnion([.onDevice, .server])
            record.scopes.subtract([.onDevice, .server])
        } else {
            record.withdrawnScopes.formUnion(scopes)
            record.scopes.subtract(scopes)
        }
        records[childProfileID] = record
    }
}

public struct SpeechFeatureFlags: Sendable, Equatable {
    /// `speech.server.sarvam`. Default off. Study builds only.
    public var sarvamEnabled: Bool
    public init(sarvamEnabled: Bool = false) {
        self.sarvamEnabled = sarvamEnabled
    }
}

public enum ServerSpeechBuild {
    public static var isStudyBuild: Bool {
        #if STUDY
        true
        #else
        false
        #endif
    }
}

public struct SelectionInput: Sendable, Equatable {
    public var studyBuild: Bool
    public var flagOn: Bool
    public var online: Bool
    public var sessionValid: Bool
    public var onDeviceAvailable: Bool
    public var childProfileID: UUID
    public var record: AudioConsentRecord?

    public init(
        studyBuild: Bool,
        flagOn: Bool,
        online: Bool,
        sessionValid: Bool,
        onDeviceAvailable: Bool = true,
        childProfileID: UUID,
        record: AudioConsentRecord?
    ) {
        self.studyBuild = studyBuild
        self.flagOn = flagOn
        self.online = online
        self.sessionValid = sessionValid
        self.onDeviceAvailable = onDeviceAvailable
        self.childProfileID = childProfileID
        self.record = record
    }
}

public enum SelectionReason: String, Codable, Sendable, Equatable {
    case consentRequired
    case onDeviceWithdrawn
    case flagOff
    case onDeviceOnly
    case serverWithdrawn
    case staleConsentVersion
    case wrongChild
    case sessionExpired
    case offline
    case backendUnconfirmed
    case releaseBuild
    case serverEligible
    case onDeviceUnavailable
    case timeout
    case serverError
    case suspended
}

public enum SelectedEngine: Sendable, Equatable {
    case none
    case appleOnDevice
    case sarvam
    case parentMarking
}

public struct EngineSelection: Sendable, Equatable {
    public var engine: SelectedEngine
    public var reason: SelectionReason
    public var maySendAudio: Bool

    public init(engine: SelectedEngine, reason: SelectionReason, maySendAudio: Bool) {
        self.engine = engine
        self.reason = reason
        self.maySendAudio = maySendAudio
    }
}

public enum SpeechEngineSelector {
    /// Server speech only when the study build, the flag, this child's current server consent,
    /// a live session, and a confirmed online check all agree. Otherwise no audio leaves the device.
    public static func select(_ input: SelectionInput) -> EngineSelection {
        guard let record = input.record else {
            return EngineSelection(engine: .none, reason: .consentRequired, maySendAudio: false)
        }
        guard record.childProfileID == input.childProfileID else {
            return EngineSelection(engine: .none, reason: .wrongChild, maySendAudio: false)
        }
        guard record.scopeIsActive(.onDevice) else {
            return EngineSelection(engine: .none, reason: .onDeviceWithdrawn, maySendAudio: false)
        }
        if serverEligible(input, record: record) {
            return EngineSelection(engine: .sarvam, reason: .serverEligible, maySendAudio: true)
        }
        if !input.onDeviceAvailable {
            return EngineSelection(engine: .parentMarking, reason: .onDeviceUnavailable, maySendAudio: false)
        }
        return EngineSelection(engine: .appleOnDevice, reason: onDeviceReason(input, record: record), maySendAudio: false)
    }

    private static func serverEligible(_ input: SelectionInput, record: AudioConsentRecord) -> Bool {
        input.studyBuild
            && input.flagOn
            && input.sessionValid
            && input.online
            && record.backendConfirmed
            && record.version == AudioConsentRecord.currentVersion
            && record.scopeIsActive(.server)
    }

    private static func onDeviceReason(_ input: SelectionInput, record: AudioConsentRecord) -> SelectionReason {
        if !input.studyBuild { return .releaseBuild }
        if !input.flagOn { return .flagOff }
        if !input.sessionValid { return .sessionExpired }
        if !input.online { return .offline }
        if !record.backendConfirmed { return .backendUnconfirmed }
        if record.version != AudioConsentRecord.currentVersion { return .staleConsentVersion }
        if record.withdrawnScopes.contains(.server) { return .serverWithdrawn }
        return .onDeviceOnly
    }
}

public struct RecognizedWord: Codable, Sendable, Equatable {
    public var text: String
    public var start: TimeInterval
    public var duration: TimeInterval

    public init(text: String, start: TimeInterval, duration: TimeInterval) {
        self.text = text
        self.start = start
        self.duration = duration
    }
}

public struct SpeechAudio: Sendable, Equatable {
    public enum Storage: String, Sendable { case memory }
    public var storage: Storage
    public var samples: Data

    public init(samples: Data) {
        self.storage = .memory
        self.samples = samples
    }

    public mutating func discard() { samples.removeAll() }
}

public struct SpeechRecognitionResult: Sendable, Equatable {
    public var transcript: String
    public var words: [RecognizedWord]
    public var engineID: SpeechEngineID

    public init(transcript: String, words: [RecognizedWord], engineID: SpeechEngineID) {
        self.transcript = transcript
        self.words = words
        self.engineID = engineID
    }
}

public enum SpeechAvailability: Sendable, Equatable {
    case available
    case unavailable(String)
}

public enum SpeechEngineOutcome: Sendable, Equatable {
    case transcript(SpeechRecognitionResult)
    case unavailable(String)
}

public protocol SpeechRecognizing: AnyObject, Sendable {
    var engineID: SpeechEngineID { get }
    func availability(locale: String) async -> SpeechAvailability
    func transcribe(audio: SpeechAudio, locale: String) async -> SpeechEngineOutcome
}

public enum SpeechPermission: String, Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

public struct SpeechAccess: Sendable, Equatable {
    public var microphone: SpeechPermission
    public var speech: SpeechPermission
    public var canRecord: Bool { microphone == .authorized && speech == .authorized }

    public init(microphone: SpeechPermission, speech: SpeechPermission) {
        self.microphone = microphone
        self.speech = speech
    }
}

public protocol SpeechPermissionChecking: Sendable {
    func currentAccess() -> SpeechAccess
    func requestAccess() async -> SpeechAccess
}

public enum OnDeviceRequestPolicy {
    public static let requiresOnDeviceRecognition = true
    public static let localeIdentifier = "en-IN"
    public static let serverTimeout: TimeInterval = 8
}
