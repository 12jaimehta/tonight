import XCTest

final class TonightUITests: XCTestCase {
    // Camera capture, the microphone, on-device speech recognition, and spoken playback
    // are not driven here. Those screens show their denied and idle states without the hardware.
    func testSignInPlaceholderContinues() {
        let app = launch()
        app.buttons["signin.apple"].tap()
        XCTAssertTrue(app.staticTexts["A grown-up sets up Tonight"].waitForExistence(timeout: 8))
    }

    func testConsentStaysClosedUntilThePlaceholderIsAccepted() {
        let app = launch(screen: "consent")
        XCTAssertTrue(app.buttons["consent.accept"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["consent.accept"].label, "Consent copy placeholder")
        let agree = app.buttons["consent.agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 5))
        XCTAssertFalse(agree.isEnabled)
        app.buttons["consent.accept"].tap()
        XCTAssertTrue(agree.isEnabled)
        agree.tap()
        XCTAssertTrue(app.staticTexts["Add a child"].waitForExistence(timeout: 5))
    }

    func testAddChildRejectsALongNickname() {
        let app = launch(screen: "addChild")
        let next = app.buttons["child.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        XCTAssertFalse(next.isEnabled)
        let field = app.textFields["child.nickname"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("This nickname is far too long")
        XCTAssertTrue(app.staticTexts["Use a short nickname, up to 16 letters."].waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled)
        clear(field, in: app)
        field.typeText("Aarav")
        XCTAssertTrue(next.isEnabled)
    }

    func testSubjectHideAndReorderKeepTheLastSubject() {
        let app = launch(screen: "subjects")
        let order = app.staticTexts["subject.order"]
        XCTAssertTrue(order.waitForExistence(timeout: 8))
        XCTAssertTrue(order.label.contains("english, hindi, maths, evs"))
        app.buttons["subject.down.english"].tap()
        XCTAssertTrue(order.label.contains("hindi, english, maths, evs"))
        app.buttons["subject.hide.hindi"].tap()
        app.buttons["subject.hide.english"].tap()
        app.buttons["subject.hide.maths"].tap()
        app.buttons["subject.hide.evs"].tap()
        XCTAssertTrue(app.staticTexts["Keep at least one subject."].waitForExistence(timeout: 5))
        XCTAssertTrue(order.label.contains("english"))
        XCTAssertTrue(order.label.contains("hindi"))
        XCTAssertTrue(order.label.contains("maths"))
        XCTAssertTrue(order.label.contains("evs"))
    }

    func testFixedGateUnlocksWithTheSpelledNumber() {
        let app = launch(screen: "child")
        XCTAssertTrue(app.buttons["subject.english"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["subject.english"].label.contains("English"))
        XCTAssertTrue(app.buttons["subject.hindi"].label.contains("हिन्दी"))
        XCTAssertTrue(app.buttons["subject.maths"].label.contains("Maths"))
        XCTAssertTrue(app.buttons["subject.evs"].label.contains("EVS"))
        app.buttons["child.lock"].tap()
        XCTAssertTrue(app.staticTexts["three hundred and forty-seven"].waitForExistence(timeout: 5))
        tapDigits(["3", "4", "7"], in: app)
        XCTAssertTrue(app.staticTexts["Tonight for Aarav"].waitForExistence(timeout: 5))
    }

    func testWrongGateAnswerStaysWithTheChild() {
        let app = launch(screen: "child")
        app.buttons["child.lock"].tap()
        XCTAssertTrue(app.staticTexts["three hundred and forty-seven"].waitForExistence(timeout: 5))
        tapDigits(["1", "1", "1"], in: app)
        XCTAssertTrue(app.staticTexts["Let's try a different one."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Tonight for Aarav"].exists)
        XCTAssertTrue(app.staticTexts["three hundred and forty-seven"].exists)
    }

    func testEnglishReadAloudCannotSaveWithoutConfirmedText() {
        let app = launch(screen: "newTask")
        app.buttons["task.subject.english"].tap()
        app.buttons["task.next"].tap()
        XCTAssertTrue(app.buttons["task.typeInstead"].waitForExistence(timeout: 5))
        app.buttons["task.typeInstead"].tap()
        let looks = app.buttons["task.looksRight"]
        XCTAssertTrue(looks.waitForExistence(timeout: 5))
        XCTAssertFalse(looks.isEnabled)
        let field = app.descendants(matching: .any)["task.manual"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Ravi has a red kite")
        XCTAssertTrue(looks.isEnabled)
    }

    func testNotebookTaskNeedsAPhotoBeforeSave() {
        let app = launch(screen: "newTask")
        app.buttons["task.subject.maths"].tap()
        XCTAssertTrue(app.staticTexts["Tonight can only mark English reading for now. You'll check Maths yourself; it takes about a minute."].waitForExistence(timeout: 5))
        app.buttons["task.next"].tap()
        XCTAssertTrue(app.buttons["task.skipPhoto"].waitForExistence(timeout: 5))
        app.buttons["task.skipPhoto"].tap()
        let save = app.buttons["task.saveLater"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(app.buttons["task.saveHand"].isEnabled)
        app.buttons["task.back"].tap()
        app.buttons["task.fromPhotos"].tap()
        app.buttons["task.next"].tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
    }

    private func launch(screen: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-TonightFixedGate"]
        if let screen {
            arguments += ["-TonightScreen", screen]
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func tapDigits(_ digits: [String], in app: XCUIApplication) {
        for digit in digits {
            app.buttons["gate.key.\(digit)"].tap()
        }
    }

    private func clear(_ field: XCUIElement, in app: XCUIApplication) {
        field.tap()
        field.press(forDuration: 1.1)
        if app.menuItems["Select All"].waitForExistence(timeout: 1) {
            app.menuItems["Select All"].tap()
            field.typeText(XCUIKeyboardKey.delete.rawValue)
            return
        }
        guard let value = field.value as? String, value != "Nickname" else { return }
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }
}
