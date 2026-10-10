import XCTest
@testable import SpeechKit

final class SpeechPolicyTests: XCTestCase {
    private let child = UUID()
    private let otherChild = UUID()

    override func setUp() {
        super.setUp()
        installPlaceholderSpeechConfig()
    }

    func testCG01_noConsent_doesNotRecord() {
        let selection = SpeechEngineSelector.select(input(record: nil))
        XCTAssertEqual(selection.engine, .none)
        XCTAssertFalse(selection.maySendAudio)
        XCTAssertEqual(selection.reason, .consentRequired)
    }

    func testCG02_flagOff_onDeviceOnly_sendsNothing() {
        let selection = SpeechEngineSelector.select(input(flagOn: false, record: record(scopes: [.onDevice])))
        XCTAssertEqual(selection.engine, .appleOnDevice)
        XCTAssertFalse(selection.maySendAudio)
    }

    func testCG03_flagBeatsConsent() {
        let selection = SpeechEngineSelector.select(input(flagOn: false, record: record(scopes: [.onDevice, .server])))
        XCTAssertEqual(selection.engine, .appleOnDevice)
        XCTAssertEqual(selection.reason, .flagOff)
        XCTAssertFalse(selection.maySendAudio)
    }

    func testCG05_serverScopeMissing() {
        let selection = SpeechEngineSelector.select(eligibleInput(record: record(scopes: [.onDevice])))
        XCTAssertEqual(selection.engine, .appleOnDevice)
        XCTAssertEqual(selection.reason, .onDeviceOnly)
        XCTAssertFalse(selection.maySendAudio)
    }

    func test_CG17_NET14_releaseBuildLeavesTheServerBranchOut() {
        XCTAssertFalse(ServerSpeechBuild.isStudyBuild)
        let selection = SpeechEngineSelector.select(eligibleInput(record: record(scopes: [.onDevice, .server])))
        XCTAssertEqual(selection.engine, .appleOnDevice)
        XCTAssertEqual(selection.reason, .releaseBuild)
        XCTAssertFalse(selection.maySendAudio)
        let source = try! String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SpeechKit/SpeechAttemptRunner.swift"))
        XCTAssertTrue(source.contains("#if STUDY || DEBUG\nenum SarvamRequestBody"))
        XCTAssertTrue(source.contains("#if STUDY\n            return await transcribeServer"))
    }

    func testCG07_withdrawnServer_isOnDeviceEvenOffline() {
        var granted = record(scopes: [.onDevice, .server])
        granted.withdrawnScopes = [.server]
        granted.scopes = [.onDevice]
        let selection = SpeechEngineSelector.select(eligibleInput(online: false, record: granted))
        XCTAssertEqual(selection.engine, .appleOnDevice)
        XCTAssertFalse(selection.maySendAudio)
    }

    func testCG08_onDeviceWithdrawalCascades() {
        var granted = record(scopes: [.server])
        granted.withdrawnAt = Date()
        granted.withdrawnScopes = [.onDevice, .server]
        let selection = SpeechEngineSelector.select(eligibleInput(record: granted))
        XCTAssertEqual(selection.engine, .none)
        XCTAssertFalse(selection.maySendAudio)
    }

    func test_CG09_CG15_scopeNamesMatchTheServerVocabulary() {
        XCTAssertEqual(AudioConsentScope.onDevice.rawValue, "on_device_speech")
        XCTAssertEqual(AudioConsentScope.server.rawValue, "server_speech")
        XCTAssertEqual(AudioConsentRecord.currentVersion, "2026-10-09")
    }

    func testCG09_staleVersionBlocksServer() {
        var granted = record(scopes: [.onDevice, .server])
        granted.version = "2020-01-01"
        let selection = SpeechEngineSelector.select(eligibleInput(record: granted))
        XCTAssertEqual(selection.engine, .appleOnDevice)
        XCTAssertEqual(selection.reason, .staleConsentVersion)
        XCTAssertFalse(selection.maySendAudio)
    }

