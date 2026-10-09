# Tonight for iOS

Native app for classes 1–3 (ages 6–8). This tree is the M0 foundation: Swift packages, scoring, on-device speech, and placeholder screens. Product flows after M0 are not in this branch yet.

The app target is iOS 17 or newer. The speech path that uses `SpeechAnalyzer` needs the iOS 26 SDK (Xcode 26). There are no third-party packages.

## Modules

`TonightApp` is the composition root (routing and dependencies). The libraries live in `Packages/Tonight`:

| Module | Responsibility |
| --- | --- |
| DesignSystem | OKLCH colour tokens and static placeholder views |
| AuthKit | Parent session and adult-consent record |
| ProfilesKit | Child profiles, subject catalogue, audience config, parental gate |
| TaskKit | One homework item, check mode, stars, activity seams |
| CaptureKit | Page-photo policy and OCR protocol |
| SpeechKit | On-device recognition, consent, and the study-only server adapter |
| MarkingKit | Word alignment and answer scoring |
| PracticeKit | Remember list |
| PaywallKit | Trial and price catalogue, flag off |
| Persistence | SwiftData schema and protected files |
| Telemetry | First-party event names, no third-party SDK |

## Tests

From a Mac with Xcode 26:

```sh
cd ios/Packages/Tonight
xcodebuild test -scheme Tonight -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

`xcodebuild` is not available in the environment that prepared this branch, so these tests have not been executed here.
