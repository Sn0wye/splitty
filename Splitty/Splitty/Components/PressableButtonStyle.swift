//
//  PressableButtonStyle.swift
//  Splitty
//

import SwiftUI

/// The app's press feedback, in one place.
///
/// `.plain` draws a button with no state at all, so a card, a pill and the add button all
/// sat inert until the finger lifted and the screen changed. Feedback belongs on the press,
/// not on the release: the label dips the moment it is touched and comes back slower than
/// it went down, which is what reads as a physical thing being pushed.
///
/// Smaller controls take a deeper dip — a 4% scale on a 56pt disc is a few points of travel
/// and barely registers, while the same 4% across a full-width card is plenty.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var pressedOpacity: Double = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            // In fast, out slow: the press should feel instant and the release should feel
            // like the control settling back rather than snapping.
            .animation(
                .easeOut(duration: configuration.isPressed ? 0.1 : 0.2),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }

    static func pressable(scale: CGFloat) -> PressableButtonStyle {
        PressableButtonStyle(scale: scale)
    }
}
