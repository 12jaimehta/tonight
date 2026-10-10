import XCTest

final class TonightUITests: XCTestCase {
    func testChildHomeShowsClassesAgesAndDefaultSubjects() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Classes 1–3"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Ages 6–8"].exists)
        XCTAssertTrue(app.staticTexts["English"].exists)
        XCTAssertTrue(app.staticTexts["हिन्दी"].exists)
        XCTAssertTrue(app.staticTexts["Maths"].exists)
        XCTAssertTrue(app.staticTexts["EVS"].exists)
        XCTAssertFalse(app.staticTexts["Parent area"].exists)
    }

    func testParentAreaStaysBehindTheFixedGate() {
        let app = launch()
        app.buttons["Parent"].tap()
        XCTAssertTrue(app.staticTexts["47 × 36"].waitForExistence(timeout: 5))
        let field = app.textFields["Answer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("1692")
        app.buttons["Unlock"].tap()
        XCTAssertTrue(app.staticTexts["Parent area"].waitForExistence(timeout: 5))
    }

    func testWrongAnswerDoesNotOpenTheParentArea() {
        let app = launch()
        app.buttons["Parent"].tap()
        let field = app.textFields["Answer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("1")
        app.buttons["Unlock"].tap()
        XCTAssertTrue(app.staticTexts["47 × 36"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Parent area"].exists)
    }

    func test_CG33_LAT10_backgroundThreeSecondsIntoAStubbedUpload() {
        let app = XCUIApplication()
        app.launchArguments = ["-TonightStubUpload"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Uploading"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 3)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["Suspended"].waitForExistence(timeout: 8))
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-TonightFixedGate"]
        app.launch()
        return app
    }
}
