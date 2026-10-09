import XCTest
@testable import TaskKit

final class TaskKitPlaceholderTests: XCTestCase {
    func testModuleIsLoadable() {
        XCTAssertEqual(TaskKit.moduleName, "TaskKit")
    }
}
