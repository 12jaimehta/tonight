import XCTest
@testable import PaywallKit

final class PaywallKitPlaceholderTests: XCTestCase {
    func testModuleIsLoadable() {
        XCTAssertEqual(PaywallKit.moduleName, "PaywallKit")
    }
}
