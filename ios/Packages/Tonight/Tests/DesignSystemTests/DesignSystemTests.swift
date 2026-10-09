import XCTest
@testable import DesignSystem

final class DesignSystemPlaceholderTests: XCTestCase {
    func testModuleIsLoadable() {
        XCTAssertEqual(DesignSystem.moduleName, "DesignSystem")
    }
}
