import XCTest
@testable import ProfilesKit

final class ProfilesKitPlaceholderTests: XCTestCase {
    func testModuleIsLoadable() {
        XCTAssertEqual(ProfilesKit.moduleName, "ProfilesKit")
    }
}
