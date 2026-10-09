import XCTest
@testable import Telemetry

final class TelemetryPlaceholderTests: XCTestCase {
    func testModuleIsLoadable() {
        XCTAssertEqual(Telemetry.moduleName, "Telemetry")
    }
}
