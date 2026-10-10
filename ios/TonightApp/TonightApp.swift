import AuthKit
import Persistence
import SpeechKit
import SwiftData
import SwiftUI

@main
struct TonightApp: App {
    private let consentCenter: ConsentCenter

    init() {
        TonightEndpoints.use(bundle: .main)
        consentCenter = (try? TonightComposition.makeConsentCenter()) ?? TonightComposition.unconfiguredCenter()
    }

    var body: some Scene {
        WindowGroup {
            RootView(consentCenter: consentCenter, emailOTP: TonightComposition.makeEmailOTP())
        }
    }
}

/// Composition root for the placeholder shell. The server-speech flag is the compile-time default.
enum TonightComposition {
    static let speechFlags = SpeechFeatureFlags()

    static func makeConsentCenter() throws -> ConsentCenter {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Tonight", isDirectory: true)
        let ledgerDirectory = base.appendingPathComponent("speech-ledger", isDirectory: true)
        let storeURL = base.appendingPathComponent("Tonight.store")
        let container = try TonightStore.makeContainer(at: storeURL)
        let eraser = StoreChildEraser(context: ModelContext(container))
        return try ConsentCenter.make(directory: ledgerDirectory, eraser: eraser, sender: deletionSender())
    }

    static func unconfiguredCenter() -> ConsentCenter {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tonight-consent-\(UUID().uuidString)", isDirectory: true)
        return (try? ConsentCenter.make(
            directory: directory,
            eraser: IgnoringChildEraser(),
            sender: FailingDeletionSender()
        )) ?? ConsentCenter(ledger: try! SpeechLedger(directory: directory), eraser: IgnoringChildEraser(), sender: FailingDeletionSender())
    }

    static func makeEmailOTP() -> EmailOTPClient? {
        guard let config = SupabaseAuthConfig.load(from: .main) else { return nil }
        return EmailOTPClient(
            config: config,
            transport: URLSessionOTPTransport(),
            sessions: KeychainSessionStore(),
            tokens: KeychainAccessTokenStore()
        )
    }

    private static func deletionSender() -> any DeletionSending {
        guard let config = SupabaseSpeechConfig.load(from: .main), !config.anonKey.isEmpty else {
            return FailingDeletionSender()
        }
        TonightEndpoints.use(config)
        return HostDeletionSender(
            post: { request in
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) else { throw DeletionSendError.rejected(status) }
            },
            baseURL: config.baseURL,
            anonKey: config.anonKey,
            accessToken: ""
        )
    }
}

private final class StoreChildEraser: ChildDataErasing, @unchecked Sendable {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func erase(childID: UUID) throws {
        try ChildWithdrawalErase.erase(childID: childID, in: context)
    }
}

enum TonightSpeechScene {
    static func makeRunner() -> SpeechAttemptRunner {
        let transport: any ProxyTransporting
        if ProcessInfo.processInfo.arguments.contains("-TonightStubUpload") {
            transport = StubHoldTransport()
        } else {
            transport = ForegroundProxyTransport()
        }
        return SpeechAttemptRunner(
            transport: transport,
            onDevice: FakeSpeechEngine(scripted: .unavailable("shell"))
        )
    }
}

/// Holds one foreground request open until `suspend()` cancels it. UI tests use this instead of a network call.
final class StubHoldTransport: ProxyTransporting, @unchecked Sendable {
    func post(_ request: ProxyRequest) async throws -> ProxyResponse {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        throw CancellationError()
    }

    func cancelAll() async {}
}
