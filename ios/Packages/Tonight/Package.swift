// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tonight",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "AuthKit", targets: ["AuthKit"]),
        .library(name: "ProfilesKit", targets: ["ProfilesKit"]),
        .library(name: "TaskKit", targets: ["TaskKit"]),
        .library(name: "CaptureKit", targets: ["CaptureKit"]),
        .library(name: "SpeechKit", targets: ["SpeechKit"]),
        .library(name: "MarkingKit", targets: ["MarkingKit"]),
        .library(name: "PracticeKit", targets: ["PracticeKit"]),
        .library(name: "PaywallKit", targets: ["PaywallKit"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Telemetry", targets: ["Telemetry"]),
        .library(name: "GateHarness", targets: ["GateHarness"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),

        .target(name: "MarkingKit"),
        .testTarget(
            name: "MarkingKitTests",
            dependencies: ["MarkingKit"],
            resources: [.copy("Fixtures")]
        ),

        .target(name: "SpeechKit"),
        .testTarget(name: "SpeechKitTests", dependencies: ["SpeechKit"]),

        .target(name: "AuthKit"),
        .testTarget(name: "AuthKitTests", dependencies: ["AuthKit"]),

        .target(name: "ProfilesKit"),
        .testTarget(name: "ProfilesKitTests", dependencies: ["ProfilesKit"]),

        .target(name: "TaskKit", dependencies: ["MarkingKit"]),
        .testTarget(name: "TaskKitTests", dependencies: ["TaskKit", "MarkingKit"]),

        .target(name: "CaptureKit"),
        .testTarget(name: "CaptureKitTests", dependencies: ["CaptureKit"]),

        .target(name: "PracticeKit"),
        .testTarget(name: "PracticeKitTests", dependencies: ["PracticeKit"]),

        .target(name: "PaywallKit"),
        .testTarget(name: "PaywallKitTests", dependencies: ["PaywallKit"]),

        .target(
            name: "Persistence",
            dependencies: ["ProfilesKit", "TaskKit", "PracticeKit", "AuthKit"]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "ProfilesKit", "TaskKit", "PracticeKit", "AuthKit"]
        ),

        .target(name: "Telemetry"),
        .testTarget(name: "TelemetryTests", dependencies: ["Telemetry"]),

        .target(name: "GateHarness"),
        .testTarget(
            name: "GateHarnessTests",
            dependencies: ["GateHarness"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
