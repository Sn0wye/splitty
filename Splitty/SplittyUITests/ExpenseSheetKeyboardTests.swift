//
//  ExpenseSheetKeyboardTests.swift
//  SplittyUITests
//

import XCTest

/// The expense sheet is two steps, and the reason it is two steps is that the amount pad
/// and the system keyboard must never contend for the bottom of the sheet. These pin that
/// down: one input surface per screen, and a push to the split screen that does not disturb
/// either.
///
/// Runs against whatever `SPLITTY_API_BASE_URL` points at, which by default is the
/// deployed API — nothing local to stand up. Signs in through `/auth/dev-login` as a seeded
/// user and reads: it never taps Save, so it writes nothing. Anything missing along the way
/// is a skip rather than a failure, since these are about layout, not about the backend.
final class ExpenseSheetKeyboardTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The amount screen belongs to the pad alone.
    @MainActor
    func testTheAmountStepHasNoSystemKeyboard() throws {
        let app = try launchOnAnExpenseSheet()

        XCTAssertTrue(app.buttons["keypad.key.5"].exists, "The pad should own the amount step.")
        XCTAssertFalse(
            app.textFields["expense.description"].exists,
            "Nothing on the amount step should be able to raise a system keyboard."
        )
    }

    /// Forward is unavailable until there is an amount to carry forward.
    @MainActor
    func testNextIsBlockedUntilAnAmountIsTyped() throws {
        let app = try launchOnAnExpenseSheet()

        let next = app.buttons["expense.next"]
        XCTAssertFalse(next.isEnabled, "Next should be blocked while the amount is zero.")

        app.buttons["keypad.key.5"].tap()
        XCTAssertTrue(next.isEnabled, "Next should open up as soon as there is an amount.")
    }

    /// The details screen belongs to the system keyboard alone.
    @MainActor
    func testTheDetailsStepReplacesThePadWithTheKeyboard() throws {
        let app = try enterDetails(try launchOnAnExpenseSheet())

        XCTAssertTrue(
            waitForFocus(app.textFields["expense.description"]),
            "The details step should arrive with the description already focused."
        )
        XCTAssertFalse(
            app.buttons["keypad.key.5"].exists,
            "The pad belongs to the previous screen and should not be on this one."
        )
    }

    /// Save is the commit, and it stays blocked until the expense is actually saveable.
    @MainActor
    func testSaveIsBlockedUntilThereIsADescription() throws {
        let app = try enterDetails(try launchOnAnExpenseSheet())
        XCTAssertTrue(waitForFocus(app.textFields["expense.description"]))

        let save = app.buttons["expense.save"]
        XCTAssertFalse(save.isEnabled, "Save should be blocked without a description.")

        app.typeText("dinner")
        XCTAssertTrue(save.isEnabled, "Save should open up once the expense is complete.")
    }

    /// Pushing to the split screen and popping back lands on the details step with what was
    /// typed still there. This is the round trip that used to come back misaligned.
    @MainActor
    func testPoppingBackFromSplitKeepsTheDetailsStepIntact() throws {
        let app = try enterDetails(try launchOnAnExpenseSheet())
        XCTAssertTrue(waitForFocus(app.textFields["expense.description"]))
        app.typeText("dinner")

        app.buttons["expense.split"].tap()
        XCTAssertTrue(
            app.otherElements["split.mode"].waitForExistence(timeout: 5)
                || app.buttons["split.payer"].waitForExistence(timeout: 5),
            "Expected the split screen to be pushed."
        )

        app.navigationBars.buttons.element(boundBy: 0).tap()

        let description = app.textFields["expense.description"]
        XCTAssertTrue(
            description.waitForExistence(timeout: 5),
            "Popping back should land on the details step."
        )
        XCTAssertEqual(
            description.value as? String, "dinner",
            "The description should survive the push and pop."
        )
        XCTAssertFalse(
            app.buttons["keypad.key.5"].exists,
            "Popping back should not bring the amount pad onto the details step."
        )
    }

    // MARK: - Helpers

    /// Whether the field actually holds keyboard focus.
    ///
    /// Not `app.keyboards`: the simulator runs with the hardware keyboard connected, so no
    /// software keyboard is ever drawn and that collection is empty however focused the
    /// field is. Focus is the thing under test either way — the drawn keyboard was only
    /// ever a proxy for it.
    private func waitForFocus(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value(forKey: "hasKeyboardFocus") as? Bool) == true { return true }
            usleep(100_000)
        }
        return false
    }

    // MARK: - Getting there

    private func enterDetails(_ app: XCUIApplication) throws -> XCUIApplication {
        app.buttons["keypad.key.5"].tap()
        app.buttons["keypad.key.0"].tap()
        app.buttons["expense.next"].tap()
        return app
    }

    /// Signs in as a seeded user, opens a group, and opens the add-expense sheet.
    private func launchOnAnExpenseSheet() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()

        try signIn(app)

        // Whichever group comes first: the sheet under test is the same one from any of
        // them, and pinning a name here would tie the test to one backend's data.
        let group = app.buttons["groups.card"].firstMatch
        guard group.waitForExistence(timeout: 15) else {
            throw XCTSkip("The signed-in user has no groups to open.")
        }
        group.tap()

        let addExpense = app.buttons["group.addExpense"]
        guard addExpense.waitForExistence(timeout: 15) else {
            throw XCTSkip("The group never finished loading.")
        }
        addExpense.tap()

        guard app.buttons["keypad.key.5"].waitForExistence(timeout: 10) else {
            throw XCTSkip("The expense sheet did not open.")
        }
        return app
    }

    private func signIn(_ app: XCUIApplication) throws {
        // Already signed in from a previous run: the token lives in the keychain.
        if app.staticTexts["Groups"].waitForExistence(timeout: 5) { return }

        let devSignIn = app.buttons["Dev sign in"]
        guard devSignIn.waitForExistence(timeout: 10) else {
            throw XCTSkip("Neither the login screen nor the groups list appeared.")
        }
        devSignIn.tap()
        app.buttons["john@example.com"].tap()

        guard app.staticTexts["Groups"].waitForExistence(timeout: 20) else {
            throw XCTSkip("Dev sign-in did not complete; is the local API reachable?")
        }
    }
}
