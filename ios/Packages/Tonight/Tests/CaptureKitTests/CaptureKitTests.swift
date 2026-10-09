import XCTest
@testable import CaptureKit

final class CaptureKitPlaceholderTests: XCTestCase {
    func testModuleIsLoadable() {
        XCTAssertEqual(CaptureKit.moduleName, "CaptureKit")
    }
}
