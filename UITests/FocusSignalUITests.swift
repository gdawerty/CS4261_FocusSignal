import XCTest

final class FocusSignalUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset"]
        app.launch()
    }

    private func startDemo() {
        XCTAssertTrue(app.buttons["setupSession"].waitForExistence(timeout: 10))
        app.buttons["setupSession"].tap()
        let start = app.buttons["startFocusSession"]
        for _ in 0..<4 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable)
        start.tap()
        XCTAssertTrue(app.staticTexts["activeSession"].waitForExistence(timeout: 5))
    }

    private func startShortcutsSession() {
        XCTAssertTrue(app.buttons["setupSession"].waitForExistence(timeout: 10))
        app.buttons["setupSession"].tap()
        let mode = app.segmentedControls["sessionMode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.buttons["Shortcuts"].tap()
        let start = app.buttons["startFocusSession"]
        for _ in 0..<5 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable)
        start.tap()
        XCTAssertTrue(app.staticTexts["activeSession"].waitForExistence(timeout: 5))
    }

    private func openTestingPanel() {
        let panel = app.buttons["testingPanel"]
        for _ in 0..<3 where !panel.isHittable { app.swipeUp() }
        panel.tap()
        XCTAssertTrue(app.buttons["simulate.video"].waitForExistence(timeout: 5))
    }

    func testDemoIgnoresProductiveAppsAndPersistsGoBackResults() {
        startDemo()
        openTestingPanel()
        app.buttons["simulate.productive"].tap()
        XCTAssertTrue(app.staticTexts["attemptCount"].label.contains("0"))
        app.buttons["simulate.video"].tap()
        app.buttons["simulate.feed"].tap()
        XCTAssertFalse(app.staticTexts["frictionTitle"].exists)
        app.buttons["simulate.forum"].tap()
        XCTAssertTrue(app.staticTexts["frictionTitle"].waitForExistence(timeout: 5))
        app.buttons["friction.goBack"].tap()
        XCTAssertTrue(app.buttons["simulate.video"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let end = app.buttons["endSession"]
        for _ in 0..<4 where !end.isHittable { app.swipeUp() }
        end.tap()
        XCTAssertTrue(app.navigationBars["Session results"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["results.goBack"].label.contains("100%"))
        let save = app.buttons["saveRatings"]
        for _ in 0..<3 where !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertEqual(save.label, "Update Ratings")
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Studying").firstMatch.waitForExistence(timeout: 5))
        app.buttons.containing(.staticText, identifier: "Studying").firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["results.goBack"].label.contains("100%"))
        let updatedSave = app.buttons["saveRatings"]
        for _ in 0..<8 where !updatedSave.isHittable { app.swipeUp() }
        XCTAssertEqual(updatedSave.label, "Update Ratings")
    }

    func testContinueExemptionSurvivesRelaunchAndOtherAppCanTrigger() {
        startDemo()
        openTestingPanel()
        app.buttons["triggerNow"].tap()
        XCTAssertTrue(app.buttons["friction.continue"].waitForExistence(timeout: 5))
        app.buttons["friction.continue"].tap()
        XCTAssertTrue(app.staticTexts["Why do you want to continue?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["continueReason.needSomething"].exists)
        app.buttons["continueReason.needSomething"].tap()
        // Force chooses the first available app (feed), because selected demo IDs are sorted.
        app.buttons["simulate.feed"].tap()
        XCTAssertTrue(app.staticTexts["demoFeedback"].label.contains("Allowed until"))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["activeSession"].waitForExistence(timeout: 5))
        openTestingPanel()
        app.buttons["simulate.feed"].tap()
        XCTAssertTrue(app.staticTexts["demoFeedback"].label.contains("Allowed until"))
        app.buttons["triggerNow"].tap()
        XCTAssertTrue(app.buttons["friction.goBack"].waitForExistence(timeout: 5))
        app.buttons["friction.goBack"].tap()
        XCTAssertTrue(app.staticTexts["triggerCount"].label.contains("2"))
    }

    func testZeroDecisionSessionDoesNotShowMisleadingPercentages() {
        startDemo()
        let end = app.buttons["endSession"]
        for _ in 0..<4 where !end.isHittable { app.swipeUp() }
        end.tap()
        XCTAssertTrue(app.navigationBars["Session results"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["results.goBack"].label.contains("—"))
        XCTAssertTrue(app.descendants(matching: .any)["results.continue"].label.contains("—"))
    }

    func testShortcutURLEventsOpenFrictionAtConfiguredThreshold() {
        startShortcutsSession()
        // The accessibility element type differs across iOS versions.
        let shortcutLink = app.descendants(matching: .any)["shortcutTestLink"]
        for _ in 0..<5 where !shortcutLink.isHittable { app.swipeUp() }
        XCTAssertTrue(shortcutLink.waitForExistence(timeout: 5))

        shortcutLink.tap()
        XCTAssertFalse(app.staticTexts["frictionTitle"].exists)
        shortcutLink.tap()
        XCTAssertFalse(app.staticTexts["frictionTitle"].exists)
        shortcutLink.tap()

        XCTAssertTrue(app.staticTexts["frictionTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["friction.goBack"].exists)
        XCTAssertTrue(app.buttons["friction.continue"].exists)
        app.buttons["friction.continue"].tap()
        XCTAssertTrue(app.buttons["continueReason.takingBreak"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["continueReason.cancel"].exists)
        app.buttons["continueReason.cancel"].tap()
        app.buttons["friction.goBack"].tap()

        // A later reported selected-app event is follow-up evidence even while cooldown
        // prevents it from becoming another intervention trigger.
        shortcutLink.tap()
        let end = app.buttons["endSession"]
        for _ in 0..<5 where !end.isHittable { app.swipeUp() }
        end.tap()
        XCTAssertTrue(app.navigationBars["Session results"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["results.reopened"].label.contains("1"))
        XCTAssertTrue(app.descendants(matching: .any)["results.noReopen"].label.contains("0"))
    }
}
