import XCTest
@testable import SpeechKit

final class SpeechKitPlaceholderTests: XCTestCase {
    func testModuleIsLoadable() {
        XCTAssertEqual(SpeechKit.moduleName, "SpeechKit")
    }
}
