import XCTest
@testable import SpeechKit

final class SpeechHTTPTests: XCTestCase {
    private let child = UUID()

    override func setUp() {
        super.setUp()
        installPlaceholderSpeechConfig()
    }

    func test_LAT05_httpErrorDoesNotMarkTheChildWrong() async {
        let transport = ScriptedTransport(.fail(.serverError(status: 401, bytesSent: 12)))
        let onDevice = localEngine("the cat sat")
        let outcome = await runner(transport, onDevice).run(
            audio: SpeechAudio(samples: Data([1, 2, 3])),
            input: eligible(),
            attemptID: UUID()
        )
        XCTAssertEqual(outcome.engine, .appleOnDevice)
        XCTAssertEqual(outcome.transcript, "the cat sat")
        XCTAssertNotEqual(outcome.transcript, "")
        #if STUDY
        XCTAssertEqual(outcome.fallbackReason, SelectionReason.serverError.rawValue)
        XCTAssertEqual(outcome.bytesSent, 12)
        #else
        XCTAssertNil(outcome.fallbackReason)
        XCTAssertEqual(outcome.bytesSent, 0)
        #endif
    }

    func test_LAT07_serverFailureIsNotAWrongMark() async {
        let transport = ScriptedTransport(.fail(.serverError(status: 503, bytesSent: 4)))
        let outcome = await runner(transport, localEngine("kept")).run(
            audio: SpeechAudio(samples: Data([9])),
            input: eligible(),
            attemptID: UUID()
        )
        XCTAssertEqual(outcome.transcript, "kept")
        XCTAssertFalse(outcome.parentMarking)
        #if STUDY
        XCTAssertEqual(outcome.fallbackReason, "serverError")
        #else
        XCTAssertNil(outcome.fallbackReason)
        #endif
    }

    func test_CG21_bytesSentComeFromTheTransport() async {
        let transport = ScriptedTransport(.fail(.cancelled(bytesSent: 48)))
        let runner = runner(transport, localEngine("local"))
        let outcome = await runner.run(audio: SpeechAudio(samples: Data([1])), input: eligible(), attemptID: UUID())
        #if STUDY
        XCTAssertEqual(outcome.bytesSent, 48)
        XCTAssertEqual(outcome.fallbackReason, "cancelled")
        XCTAssertEqual(runner.audit.snapshot().last?.cancelledAfterBytes, 48)
        #else
        XCTAssertEqual(outcome.bytesSent, 0)
        XCTAssertNil(outcome.fallbackReason)
        #endif
    }

    func test_CG22_emptyTranscriptFallsBack() async {
        let transport = ScriptedTransport(.succeed(ProxyResponse(transcript: "", words: [], latency: 0, cost: nil)))
        let outcome = await runner(transport, localEngine("on device")).run(
            audio: SpeechAudio(samples: Data([1, 1])),
            input: eligible(),
            attemptID: UUID()
        )
        XCTAssertEqual(outcome.transcript, "on device")
        XCTAssertNotEqual(outcome.engine, .sarvam)
        #if STUDY
        XCTAssertEqual(outcome.fallbackReason, "serverError")
        #else
        XCTAssertNil(outcome.fallbackReason)
        #endif
    }

    private func runner(_ transport: ScriptedTransport, _ onDevice: FakeSpeechEngine) -> SpeechAttemptRunner {
        SpeechAttemptRunner(transport: transport, onDevice: onDevice, sleeper: NeverSleeper())
    }

    private func localEngine(_ transcript: String) -> FakeSpeechEngine {
        FakeSpeechEngine(
            engineID: .appleOnDevice,
            scripted: .transcript(SpeechRecognitionResult(transcript: transcript, words: [], engineID: .appleOnDevice))
        )
    }

    private func eligible() -> SelectionInput {
        SelectionInput(
            studyBuild: true,
            flagOn: true,
            online: true,
            sessionValid: true,
            childProfileID: child,
            record: AudioConsentRecord(
                parentID: "parent",
                childProfileID: child,
                scopes: [.onDevice, .server],
                tappedAt: Date(timeIntervalSince1970: 1_700_000_000),
                method: "stub",
                backendConfirmed: true
            )
        )
    }
}

actor ScriptedTransport: ProxyTransporting {
    enum Mode {
        case fail(ProxyTransportError)
        case succeed(ProxyResponse)
    }

    private let mode: Mode
    init(_ mode: Mode) { self.mode = mode }

    func post(_ request: ProxyRequest) async throws -> ProxyResponse {
        switch mode {
        case .fail(let error): throw error
        case .succeed(let response): return response
        }
    }

    func cancelAll() async {}
}
