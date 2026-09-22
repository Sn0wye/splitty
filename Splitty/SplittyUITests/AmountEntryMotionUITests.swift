//
//  AmountEntryMotionUITests.swift
//  SplittyUITests
//

import XCTest

/// Amount entry is the app's most frequent interaction, and the number on screen has to be
/// the latest one however fast the keys are hit. These drive the pad faster than a person
/// would and read what the amount says afterwards, with and without Reduce Motion, and check
/// that a released swipe still comes home.
///
/// Runs against the `-SplittyPerformanceScenario` fixtures, so there is no backend to reach.
final class AmountEntryMotionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRapidEntryShowsTheLatestAmount() throws {
        let app = launchOnAFixtureExpenseSheet()
        enterBackspaceAndClear(in: app)
    }

    @MainActor
    func testRapidEntryShowsTheLatestAmountWithReduceMotion() throws {
        try withReduceMotion {
            let app = launchOnAFixtureExpenseSheet()
            enterBackspaceAndClear(in: app)
        }
    }

    /// With Reduce Motion the press is a fade rather than a dip, and the buttons carrying it
    /// still have to answer the tap.
    @MainActor
    func testPressFeedbackStillActsWithReduceMotion() throws {
        try withReduceMotion {
            let app = launchOnAFixtureExpenseSheet()
            let next = app.buttons["expense.next"]

            tap("5", in: app)
            XCTAssertTrue(next.isHittable)
            next.tap()
            XCTAssertTrue(
                app.buttons["expense.split"].waitForExistence(timeout: 5),
                "Next should still move to the details step."
            )
        }
    }

    @MainActor
    func testSwipeReleaseSettlesWithReduceMotion() throws {
        try withReduceMotion {
            let app = launchScenarioApp()
            openFirstGroup(in: app)

            let row = app.otherElements["timeline.row"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            let resting = row.frame

            row.swipeLeft(velocity: .fast)

            let alert = app.alerts.firstMatch
            XCTAssertTrue(
                alert.waitForExistence(timeout: 5),
                "A committed swipe should still ask before deleting."
            )
            alert.buttons["Cancel"].tap()

            XCTAssertTrue(
                waitUntil { row.frame == resting },
                "The row should settle back to where it rests."
            )
        }
    }

    // MARK: - Scenario

    /// Ten digits into a nine-digit field, two deletions, a fraction, then the long-press
    /// clear, reading the amount after each burst.
    @MainActor
    private func enterBackspaceAndClear(in app: XCUIApplication) {
        let amount = app.descendants(matching: .any)["expense.amount"].firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(amount.label.hasPrefix("0"), "Got \(amount.label)")

        for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] {
            tap(key, in: app)
        }
        XCTAssertTrue(
            amount.label.hasPrefix("123456789") && !amount.label.hasPrefix("1234567890"),
            "Expected the nine digits the field holds, got \(amount.label)"
        )

        tap("chevron.left", in: app)
        tap("chevron.left", in: app)
        tap(".", in: app)
        tap("5", in: app)
        XCTAssertTrue(
            amount.label.hasPrefix("1234567.5"),
            "Expected the amount after backspace, got \(amount.label)"
        )

        app.buttons["keypad.key.chevron.left"].press(forDuration: 0.8)
        XCTAssertTrue(
            waitUntil { amount.label.hasPrefix("0") && !amount.label.hasPrefix("0.") },
            "A long press should clear the amount, got \(amount.label)"
        )
        XCTAssertFalse(app.buttons["expense.next"].isEnabled)
    }

    // MARK: - Helpers

    @MainActor
    private func withReduceMotion(_ body: () throws -> Void) throws {
        try enableReduceMotion(true)
        // A teardown block, not `defer`: a failed assertion stops the test before a `defer`
        // runs, and every test after it would inherit the setting.
        addTeardownBlock {
            try? self.enableReduceMotion(false)
        }
        try body()
    }

    @MainActor
    private func tap(_ key: String, in app: XCUIApplication) {
        app.buttons["keypad.key.\(key)"].tap()
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(50_000)
        }
        return condition()
    }

    @MainActor
    private func launchScenarioApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-SplittyPerformanceScenario")
        app.launch()
        return app
    }

    @MainActor
    private func openFirstGroup(in app: XCUIApplication) {
        let group = app.buttons["groups.card"].firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 10), "Expected the fixture groups.")
        group.tap()
        XCTAssertTrue(app.buttons["group.addExpense"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func launchOnAFixtureExpenseSheet() -> XCUIApplication {
        let app = launchScenarioApp()
        openFirstGroup(in: app)
        app.buttons["group.addExpense"].tap()
        XCTAssertTrue(app.buttons["keypad.key.5"].waitForExistence(timeout: 5))
        return app
    }
}
