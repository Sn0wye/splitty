//
//  ReduceMotionSetting.swift
//  SplittyUITests
//

import XCTest

extension XCTestCase {

    /// Flips the simulator's Reduce Motion switch through Settings, since there is no
    /// launch argument for it. Call it before launching the app under test: Settings takes
    /// the foreground while it runs.
    @MainActor
    func enableReduceMotion(_ enabled: Bool) throws {
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
