import SwiftUI
import SpeechKit

@main
struct TonightApp: App {
    init() {
        TonightEndpoints.use(bundle: .main)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Composition root for the placeholder shell. The server-speech flag is the compile-time default.
enum TonightComposition {
    static let speechFlags = SpeechFeatureFlags()
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
