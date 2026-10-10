# Tonight for iOS

Native app for classes 1–3 (ages 6–8). This tree is the M0 foundation: Swift packages, scoring, on-device speech, and placeholder screens. Product flows after M0 are not in this branch yet.

The app target is iOS 17 or newer, iPhone, portrait only. Bundle id `com.tonight.homework`. The speech path that uses `SpeechAnalyzer` needs the iOS 26 SDK (Xcode 26). There are no third-party packages.

`Tonight.xcworkspace` opens the app project. The app links the local package at `Packages/Tonight`. Launch argument `-TonightFixedGate` uses the spelled-out challenge "three hundred and forty-seven" (347). The server-speech flag is the compile-time default in `SpeechFeatureFlags`. It is not stored in UserDefaults.

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
| PaywallKit | 7-night trial on the annual plan only, monthly 149 INR, annual 999 INR. No trial on the monthly plan. Family Sharing is off. Flag off. Parental gate required. No store network. |
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

## Run on a personal iPhone

The app is signed with a free Apple ID (Personal Team). The project leaves `DEVELOPMENT_TEAM` empty so Xcode can fill in that team on your Mac.

1. Open `Tonight.xcworkspace`, select the Tonight target, and open Signing & Capabilities.
2. Set Team to your Personal Team.
3. If the bundle id `com.tonight.homework` is already taken, change it to one that belongs to you, such as `com.yourname.tonight`.
4. Connect the iPhone, choose it as the run destination, and run Tonight.
5. On the iPhone, open Settings → General → VPN & Device Management, trust the developer certificate, and open Tonight.

A Personal Team provisioning profile expires after 7 days. Run the app from Xcode again when it expires. A Personal Team can register up to 3 devices.

Sign in with Apple, push, and iCloud are off because they need a paid Apple Developer Program. Email OTP is the sign-in on screen. Local purchase testing uses `Tonight.storekit` on the Tonight scheme: ₹149 a month with no trial, and ₹999 a year with a 7-day free trial. Family Sharing is off, and the configuration does not contact the App Store.
