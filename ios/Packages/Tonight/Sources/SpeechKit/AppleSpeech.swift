import AVFoundation
import Foundation
import Speech
import os

public final class FakeSpeechEngine: SpeechRecognizing, @unchecked Sendable {
    public let engineID: SpeechEngineID
    private let state: OSAllocatedUnfairLock<State>

    private struct State: Sendable {
        var scripted: SpeechEngineOutcome
        var calls: Int
    }

    public var scripted: SpeechEngineOutcome {
        get { state.withLock { $0.scripted } }
        set { state.withLock { $0.scripted = newValue } }
    }

    public private(set) var calls: Int {
        get { state.withLock { $0.calls } }
        set { state.withLock { $0.calls = newValue } }
    }

    public init(engineID: SpeechEngineID = .fake, scripted: SpeechEngineOutcome) {
        self.engineID = engineID
        self.state = OSAllocatedUnfairLock(initialState: State(scripted: scripted, calls: 0))
    }

    public func availability(locale: String) async -> SpeechAvailability {
        if case .unavailable(let reason) = scripted { return .unavailable(reason) }
        return .available
    }

    public func transcribe(audio: SpeechAudio, locale: String) async -> SpeechEngineOutcome {
        state.withLock { state in
            state.calls += 1
            return state.scripted
        }
    }
}

public final class AppleOnDeviceRecognizer: SpeechRecognizing, @unchecked Sendable {
    public let engineID: SpeechEngineID = .appleOnDevice
    private let permissions: any SpeechPermissionChecking

    public init(permissions: any SpeechPermissionChecking = SystemSpeechPermissions()) {
        self.permissions = permissions
    }

    public func availability(locale: String) async -> SpeechAvailability {
        let identifier = locale.replacingOccurrences(of: "_", with: "-")
        if #available(iOS 26.0, *) {
            let analyzer = await SpeechAnalyzerAvailability.check(localeIdentifier: identifier)
            if case .available = analyzer { return .available }
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)) else {
            return .unavailable("en-IN recognizer is missing")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            return .unavailable("On-device en-IN recognition is not supported")
        }
        return .available
    }

    public func transcribe(audio: SpeechAudio, locale: String) async -> SpeechEngineOutcome {
        let access = await permissions.requestAccess()
        guard access.canRecord else { return .unavailable("Microphone or speech permission was denied") }
        let availability = await availability(locale: locale)
        guard case .available = availability else { return .unavailable("On-device recognition is unavailable") }
        if #available(iOS 26.0, *) {
            if let result = await SpeechAnalyzerAvailability.transcribeIfPossible(audio: audio, localeIdentifier: locale) {
                return result
            }
        }
        return await SFSpeechOnDeviceSession().transcribe(audio: audio, localeIdentifier: locale)
    }
}

@available(iOS 26.0, *)
enum SpeechAnalyzerAvailability {
    static func check(localeIdentifier: String) async -> SpeechAvailability {
        guard SpeechTranscriber.isAvailable else {
            return .unavailable("SpeechAnalyzer is not available on this device")
        }
        let supported = await SpeechTranscriber.supportedLocales
        let wanted = localeIdentifier.replacingOccurrences(of: "_", with: "-").lowercased()
        let match = supported.contains { locale in
            let identifier = locale.identifier(.bcp47).lowercased()
            return identifier == wanted || identifier.hasPrefix(wanted)
        }
        guard match else { return .unavailable("SpeechAnalyzer has no \(localeIdentifier) locale") }
        let installed = await SpeechTranscriber.installedLocales
        let ready = installed.contains { $0.identifier(.bcp47).lowercased() == wanted }
        guard ready else { return .unavailable("en-IN SpeechAnalyzer asset is not installed") }
        return .available
    }

