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
