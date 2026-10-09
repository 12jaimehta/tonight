import XCTest
@testable import PracticeKit

final class PracticeKitPlaceholderTests: XCTestCase {
    func testModuleIsLoadable() {
        XCTAssertEqual(PracticeKit.moduleName, "PracticeKit")
    }
}