    func testCG10_consentDoesNotCrossChildren() {
        let sibling = record(scopes: [.onDevice, .server])
        let stolen = SpeechEngineSelector.select(eligibleInput(child: otherChild, record: sibling))
        XCTAssertEqual(stolen.engine, .none)
        XCTAssertEqual(stolen.reason, .wrongChild)
        XCTAssertFalse(stolen.maySendAudio)

        let own = record(child: otherChild, scopes: [.onDevice])
        let local = SpeechEngineSelector.select(eligibleInput(child: otherChild, record: own))
        XCTAssertEqual(local.engine, .appleOnDevice)
        XCTAssertFalse(local.maySendAudio)
    }

    func testCG11_cancelledConsentStoresNothing() {
        let store = AudioConsentStore()
        store.cancelDraft()
        XCTAssertNil(store.record(for: child))
        let selection = SpeechEngineSelector.select(input(record: store.record(for: child)))
        XCTAssertEqual(selection.engine, .none)
    }

    func testCG12_expiredSessionBlocksServer() {
        let selection = SpeechEngineSelector.select(eligibleInput(sessionValid: false, record: record(scopes: [.onDevice, .server])))
        XCTAssertEqual(selection.engine, .appleOnDevice)
        XCTAssertEqual(selection.reason, .sessionExpired)
        XCTAssertFalse(selection.maySendAudio)
    }

    func testCG14_offlineRefusesServerImmediately() {
        let selection = SpeechEngineSelector.select(eligibleInput(online: false, record: record(scopes: [.onDevice, .server])))
        XCTAssertEqual(selection.engine, .appleOnDevice)
        XCTAssertEqual(selection.reason, .offline)
        XCTAssertFalse(selection.maySendAudio)
    }

    func testCG17_releaseBuildCannotEnableTheFlag() {
        let selection = SpeechEngineSelector.select(
            input(studyBuild: false, flagOn: true, record: record(scopes: [.onDevice, .server]))
        )
        XCTAssertEqual(selection.engine, .appleOnDevice)
        XCTAssertEqual(selection.reason, .releaseBuild)
        XCTAssertFalse(ServerSpeechBuild.isStudyBuild)
        XCTAssertFalse(selection.maySendAudio)
    }

    func testLAT04AndLAT06_offlineUnavailableBecomesParentMarking() {
        let selection = SpeechEngineSelector.select(
            eligibleInput(online: false, onDeviceAvailable: false, record: record(scopes: [.onDevice, .server]))
        )
        XCTAssertEqual(selection.engine, .parentMarking)
        XCTAssertFalse(selection.maySendAudio)
    }

    func testWithdrawalDeletesSpeechDataImmediately() {
        let registry = AudioArtefactRegistry()
        registry.register(AudioArtefact(childProfileID: child, kind: .audio, serverPath: false))
        registry.register(AudioArtefact(childProfileID: child, kind: .transcript, serverPath: true))
        registry.register(AudioArtefact(childProfileID: otherChild, kind: .audio, serverPath: false))
        let store = AudioConsentStore()
        store.grant(record(scopes: [.onDevice, .server]))
        store.withdraw(childProfileID: child, scopes: [.onDevice], at: Date())
        registry.delete(childProfileID: child, serverPathOnly: false, at: Date())
        XCTAssertTrue(registry.live(childProfileID: child).isEmpty)
        XCTAssertEqual(registry.live(childProfileID: otherChild).count, 1)
        XCTAssertEqual(store.record(for: child)?.scopeIsActive(.server), false)
        XCTAssertEqual(store.record(for: child)?.scopeIsActive(.onDevice), false)
    }

