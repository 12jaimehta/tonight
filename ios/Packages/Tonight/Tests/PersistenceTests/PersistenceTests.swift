import XCTest
@testable import Persistence

final class PersistencePlaceholderTests: XCTestCase {
    func testModuleIsLoadable() {
        XCTAssertEqual(Persistence.moduleName, "Persistence")
    }
}
