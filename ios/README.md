# Tonight for iOS

Native app for classes 1–3 (ages 6–8). This tree is the M0 foundation: Swift packages, scoring, on-device speech, and placeholder screens. Product flows after M0 are not in this branch yet.

The app target is iOS 17 or newer, iPhone, portrait only. Bundle id `com.tonight.homework`. The speech path that uses `SpeechAnalyzer` needs the iOS 26 SDK (Xcode 26). There are no third-party packages.

`Tonight.xcworkspace` opens the app project. The app links the local package at `Packages/Tonight`. Launch argument `-TonightFixedGate` uses the first parental-gate challenge (`47 × 36`). The server-speech flag is the compile-time default in `SpeechFeatureFlags`. It is not stored in UserDefaults.

## Modules

`TonightApp` is the composition root (routing and dependencies). The libraries live in `Packages/Tonight`:

| Module | Responsibility |
| --- | --- |
| DesignSystem | OKLCH tokens (bg, edge, fg, accent, soft) from a subject hue, plus static views. `TonightMotion.animationsInV1` is false. Lightness and chroma come from the generated recipe in `tokens.json`. |
| AuthKit | Parent session in the Keychain (never a PIN) and an adult-consent record. Tests use an in-memory session store. |
| ProfilesKit | Child profiles, per-child subject rows, subject catalogue, audience config, parental gate |
| TaskKit | One homework item, check mode, stars, notebook photo, praise, activity seams |
| CaptureKit | Page-photo policy and OCR protocol, plus a handwriting-engine seam. Photos are not saved to the camera roll. |
| SpeechKit | On-device recognition, consent, and the study-only server adapter |
| MarkingKit | Word alignment, answer scoring, and star counts derived from a mark |
| PracticeKit | Remember list. Two different correct days clear a word. Warmup is capped at 5. |
| PaywallKit | Trial of 7 nights, monthly 149 INR, annual cap 1499 INR. Flag off. Parental gate required. No store network. |
| Persistence | SwiftData schema V1, empty migration plan, `FileProtectionType.complete`. Photos are excluded from backup. `PhotoAccess` requires the parent unlock. |
| Telemetry | First-party event names only. No free text and no third-party SDK. |

## Tests

`xcodebuild` and `swift` are not installed in the environment that prepared this branch, so these tests have not been executed here.

Package tests, from a Mac with Xcode 26. The package scheme is `Tonight-Package`:

```sh
cd ios/Packages/Tonight
xcodebuild test -scheme Tonight-Package -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

To compile the package tests without a named simulator:

```sh
cd ios/Packages/Tonight
xcodebuild build-for-testing -scheme Tonight-Package -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

App and UI tests:

```sh
cd ios
xcodebuild test -workspace Tonight.xcworkspace -scheme Tonight -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```
