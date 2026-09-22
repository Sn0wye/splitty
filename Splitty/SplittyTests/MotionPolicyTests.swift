import SwiftUI
import Testing
@testable import Splitty

struct MotionPolicyTests {

    private let standard = MotionPolicy(reduceMotion: false)
    private let reduced = MotionPolicy(reduceMotion: true)

    @Test func pressKeepsTheRequestedScaleByDefault() {
        #expect(standard.pressScale(0.94) == 0.94)
        #expect(standard.pressedOpacity(0.9) == 0.9)
    }

    /// Reduce Motion trades the dip for a fade: no scale, and an opacity change deep enough
    /// to carry the press on its own.
    @Test func reduceMotionPressesWithOpacityRatherThanScale() {
        #expect(reduced.pressScale(0.94) == 1)
        #expect(reduced.pressedOpacity(0.9) < 0.9)
        #expect(reduced.pressedOpacity(0.5) == 0.5)
    }

    @Test func swipeSettlesWithBounceByDefault() {
        #expect(standard.settleBounce > 0)
    }

    @Test func reduceMotionSettlesSwipesWithoutBounce() {
        #expect(reduced.settleBounce == 0)
    }
}
