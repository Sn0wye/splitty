import XCTest

final class SplittyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchPerformance() throws {
        // The metric terminates the app between iterations. This is a cold process
        // launch: nothing in this test primed dyld or the app's file caches first.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testWarmLaunchPerformance() throws {
        // Prime once so the measured launches reuse warmed system and app caches.
        let app = XCUIApplication()
        app.launch()
        app.terminate()

        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
