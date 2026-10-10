import XCTest

final class TonightUITests: XCTestCase {
    // Camera capture, the microphone, on-device speech recognition, and spoken playback
    // are not driven here. Those screens show their denied and idle states without the hardware.
    func testEmailOTPRemainsAndAppleButtonIsAbsent() {
        let app = launch()
        let email = app.buttons["signin.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["signin.apple"].exists)
        XCTAssertFalse(app.buttons["Sign in with Apple"].exists)
        email.tap()
        let code = app.textFields["signin.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Check your email"].exists)
        code.tap()
        code.typeText("123456")
        let verify = app.buttons["signin.verify"]
        XCTAssertTrue(verify.waitForExistence(timeout: 5))
        XCTAssertTrue(verify.isEnabled)
        verify.tap()
        XCTAssertTrue(app.staticTexts["A grown-up sets up Tonight"].waitForExistence(timeout: 8))
    }

    func testPersonalTeamBuildOmitsSignInWithApple() throws {
        let iosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appRoot = iosRoot.appendingPathComponent("TonightApp")
        let sources = FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        let swift = try sources.filter { $0.pathExtension == "swift" }.map { try String(contentsOf: $0) }.joined(separator: "\n")
        XCTAssertFalse(swift.contains("import AuthenticationServices"))
        XCTAssertFalse(swift.contains("ASAuthorization"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: appRoot.appendingPathComponent("Tonight.entitlements").path))
        let project = try String(contentsOf: iosRoot.appendingPathComponent("Tonight.xcodeproj/project.pbxproj"))
        XCTAssertFalse(project.contains("CODE_SIGN_ENTITLEMENTS"))
        XCTAssertFalse(project.contains("com.apple.developer.applesignin"))
        XCTAssertFalse(project.contains("aps-environment"))
        XCTAssertFalse(project.contains("com.apple.developer.icloud"))
        XCTAssertFalse(project.contains("com.apple.developer.associated-domains"))
        XCTAssertFalse(project.contains("keychain-access-groups"))
        XCTAssertTrue(project.contains("DEVELOPMENT_TEAM = \"\";"))
        let info = try String(contentsOf: appRoot.appendingPathComponent("Info.plist"))
        XCTAssertFalse(info.contains("UIBackgroundModes"))
        XCTAssertFalse(info.contains("aps-environment"))
    }

    func testConsentStaysClosedUntilThePlaceholderIsAccepted() {
        let app = launch(screen: "consent")
        XCTAssertTrue(app.buttons["consent.accept"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["consent.accept"].label, "Consent copy placeholder")
        let agree = app.buttons["consent.agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 5))
        XCTAssertFalse(agree.isEnabled)
        app.buttons["consent.accept"].tap()
        let enabled = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: enabled, object: agree)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed)
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
        app.buttons["subject.handle.english"].press(forDuration: 0.5, thenDragTo: app.buttons["subject.handle.hindi"])
        XCTAssertTrue(order.label.contains("hindi, english, maths, evs"))
        app.buttons["subject.hide.hindi"].tap()
        app.buttons["subject.hide.english"].tap()
        app.buttons["subject.hide.maths"].tap()
        app.buttons["subject.handle.evs"].press(forDuration: 0.5, thenDragTo: app.buttons["subject.handle.english"])
        XCTAssertTrue(order.label.contains("evs"))
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

    func test_N23_emptyStateWhenThereIsNoConsent() {
        let app = launch(screen: "child")
        app.buttons["child.lock"].tap()
        XCTAssertTrue(app.staticTexts["three hundred and forty-seven"].waitForExistence(timeout: 5))
        tapDigits(["3", "4", "7"], in: app)
        app.buttons["today.settings"].tap()
        XCTAssertTrue(app.staticTexts["three hundred and forty-seven"].waitForExistence(timeout: 5))
        tapDigits(["3", "4", "7"], in: app)
        XCTAssertTrue(app.staticTexts["No consent on file"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["consent.withdraw"].exists)
    }

    func test_N23_seededConsentWithdrawsWithoutAPlaceholderGrant() throws {
        let app = launch(screen: "child", extra: ["-TonightSeedConsent"])
        app.buttons["child.lock"].tap()
        XCTAssertTrue(app.staticTexts["three hundred and forty-seven"].waitForExistence(timeout: 5))
        tapDigits(["3", "4", "7"], in: app)
        app.buttons["today.settings"].tap()
        tapDigits(["3", "4", "7"], in: app)
        XCTAssertTrue(app.buttons["consent.withdraw"].waitForExistence(timeout: 5))
        let model = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TonightApp/Flow/TonightModel.swift")
        let source = try String(contentsOf: model, encoding: .utf8)
        let withdraw = source.components(separatedBy: "func confirmWithdrawal").last ?? ""
        XCTAssertFalse(withdraw.contains("parent-placeholder"))
        XCTAssertFalse(withdraw.contains("consentCenter.grant"))
    }

    func test_P1_13_withdrawalClearsRememberMarksAndAudio() {
        let app = launch(screen: "child", extra: ["-TonightSeedLocalData"])
        app.buttons["child.lock"].tap()
        XCTAssertTrue(app.staticTexts["three hundred and forty-seven"].waitForExistence(timeout: 5))
        tapDigits(["3", "4", "7"], in: app)
        app.buttons["today.settings"].tap()
        XCTAssertTrue(app.staticTexts["three hundred and forty-seven"].waitForExistence(timeout: 5))
        tapDigits(["3", "4", "7"], in: app)
        let before = app.staticTexts["withdrawal.local"]
        XCTAssertTrue(before.waitForExistence(timeout: 5))
        XCTAssertEqual(before.label, "remember 1 marks 1 audio 1")
        app.buttons["consent.withdraw"].tap()
        app.buttons["consent.withdraw.confirm"].tap()
        let after = app.staticTexts["withdrawal.local"]
        XCTAssertTrue(after.waitForExistence(timeout: 5))
        XCTAssertEqual(after.label, "remember 0 marks 0 audio 0")
    }

    func test_CG32_withdrawConsentConfirmsBehindTheGate() {
        let app = launch(screen: "child", extra: ["-TonightSeedConsent"])
        app.buttons["child.lock"].tap()
        XCTAssertTrue(app.staticTexts["three hundred and forty-seven"].waitForExistence(timeout: 5))
        tapDigits(["3", "4", "7"], in: app)
        XCTAssertTrue(app.staticTexts["Tonight for Aarav"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["consent.withdraw"].exists)
        app.buttons["today.settings"].tap()
        XCTAssertTrue(app.staticTexts["three hundred and forty-seven"].waitForExistence(timeout: 5))
        tapDigits(["3", "4", "7"], in: app)
        let withdraw = app.buttons["consent.withdraw"]
        XCTAssertTrue(withdraw.waitForExistence(timeout: 5))
        withdraw.tap()
        let confirm = app.buttons["consent.withdraw.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Consent withdrawn"].waitForExistence(timeout: 5))
    }

    /// CG-33 / LAT-10 on the real app shell. A stubbed upload is cancelled when the scene leaves the foreground.
    func test_CG33_LAT10_backgroundThreeSecondsIntoAStubbedUpload() {
        let app = XCUIApplication()
        app.launchArguments = ["-TonightStubUpload", "-TonightFixedGate"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Uploading"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 3)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["Suspended"].waitForExistence(timeout: 8))
    }

    private func launch(screen: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-TonightFixedGate"] + extra
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