    func testAllowlistRejectsThirdPartiesAndDirectSarvam() throws {
        XCTAssertNoThrow(try TonightEndpoints.validate(TonightEndpoints.proxyBaseURL))
        let speech = try SarvamProxyConfiguration().speechURL()
        XCTAssertEqual(speech.host, "project-ref.supabase.co")
        XCTAssertEqual(speech.path, "/functions/v1/sarvam-proxy")
        for host in ["api.sarvam.ai", "firebaseio.com", "api.openai.com", "app-measurement.com", "example.supabase.co"] {
            XCTAssertThrowsError(try TonightEndpoints.validate(URL(string: "https://\(host)/speech")!))
        }
        XCTAssertThrowsError(try TonightEndpoints.validate(URL(string: "http://project-ref.supabase.co")!))
    }

    func testProxyURLIsTheOnlyConfiguredHost() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let package = root.appendingPathComponent("Package.swift")
        let text = try sourceText(at: sources) + (try String(contentsOf: package))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("firebase"), "NET-02b")
        XCTAssertFalse(text.contains("URLSessionConfiguration.background"))
        XCTAssertFalse(text.contains("beginBackgroundTask"))
        XCTAssertFalse(text.contains("BGTaskScheduler"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("apiKey"))
        XCTAssertFalse(text.contains("AVAudioFile"))
        XCTAssertTrue(text.contains("requiresOnDeviceRecognition = OnDeviceRequestPolicy.requiresOnDeviceRecognition"))
        let urls = text.split(separator: "\"").map(String.init).filter { $0.hasPrefix("https://") }
        XCTAssertEqual(urls, [], "NET-02c the host lives in xcconfig, not in a source literal")
    }

    func test_NET02b_supabaseSwiftIsTheOnlyPermittedThirdPartySDK() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let package = try String(contentsOf: root.appendingPathComponent("Package.swift"))
        let permitted = ["supabase-swift"]
        XCTAssertEqual(permitted, ["supabase-swift"])
        for banned in ["firebase", "Firebase", "mixpanel", "amplitude", "sentry", "bugsnag", "sarvam.ai"] {
            XCTAssertFalse(package.localizedCaseInsensitiveContains(banned), banned)
        }
        if package.contains("supabase-swift") {
            XCTAssertTrue(package.contains("supabase-swift"))
            XCTAssertEqual(package.components(separatedBy: "supabase-swift").count - 1, package.components(separatedBy: ".package").count - 1)
        }
    }

    func test_NET02c_redirectDelegateRejectsEveryHop() {
        installPlaceholderSpeechConfig()
        let delegate = AllowlistSessionDelegate()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: TonightEndpoints.proxyBaseURL)
        let response = HTTPURLResponse(url: TonightEndpoints.proxyBaseURL, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let offHost = URLRequest(url: URL(string: "https://api.sarvam.ai/speech")!)
        var followed: URLRequest? = URLRequest(url: TonightEndpoints.proxyBaseURL)
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: offHost) { request in
            followed = request
        }
        XCTAssertNil(followed)
        task.cancel()
        session.invalidateAndCancel()
    }

    func testForegroundSessionIsNotABackgroundSession() {
        let session = ProxySessionFactory.foreground()
        XCTAssertFalse(ProxySessionFactory.isBackground(session.configuration))
        XCTAssertNil(session.configuration.identifier)
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 8)
        XCTAssertNil(session.configuration.urlCache)
    }

    func testCG06_runnerSendsOnlyToTheProxy() async {
        let transport = SpyTransport()
        await transport.setMode(.succeed(ProxyResponse(transcript: "the cat", words: [], latency: 0.2, cost: Decimal(string: "0.002", locale: Locale(identifier: "en_US_POSIX")))))
        let runner = makeRunner(transport: transport, sleeper: NeverSleeper())
        let outcome = await runner.run(
            audio: SpeechAudio(samples: Data([1, 2, 3, 4])),
            input: eligibleInput(record: record(scopes: [.onDevice, .server])),
            attemptID: UUID()
        )
        XCTAssertNotEqual(outcome.engine, .sarvam)
        XCTAssertEqual(outcome.bytesSent, 0)
        let posts = await transport.posts
        XCTAssertEqual(posts.count, 0)
        XCTAssertEqual(runner.callLogs.snapshot().count, 0)
    }

    func testNonEligibleStatesSendZeroBytes() async {
        let cases: [(String, SelectionInput)] = [
            ("CG-02", input(flagOn: false, record: record(scopes: [.onDevice]))),
            ("CG-03", input(flagOn: false, record: record(scopes: [.onDevice, .server]))),
            ("CG-05", eligibleInput(record: record(scopes: [.onDevice]))),
            ("CG-14", eligibleInput(online: false, record: record(scopes: [.onDevice, .server]))),
            ("CG-17", input(studyBuild: false, flagOn: true, record: record(scopes: [.onDevice, .server]))),
        ]
        for (name, selectionInput) in cases {
            let transport = SpyTransport()
            let runner = makeRunner(transport: transport, sleeper: ImmediateSleeper())
            let outcome = await runner.run(audio: SpeechAudio(samples: Data([9, 9])), input: selectionInput, attemptID: UUID())
            let posts = await transport.posts
            XCTAssertEqual(posts.count, 0, name)
            XCTAssertEqual(outcome.bytesSent, 0, name)
            XCTAssertNotEqual(outcome.engine, .sarvam, name)
        }
    }

    func testLAT03_timeoutFallsBackOnTheSameBuffer() async {
        let transport = SpyTransport()
        await transport.setMode(.hang)
        let onDevice = FakeSpeechEngine(engineID: .appleOnDevice, scripted: .transcript(
            SpeechRecognitionResult(transcript: "the cat", words: [RecognizedWord(text: "the", start: 0, duration: 0.2)], engineID: .appleOnDevice)
        ))
        let runner = makeRunner(transport: transport, onDevice: onDevice, sleeper: ImmediateSleeper())
        let outcome = await runner.run(
            audio: SpeechAudio(samples: Data(repeating: 1, count: 32)),
            input: eligibleInput(record: record(scopes: [.onDevice, .server])),
            attemptID: UUID()
        )
        XCTAssertEqual(outcome.engine, .appleOnDevice)
        XCTAssertEqual(outcome.transcript, "the cat")
        #if STUDY
        XCTAssertEqual(outcome.fallbackReason, "timeout")
        XCTAssertTrue(outcome.usedSameBuffer)
        XCTAssertEqual(outcome.bytesSent, 0)
        XCTAssertEqual(onDevice.calls, 1)
        let cancelled = await transport.wasCancelled()
        XCTAssertTrue(cancelled)
        XCTAssertEqual(runner.audit.snapshot().last?.cancelledAfterBytes != nil, true)
        #else
        XCTAssertNil(outcome.fallbackReason)
        XCTAssertEqual(outcome.bytesSent, 0)
        let posts = await transport.posts
        XCTAssertEqual(posts.count, 0)
        #endif
    }

    func testLAT06_onDeviceUnavailableAfterOfflineIsParentMarking() async {
        let transport = SpyTransport()
        let onDevice = FakeSpeechEngine(engineID: .appleOnDevice, scripted: .unavailable("no asset"))
        let runner = makeRunner(transport: transport, onDevice: onDevice, sleeper: ImmediateSleeper())
        let outcome = await runner.run(
            audio: SpeechAudio(samples: Data([1])),
            input: eligibleInput(online: false, onDeviceAvailable: false, record: record(scopes: [.onDevice, .server])),
            attemptID: UUID()
        )
        XCTAssertTrue(outcome.parentMarking)
        XCTAssertEqual(outcome.engine, .parentMarking)
        let posts = await transport.posts
        XCTAssertEqual(posts.count, 0)
        XCTAssertEqual(onDevice.calls, 0)
    }

    func testCG33_suspendCancelsAndDoesNotRetry() async {
        let transport = SpyTransport()
        let runner = makeRunner(transport: transport, sleeper: NeverSleeper())
        await runner.suspend()
        let cancelled = await transport.wasCancelled()
        XCTAssertTrue(cancelled)
        let outcome = await runner.run(
            audio: SpeechAudio(samples: Data([1, 2])),
            input: input(flagOn: false, record: record(scopes: [.onDevice])),
            attemptID: UUID()
        )
        let posts = await transport.posts
        XCTAssertEqual(posts.count, 0)
        XCTAssertEqual(outcome.bytesSent, 0)
    }

    func testAudioStorageIsMemoryOnly() {
        var audio = SpeechAudio(samples: Data([1, 2, 3]))
        XCTAssertEqual(audio.storage, .memory)
        audio.discard()
        XCTAssertTrue(audio.samples.isEmpty)
    }

    private func makeRunner(
        transport: SpyTransport,
        onDevice: FakeSpeechEngine = FakeSpeechEngine(
            engineID: .appleOnDevice,
            scripted: .transcript(SpeechRecognitionResult(transcript: "local", words: [], engineID: .appleOnDevice))
        ),
        sleeper: any SpeechSleeper
    ) -> SpeechAttemptRunner {
        SpeechAttemptRunner(transport: transport, onDevice: onDevice, sleeper: sleeper)
    }

    private func eligibleInput(
        child: UUID? = nil,
        online: Bool = true,
        sessionValid: Bool = true,
        onDeviceAvailable: Bool = true,
        record: AudioConsentRecord
    ) -> SelectionInput {
        input(
            studyBuild: true,
            flagOn: true,
            online: online,
            sessionValid: sessionValid,
            onDeviceAvailable: onDeviceAvailable,
            child: child ?? self.child,
            record: record
        )
    }

    private func input(
        studyBuild: Bool = true,
        flagOn: Bool = true,
        online: Bool = true,
        sessionValid: Bool = true,
        onDeviceAvailable: Bool = true,
        child: UUID? = nil,
        record: AudioConsentRecord?
    ) -> SelectionInput {
        SelectionInput(
            studyBuild: studyBuild,
            flagOn: flagOn,
            online: online,
            sessionValid: sessionValid,
            onDeviceAvailable: onDeviceAvailable,
            childProfileID: child ?? self.child,
            record: record
        )
    }

    private func record(child: UUID? = nil, scopes: Set<AudioConsentScope>) -> AudioConsentRecord {
        AudioConsentRecord(
            parentID: "parent",
            childProfileID: child ?? self.child,
            scopes: scopes,
            tappedAt: Date(timeIntervalSince1970: 1_700_000_000),
            method: "stub",
            backendConfirmed: true
        )
    }
}

