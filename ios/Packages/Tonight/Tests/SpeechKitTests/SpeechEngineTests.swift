import XCTest
@testable import SpeechKit

final class SpeechEngineTests: XCTestCase {
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

    func testCG08_onDeviceWithdrawalCascades() {
        var granted = record(scopes: [.server])
        granted.withdrawnAt = Date()
        granted.withdrawnScopes = [.onDevice, .server]
        let selection = SpeechEngineSelector.select(eligibleInput(record: granted))
        XCTAssertEqual(selection.engine, .none)
        XCTAssertFalse(selection.maySendAudio)
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

        let own = record(child: otherChild, scopes: [.onDevice])
        let local = SpeechEngineSelector.select(eligibleInput(child: otherChild, record: own))
        XCTAssertEqual(local.engine, .appleOnDevice)
        XCTAssertFalse(local.maySendAudio)
    }

    func testCG14_offlineRefusesServerImmediately() {
        let selection = SpeechEngineSelector.select(eligibleInput(online: false, record: record(scopes: [.onDevice, .server])))
        XCTAssertEqual(selection.engine, .appleOnDevice)
        XCTAssertEqual(selection.reason, .offline)
        XCTAssertFalse(selection.maySendAudio)
    }

    func testCG17_releaseBuildCannotEnableTheFlag() {
        XCTAssertFalse(SpeechFeatureFlags().sarvamEnabled)
        let selection = SpeechEngineSelector.select(
            input(studyBuild: false, flagOn: true, record: record(scopes: [.onDevice, .server]))
        )
        XCTAssertEqual(selection.engine, .appleOnDevice)
        XCTAssertEqual(selection.reason, .releaseBuild)
        XCTAssertFalse(ServerSpeechBuild.isStudyBuild)
        XCTAssertFalse(selection.maySendAudio)
    }

    func testLAT04_offlineUnavailableBecomesParentMarking() {
        let selection = SpeechEngineSelector.select(
            eligibleInput(online: false, onDeviceAvailable: false, record: record(scopes: [.onDevice, .server]))
        )
        XCTAssertEqual(selection.engine, .parentMarking)
        XCTAssertFalse(selection.maySendAudio)
    }

    func testOnDeviceWithdrawalClearsBothScopes() {
        let store = AudioConsentStore()
        store.grant(record(scopes: [.onDevice, .server]))
        store.withdraw(childProfileID: child, scopes: [.onDevice], at: Date())
        XCTAssertEqual(store.record(for: child)?.scopeIsActive(.onDevice), false)
        XCTAssertEqual(store.record(for: child)?.scopeIsActive(.server), false)
    }

    func testAllowlistRejectsOtherHosts() throws {
        XCTAssertNoThrow(try TonightEndpoints.validate(TonightEndpoints.proxyBaseURL))
        let speech = try SarvamProxyConfiguration().speechURL()
        XCTAssertEqual(speech.host, "project-ref.supabase.co")
        XCTAssertEqual(speech.path, "/functions/v1/sarvam-proxy")
        XCTAssertEqual(OnDeviceRequestPolicy.requiresOnDeviceRecognition, true)
        XCTAssertEqual(OnDeviceRequestPolicy.localeIdentifier, "en-IN")
        XCTAssertEqual(OnDeviceRequestPolicy.serverTimeout, 8)
        for host in ["api.sarvam.ai", "firebaseio.com", "api.openai.com", "example.supabase.co"] {
            XCTAssertThrowsError(try TonightEndpoints.validate(URL(string: "https://\(host)/speech")!))
        }
    }

    func testProxyURLIsTheOnlyConfiguredHost() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let package = root.appendingPathComponent("Package.swift")
        let text = try sourceText(at: sources) + (try String(contentsOf: package))
        XCTAssertFalse(text.contains("firebase"))
        XCTAssertFalse(text.contains("import Supabase"))
        XCTAssertFalse(text.contains("supabase-swift"))
        XCTAssertFalse(text.contains("URLSessionConfiguration.background"))
        XCTAssertFalse(text.contains("beginBackgroundTask"))
        XCTAssertFalse(text.contains("BGTaskScheduler"))
        assertNoVendorSecret(in: text)
        XCTAssertFalse(text.contains("AVAudioFile"))
        XCTAssertTrue(text.contains("requiresOnDeviceRecognition = OnDeviceRequestPolicy.requiresOnDeviceRecognition"))
        let urls = text.split(separator: "\"").map(String.init).filter { $0.hasPrefix("https://") }
        XCTAssertEqual(urls, [])
    }

    func testAudioStorageIsMemoryOnly() {
        var audio = SpeechAudio(samples: Data([1, 2, 3]))
        XCTAssertEqual(audio.storage, .memory)
        audio.discard()
        XCTAssertTrue(audio.samples.isEmpty)
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

final class RecordingSynthesizer: SpeechSynthesizing, @unchecked Sendable {
    var spoken: [(text: String, rate: Float)] = []

    func speak(_ text: String, rate: Float) async {
        spoken.append((text, rate))
    }

    func stop() {}
}

final class SpokenCueTests: XCTestCase {
    func testHearItAsksForThePassage() async {
        let fake = RecordingSynthesizer()
        await SpokenCue.passage("Ravi has a red kite.", using: fake)
        XCTAssertEqual(fake.spoken.map(\.text), ["Ravi has a red kite."])
        XCTAssertEqual(fake.spoken.map(\.rate), [IndianEnglishSpeech.passageRate])
    }

    func testHearWordAsksForTheWord() async {
        let fake = RecordingSynthesizer()
        await SpokenCue.word("strong", using: fake)
        XCTAssertEqual(fake.spoken.map(\.text), ["strong"])
        XCTAssertEqual(fake.spoken.map(\.rate), [IndianEnglishSpeech.wordRate])
    }
}

private func assertNoVendorSecret(in text: String, file: StaticString = #filePath, line: UInt = #line) {
    let withoutAnonHeader = text.replacingOccurrences(of: "\"apikey\"", with: "")
    XCTAssertFalse(
        withoutAnonHeader.localizedCaseInsensitiveContains("apikey"),
        "the Supabase anon-key header is the only api key name allowed",
        file: file,
        line: line
    )
    XCTAssertFalse(text.localizedCaseInsensitiveContains("x-api-key"), file: file, line: line)
}

private func sourceText(at root: URL) throws -> String {
    let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
    return try files.filter { $0.pathExtension == "swift" }.map { try String(contentsOf: $0) }.joined(separator: "\n")
}