    static func transcribeIfPossible(audio: SpeechAudio, localeIdentifier: String) async -> SpeechEngineOutcome? {
        guard case .available = await check(localeIdentifier: localeIdentifier) else { return nil }
        let locale = Locale(identifier: localeIdentifier)
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        do {
            try await analyzer.start(inputSequence: stream)
            if let buffer = Self.buffer(from: audio.samples) {
                continuation.yield(AnalyzerInput(buffer: buffer))
            }
            continuation.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            var text = ""
            for try await result in transcriber.results where !result.isVolatile {
                text += String(result.text.characters)
            }
            return .transcript(SpeechRecognitionResult(transcript: text, words: [], engineID: .appleOnDevice))
        } catch {
            return .unavailable("SpeechAnalyzer failed on device")
        }
    }

    private static func buffer(from samples: Data) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty else { return nil }
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)
        guard let format else { return nil }
        let frames = AVAudioFrameCount(samples.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        samples.withUnsafeBytes { raw in
            guard let address = raw.baseAddress, let channel = buffer.int16ChannelData else { return }
            channel[0].update(from: address.assumingMemoryBound(to: Int16.self), count: Int(frames))
        }
        return buffer
    }
}

final class ResumeOnce: @unchecked Sendable {
    private let done = OSAllocatedUnfairLock(initialState: false)

    func resume(_ body: () -> Void) {
        let shouldRun = done.withLock { (done: inout Bool) -> Bool in
            if done { return false }
            done = true
            return true
        }
        if shouldRun { body() }
    }
}

struct SFSpeechOnDeviceSession {
    func transcribe(audio: SpeechAudio, localeIdentifier: String) async -> SpeechEngineOutcome {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            return .unavailable("On-device recognition is unavailable")
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = OnDeviceRequestPolicy.requiresOnDeviceRecognition
        request.shouldReportPartialResults = false
        if let buffer = pcmBuffer(audio.samples) {
            request.append(buffer)
        }
        request.endAudio()
        let gate = ResumeOnce()
        return await withCheckedContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                guard result?.isFinal == true || error != nil else { return }
                gate.resume {
                    if let result {
                        let words = result.bestTranscription.segments.map {
                            RecognizedWord(text: $0.substring, start: $0.timestamp, duration: $0.duration)
                        }
                        continuation.resume(returning: .transcript(SpeechRecognitionResult(
                            transcript: result.bestTranscription.formattedString,
                            words: words,
                            engineID: .appleOnDevice
                        )))
                    } else {
                        continuation.resume(returning: .unavailable("On-device recognition failed"))
                    }
                }
            }
        }
    }

    private func pcmBuffer(_ samples: Data) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty else { return nil }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true) else {
            return nil
        }
        let frames = AVAudioFrameCount(samples.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frames, 1)) else { return nil }
        buffer.frameLength = frames
        samples.withUnsafeBytes { raw in
            guard let address = raw.baseAddress, let channel = buffer.int16ChannelData else { return }
            channel[0].update(from: address.assumingMemoryBound(to: Int16.self), count: Int(frames))
        }
        return buffer
    }
}

public struct SystemSpeechPermissions: SpeechPermissionChecking {
    public init() {}

    public func currentAccess() -> SpeechAccess {
        SpeechAccess(microphone: microphoneStatus(), speech: speechStatus())
    }

    public func requestAccess() async -> SpeechAccess {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: Self.map(status))
            }
        }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed ? SpeechPermission.authorized : SpeechPermission.denied)
            }
        }
        return SpeechAccess(microphone: microphone, speech: speech)
    }

    private func speechStatus() -> SpeechPermission {
        Self.map(SFSpeechRecognizer.authorizationStatus())
    }

    private func microphoneStatus() -> SpeechPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: return .notDetermined
        case .granted: return .authorized
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> SpeechPermission {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }
}

public protocol SpeechSynthesizing: AnyObject, Sendable {
    func speak(_ text: String, rate: Float) async
    func stop()
}

public final class IndianEnglishSpeech: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    public static let passageRate: Float = 0.9
    public static let wordRate: Float = 0.85

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    public func speak(_ text: String, rate: Float = passageRate) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice.speechVoices().first {
            $0.language.replacingOccurrences(of: "_", with: "-").lowercased().hasPrefix("en-in")
        } ?? AVSpeechSynthesisVoice(language: "en-IN")
        utterance.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
