import XCTest
@testable import Telemetry

final class TelemetryTests: XCTestCase {
    func testLogStoresNamesAndTimeOnly() throws {
        let log = TonightEventLog()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        log.record(.gateUnlocked, at: when)
        log.record(.paywallBlocked, at: when)
        XCTAssertEqual(log.snapshot(), [
            TonightEvent(name: .gateUnlocked, recordedAt: when),
            TonightEvent(name: .paywallBlocked, recordedAt: when),
        ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(log.snapshot()[0])
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(Set(object?.keys ?? []), ["name", "recordedAt"])
        XCTAssertEqual(object?["name"] as? String, "gate.unlocked")
    }

    func testNamesAreClosedIdentifiers() {
        XCTAssertFalse(TelemetryPolicy.acceptsFreeText)
        XCTAssertFalse(TelemetryPolicy.usesThirdPartySDK)
        for name in TonightEventName.allCases {
            XCTAssertFalse(name.rawValue.contains(" "))
            XCTAssertFalse(name.rawValue.isEmpty)
        }
    }

    func testSourcesHaveNoThirdPartySDK() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Telemetry")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        let text = try files.filter { $0.pathExtension == "swift" }.map { try String(contentsOf: $0) }.joined(separator: "\n")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("firebase"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("mixpanel"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("amplitude"))
        XCTAssertFalse(text.contains("https://"))
        XCTAssertFalse(text.contains("message"))
    }
}
