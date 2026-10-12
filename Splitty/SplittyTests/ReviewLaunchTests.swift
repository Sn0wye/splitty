import Testing
@testable import Splitty

struct ReviewLaunchTests {
    @Test func withoutTheArgumentTheAppLaunchesNormally() {
        #expect(ReviewLaunch.parse(["Splitty"]) == nil)
        #expect(ReviewLaunch.parse(["Splitty", "-SplittyPerformanceScenario"]) == nil)
    }

    @Test func theArgumentAloneOpensTheGallery() {
        #expect(ReviewLaunch.parse(["Splitty", "-SplittyReview"]) == ReviewLaunch(screen: nil))
    }

    @Test func aScreenNameOpensThatScreen() {
        for screen in ReviewScreen.allCases {
            #expect(ReviewLaunch.parse(["Splitty", "-SplittyReview", screen.rawValue]) == ReviewLaunch(screen: screen))
        }
    }

    @Test func anUnknownScreenFallsBackToTheGallery() {
        #expect(ReviewLaunch.parse(["Splitty", "-SplittyReview", "odometer"]) == ReviewLaunch(screen: nil))
        #expect(ReviewLaunch.parse(["Splitty", "-SplittyReview", "-NSDoubleLocalizedStrings"]) == ReviewLaunch(screen: nil))
    }
}
