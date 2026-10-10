import XCTest
@testable import SpeechKit

final class SpeechSceneTests: XCTestCase {
    private let child = UUID()

    func test_CG33_inactiveSceneSuspendsTheRunner() async {
        let transport = SpyTransport()
        let scene = SpeechSceneController(runner: runner(transport))
        await scene.sceneDidChange(isActive: false)
        XCTAssertTrue(scene.suspended)
        let cancelled = await transport.wasCancelled()
        XCTAssertTrue(cancelled)
    }

    func test_LAT10_backgroundDoesNotQueueARetry() async {
        let transport = SpyTransport()
        let scene = SpeechSceneController(runner: runner(transport))
        await scene.sceneDidChange(isActive: false)
        let outcome = await scene.runner.run(
            audio: SpeechAudio(samples: Data([1])),
            input: input(flagOn: false, record: record(scopes: [.onDevice])),
            attemptID: UUID()
        )
        let posts = await transport.posts
        XCTAssertEqual(posts.count, 0)
        XCTAssertEqual(outcome.bytesSent, 0)
    }

    func test_CG20_consentWithdrawalCancelsAndRequestsDeletion() async {
        let transport = SpyTransport()
        let scene = SpeechSceneController(runner: runner(transport))
        await scene.apply(SpeechWatch(childID: child, consentActive: true, flagOn: true))
        await scene.apply(SpeechWatch(childID: child, consentActive: false, flagOn: true))
        XCTAssertTrue(scene.deletionRequested)
        let cancelled = await transport.wasCancelled()
        XCTAssertTrue(cancelled)
    }

    func test_CG21_flagOffCancelsTheUpload() async {
        let transport = SpyTransport()
        let scene = SpeechSceneController(runner: runner(transport))
        await scene.apply(SpeechWatch(childID: child, consentActive: true, flagOn: true))
        await scene.apply(SpeechWatch(childID: child, consentActive: true, flagOn: false))
        XCTAssertTrue(scene.deletionRequested)
        let cancelled = await transport.wasCancelled()
        XCTAssertTrue(cancelled)
    }

    func test_CG25_childChangeCancelsTheUpload() async {
        let transport = SpyTransport()
        let scene = SpeechSceneController(runner: runner(transport))
        await scene.apply(SpeechWatch(childID: child, consentActive: true, flagOn: true))
        await scene.apply(SpeechWatch(childID: UUID(), consentActive: true, flagOn: true))
        XCTAssertTrue(scene.deletionRequested)
        let cancelled = await transport.wasCancelled()
        XCTAssertTrue(cancelled)
    }

    private func runner(_ transport: SpyTransport) -> SpeechAttemptRunner {
        SpeechAttemptRunner(
            transport: transport,
            onDevice: FakeSpeechEngine(
                engineID: .appleOnDevice,
                scripted: .transcript(SpeechRecognitionResult(transcript: "local", words: [], engineID: .appleOnDevice))
            ),
            sleeper: NeverSleeper()
        )
    }

    private func input(flagOn: Bool, record: AudioConsentRecord?) -> SelectionInput {
        SelectionInput(
            studyBuild: true,
            flagOn: flagOn,
            online: true,
            sessionValid: true,
            childProfileID: child,
            record: record
        )
    }

    private func record(scopes: Set<AudioConsentScope>) -> AudioConsentRecord {
        AudioConsentRecord(
            parentID: "parent",
            childProfileID: child,
            scopes: scopes,
            tappedAt: Date(timeIntervalSince1970: 1_700_000_000),
            method: "stub",
            backendConfirmed: true
        )
    }
}
