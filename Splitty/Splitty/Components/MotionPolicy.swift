//
//  MotionPolicy.swift
//  Splitty
//

import SwiftUI

/// What the app's custom motion becomes under Reduce Motion, in one place.
///
/// Feedback stays; travel goes. A press still answers the finger, but with a fade instead of
/// a dip, and a released swipe still settles from wherever the hand left it, but without
/// overshooting on the way home. Tracking under the finger is never touched: that motion is
/// the user's own.
struct MotionPolicy {
    let reduceMotion: Bool

    /// The deepest a press may fade to when it has no scale to carry it. Shallower fades
    /// read as nothing happening once the dip is gone.
    private static let reducedPressOpacity: Double = 0.6

    /// The bounce a released swipe comes home with — the momentum the throw put into it.
    private static let settleBounceAmount: Double = 0.25

    func pressScale(_ requested: CGFloat) -> CGFloat {
        reduceMotion ? 1 : requested
    }

    func pressedOpacity(_ requested: Double) -> Double {
        reduceMotion ? min(requested, Self.reducedPressOpacity) : requested
    }

    var settleBounce: Double {
        reduceMotion ? 0 : Self.settleBounceAmount
    }

    /// Equivalent to `.snappy(duration: 0.3, extraBounce: 0.1)` with motion on, and the same
    /// curve with the overshoot removed with it off.
    var settle: Animation {
        .spring(duration: 0.3, bounce: settleBounce)
    }
}
