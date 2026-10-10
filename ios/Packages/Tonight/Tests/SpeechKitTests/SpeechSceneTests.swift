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
        var session = SpeechSessionModel(childID: child, consentActive: true, flagOn: true)
        await scene.apply(session.watch)
        session = session.withdrawing()
        await scene.apply(session.watch)
        XCTAssertFalse(session.consentActive)
        XCTAssertTrue(scene.deletionRequested)
        let cancelled = await transport.wasCancelled()
        XCTAssertTrue(cancelled)
    }

    func test_CG21_flagOffCancelsTheUpload() async {
        let transport = SpyTransport()
        let scene = SpeechSceneController(runner: runner(transport))
        var session = SpeechSessionModel(childID: child, consentActive: true, flagOn: true)
        await scene.apply(session.watch)
        session = session.turningFlagOff()
        await scene.apply(session.watch)
        XCTAssertFalse(session.flagOn)
        XCTAssertTrue(scene.deletionRequested)
        let cancelled = await transport.wasCancelled()
        XCTAssertTrue(cancelled)
    }

    func test_CG25_childChangeCancelsTheUpload() async {
        let transport = SpyTransport()
        let scene = SpeechSceneController(runner: runner(transport))
        var session = SpeechSessionModel(childID: child, consentActive: true, flagOn: true)
        await scene.apply(session.watch)
        session = session.switchingChild(to: UUID())
        await scene.apply(session.watch)
        XCTAssertNotEqual(session.childID, child)
        XCTAssertTrue(scene.deletionRequested)
        let cancelled = await transport.wasCancelled()
        XCTAssertTrue(cancelled)
    }

    func test_CG33_LAT10_appAppliesTheSessionWatch() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TonightApp/RootView.swift")
        let source = try String(contentsOf: root, encoding: .utf8)
        XCTAssertTrue(source.contains("speechScene.apply"))
        XCTAssertTrue(source.contains("withdrawing()"))
        XCTAssertTrue(source.contains("turningFlagOff()"))
        XCTAssertTrue(source.contains("switchingChild"))
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