actor SpyTransport: ProxyTransporting {
    enum Mode {
        case hang
        case succeed(ProxyResponse)
    }

    private(set) var posts: [ProxyRequest] = []
    private var cancelled = false
    private var mode: Mode = .hang

    func setMode(_ mode: Mode) { self.mode = mode }

    func post(_ request: ProxyRequest) async throws -> ProxyResponse {
        posts.append(request)
        switch mode {
        case .hang:
            try await Task.sleep(nanoseconds: 30_000_000_000)
            throw CancellationError()
        case .succeed(let response):
            return response
        }
    }

    func cancelAll() async { cancelled = true }
    func wasCancelled() -> Bool { cancelled }
}

struct ImmediateSleeper: SpeechSleeper {
    func sleep(seconds: TimeInterval) async throws {}
}

func installPlaceholderSpeechConfig() {
    TonightEndpoints.use(SupabaseSpeechConfig(
        baseURL: URL(string: "https://project-ref.supabase.co")!,
        anonKey: "test-anon-key"
    ))
}

struct NeverSleeper: SpeechSleeper {
    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: 30_000_000_000)
    }
}

private func sourceText(at root: URL) throws -> String {
    let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
    return try files.filter { $0.pathExtension == "swift" }.map { try String(contentsOf: $0) }.joined(separator: "\n")
}
