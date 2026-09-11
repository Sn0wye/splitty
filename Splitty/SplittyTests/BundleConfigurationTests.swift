import Foundation
import Testing
@testable import Splitty

struct BundleConfigurationTests {

    // ProMotion is opt-in on iPhone. Without this key the system caps the app at 60 Hz
    // even on a 120 Hz display. The test host is the app, so `.main` is the built product.
    @Test func theAppBundleOptsIntoUnrestrictedRefreshRatesOnIPhone() {
        let value = Bundle.main.object(
            forInfoDictionaryKey: "CADisableMinimumFrameDurationOnPhone"
        ) as? Bool
        #expect(value == true)
    }
}
