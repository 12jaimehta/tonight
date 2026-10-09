import XCTest
@testable import MarkingKit

final class MarkingKitPlaceholderTests: XCTestCase {
    func testModuleIsLoadable() {
        XCTAssertEqual(MarkingKit.moduleName, "MarkingKit")
    }
}
