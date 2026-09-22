import XCTest

/// Drives the #52 Instruments scenarios against the launch-argument fixtures.
///
/// This is the on-device choreography for groups scroll, timeline scroll, amount
/// entry, split editing, and swipe release. Traces themselves stay out of git.
final class PerformanceBaselineUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBaselineScenarios() throws {
        let app = launchScenarioApp()
        try runScenarios(in: app)
    }

    @MainActor
    func testBaselineScenariosWithReduceMotion() throws {
        try enableReduceMotion(true)
        addTeardownBlock {
            try? self.enableReduceMotion(false)
        }

        let app = launchScenarioApp()
        try runScenarios(in: app)
    }

    @MainActor
    private func launchScenarioApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-SplittyPerformanceScenario")
        app.launch()
        return app
    }

    @MainActor
    private func runScenarios(in app: XCUIApplication) throws {
        let groups = app.scrollViews["groups.scroll"]
        XCTAssertTrue(groups.waitForExistence(timeout: 10), "Expected the 100-group fixture list.")

        groups.swipeUp(velocity: .fast)
        groups.swipeUp(velocity: .fast)
        groups.swipeDown(velocity: .fast)

        let firstGroup = app.buttons["groups.card"].firstMatch
        XCTAssertTrue(firstGroup.waitForExistence(timeout: 5))
        firstGroup.tap()

        let timeline = app.scrollViews["group.timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 10), "Expected the 500-expense timeline.")
        timeline.swipeUp(velocity: .fast)
        timeline.swipeUp(velocity: .fast)
        timeline.swipeDown(velocity: .fast)

        let addExpense = app.buttons["group.addExpense"]
        XCTAssertTrue(addExpense.waitForExistence(timeout: 5))
        addExpense.tap()

        XCTAssertTrue(app.buttons["keypad.key.5"].waitForExistence(timeout: 5))
        for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] {
            app.buttons["keypad.key.\(key)"].tap()
        }

        app.buttons["expense.next"].tap()
        XCTAssertTrue(app.buttons["expense.split"].waitForExistence(timeout: 5))
        app.buttons["expense.split"].tap()

        let splitMode = app.otherElements["split.mode"]
        XCTAssertTrue(
            splitMode.waitForExistence(timeout: 5) || app.buttons["split.payer"].waitForExistence(timeout: 5)
        )
        app.swipeUp(velocity: .fast)
        app.swipeUp(velocity: .fast)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["expense.cancel"].tap()

        let row = app.otherElements["timeline.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft(velocity: .fast)
        row.swipeRight(velocity: .fast)
    }

    @MainActor
    private func enableReduceMotion(_ enabled: Bool) throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        settings.launch()

        if settings.buttons["Back"].exists {
            settings.buttons["Back"].tap()
        }

        let search = settings.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Reduce Motion")
            let result = settings.cells.containing(.staticText, identifier: "Reduce Motion").firstMatch
            if result.waitForExistence(timeout: 5) {
                result.tap()
            }
        } else {
            XCTAssertTrue(settings.cells["Accessibility"].waitForExistence(timeout: 8))
            settings.cells["Accessibility"].tap()
            XCTAssertTrue(settings.cells["Motion"].waitForExistence(timeout: 8))
            settings.cells["Motion"].tap()
        }

        let toggle = settings.switches["Reduce Motion"]
        guard toggle.waitForExistence(timeout: 8) else {
            throw XCTSkip("Could not reach the Reduce Motion switch on this OS.")
        }

        let isOn = (toggle.value as? String) == "1"
        if isOn != enabled {
            toggle.tap()
        }
        settings.terminate()
    }
}
