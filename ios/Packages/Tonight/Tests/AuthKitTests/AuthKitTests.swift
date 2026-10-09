import XCTest
@testable import AuthKit

final class AuthKitPlaceholderTests: XCTestCase {
    func testModuleIsLoadable() {
        XCTAssertEqual(AuthKit.moduleName, "AuthKit")
    }
}
