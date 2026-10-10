import AuthKit
import SpeechKit
import SwiftUI

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

/// Composition root for the placeholder shell. Sign-in persists the parent session in the Keychain.
/// Unit tests inject `InMemorySessionStore`. The server-speech flag is the compile-time default.
enum TonightComposition {
    static let speechFlags = SpeechFeatureFlags()
    static let sessionStore: any ParentSessionStoring = KeychainSessionStore()

    @MainActor
    static func makeModel() -> TonightModel {
        TonightModel(sessionStore: sessionStore)
    }
}
