//
//  SwipeToDeleteRow.swift
//  Splitty
//

import SwiftUI
import UIKit

/// A row that reveals a delete action when dragged left.
///
/// Not `.swipeActions`: the system draws its button as a rounded, inset shape, and these
/// rows are square and edge to edge. The gesture is the same one — drag to reveal, tap to
/// act, full swipe to act directly — so what changes is the shape, not the behaviour.
///
/// One row in a list rests open at a time. The list owns which one, through `openRow`,
/// and its scroll view closes it with `closesOpenSwipeRow(_:)`.
struct SwipeToDeleteRow<ID: Hashable, Content: View>: View {
    let id: ID
    /// The row that rests open in this list, if any. Any other value closes this row.
    @Binding var openRow: ID?
    let onTap: () -> Void
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    /// Where the row is drawn. Plain `@State`, not `@GestureState`: the gesture state
    /// resets itself the instant the drag ends, which took the row home in a single frame
    /// with nothing to animate. Owning the value means the release is ours to spring.
    @State private var dragOffset: CGFloat = 0
    /// Where the row sat when this drag took hold: home, or open. Nil while no drag holds
    /// the row, which is also what lets a close from elsewhere animate it.
    @State private var dragOrigin: CGFloat?
    @State private var isSwiping = false
    /// Bumped when the delete question is asked, from a full swipe or the button, so the
    /// haptic fires with the decision rather than with the alert that reports it. A row
    /// that only rests open has decided nothing.
    @State private var commitCount = 0
    @State private var rowWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var actionWidth: CGFloat { 88 }
    /// A release projected past 35pt (40% of the action) rests open; short of it the row
    /// snaps home. The old 44pt commit line sat close enough that a diagonal scroll crossed
    /// it; resting open is harmless, so the line can sit a little lower and still ignore
    /// the few points a vertical scroll drifts sideways.
    private static var openThreshold: CGFloat { actionWidth * 0.4 }
    /// A release projected past 60% of the row asks directly: 241pt on a 402pt iPhone row.
    /// Far enough past the open button that a swipe meant to reveal it does not delete,
    /// and it scales with the row on iPad. Never below twice the action, for a row not yet
    /// measured.
    private var fullSwipeWidth: CGFloat { max(rowWidth * 0.6, Self.actionWidth * 2) }

    var body: some View {
        // Read here, not in the tap: the scroll view's own tap may clear `openRow` first,
        // and the row has to know the list was open when the finger came down.
        let listHasOpenRow = openRow != nil

        ZStack(alignment: .trailing) {
            // Tied to the card's edge rather than parked at the row's: the button arrives
            // with the drag the way a system swipe action does, and stretches to fill
            // anything dragged past its width.
            Button(action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: Self.actionWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(Color.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Common.delete)
            .frame(width: max(Self.actionWidth, -shownOffset))
            .offset(x: max(0, Self.actionWidth + shownOffset))

            // A tap gesture the swipe can veto, rather than a `Button`: the row is the
            // button's whole area, so a finger that swipes never leaves it, and releasing
            // counted as a tap and opened the expense.
            content
                .background(Color("card"))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isSwiping else { return }
                    // While a row is open a tap closes it and does nothing else, as in Mail:
                    // the finger is dismissing the action, not choosing an expense.
                    guard !listHasOpenRow else {
                        openRow = nil
                        return
                    }
                    onTap()
                }
                .offset(x: shownOffset)
        }
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .transition(removal)
        .accessibilityIdentifier("timeline.row")
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: commitCount)
        // A UIKit pan rather than a `DragGesture`: the row's drag has to be able to decline
        // a touch. A `DragGesture` claimed every horizontal drag, so the navigation stack's
        // swipe back from the screen edge never started over a row. This one begins on a
        // leftward drag, or a rightward one that closes this row, and runs alongside the
        // scroll view's pan.
        .gesture(RowSwipeGesture(
            isOpen: dragOffset < 0,
            onBegan: {
                isSwiping = true
                dragOrigin = dragOffset
                // Taking this row closes whichever other row is open.
                openRow = id
            },
            // No animation here on purpose: while the finger is down the row is glued to
            // it, and the only motion is the one the hand is making.
            onChanged: { dragOffset = (dragOrigin ?? 0) + $0 },
            onEnded: { predictedTranslation in
                settle(predictedTranslation: predictedTranslation)
                // Cleared late: the tap lands on the same release as the drag's end.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    isSwiping = false
                }
            }
        ))
        // Another row taken, a tap elsewhere, or a scroll: home without bounce, since
        // nothing was thrown. A row under the finger is left to its own release.
        .onChange(of: openRow) { _, newValue in
            guard newValue != id, dragOrigin == nil, dragOffset != 0 else { return }
            withAnimation(closeAnimation) {
                dragOffset = 0
            }
        }
        // A row that leaves the screen open would come back closed and leave the list
        // thinking one is open, which would swallow the next tap.
        .onDisappear {
            if openRow == id { openRow = nil }
        }
    }

    /// Follows the finger one to one to the left, so a full swipe looks as far as it is,
    /// and never drags right of its resting place.
    private var shownOffset: CGFloat {
        min(0, dragOffset)
    }

    /// Three outcomes, decided on where the release is *going*, not on where the finger
    /// happened to stop: the predicted translation carries the release velocity, so a
    /// fast flick projects past the full-swipe line even when the finger travelled a
    /// little, and needs no velocity check of its own. Judging on final position alone
    /// meant a short fast swipe did nothing at all.
    ///
    /// - Past `fullSwipeWidth`: asks the question and goes home.
    /// - Past `openThreshold`: rests open with the button under the finger's reach.
    /// - Otherwise home, as if nothing happened.
    private func settle(predictedTranslation: CGFloat) {
        guard let origin = dragOrigin else { return }
        dragOrigin = nil

        let projected = origin + predictedTranslation
        let release = PerformanceSignpost.begin(.swipeRelease)

        let committed = projected < -fullSwipeWidth
        let rests = !committed && projected < -Self.openThreshold

        // Bounce, and only on a release: the row is landing off a throw, and the overshoot
        // is the momentum the hand put into it. A close from elsewhere has none.
        withAnimation(releaseAnimation) {
            dragOffset = rests ? -Self.actionWidth : 0
        } completion: {
            PerformanceSignpost.end(.swipeRelease, release)
        }

        if rests {
            openRow = id
        } else if openRow == id {
            openRow = nil
        }

        if committed {
            commitCount += 1
            onDelete()
        }
    }

    /// A deleted row leaves the way the swipe was sending it. Removal only: a row that
    /// arrives, or comes back after a failed delete, has no swipe to continue. Reduce
    /// Motion fades it instead.
    private var removal: AnyTransition {
        .asymmetric(
            insertion: .identity,
            removal: reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity)
        )
    }

    /// Reduce Motion keeps the row landing, without the overshoot.
    private var releaseAnimation: Animation {
        reduceMotion ? .snappy(duration: 0.3) : .snappy(duration: 0.3, extraBounce: 0.1)
    }

    private var closeAnimation: Animation {
        .snappy(duration: 0.3)
    }

    /// The button on a rested row: closes it without bounce, since no hand threw it, and
    /// asks.
    private func delete() {
        withAnimation(closeAnimation) {
            dragOffset = 0
        }
        if openRow == id { openRow = nil }
        commitCount += 1
        onDelete()
    }
}

extension View {
    /// Closes the list's open swipe row on any tap or when the list starts scrolling.
    ///
    /// The tap is simultaneous so buttons, rows and links under it still act; a row tapped
    /// while another is open reads the open state itself and only closes it.
    func closesOpenSwipeRow<ID: Hashable>(_ openRow: Binding<ID?>) -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                if openRow.wrappedValue != nil { openRow.wrappedValue = nil }
            }
        )
        .onScrollPhaseChange { _, phase in
            if phase == .interacting, openRow.wrappedValue != nil {
                openRow.wrappedValue = nil
            }
        }
    }
}

/// The row's drag. Begins only when the finger moves more sideways than vertically, and
/// leftward unless the row is open, so a scroll stays a scroll and a rightward drag over a
/// closed row goes to the navigation stack's swipe back. The direction is decided once, as
/// the pan begins, and held for the rest of the drag: re-deciding every frame let a
/// curving finger hand the row back to the list mid-swipe.
private struct RowSwipeGesture: UIGestureRecognizerRepresentable {
    /// Rested open, so a rightward drag closes it.
    let isOpen: Bool
    let onBegan: () -> Void
    let onChanged: (_ translation: CGFloat) -> Void
    /// The release, with the translation the flick would carry it to.
    let onEnded: (_ predictedTranslation: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isOpen = isOpen
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began:
            onBegan()
            onChanged(translation)
        case .changed:
            onChanged(translation)
        case .ended, .cancelled:
            onEnded(translation + Self.projection(of: recognizer.velocity(in: recognizer.view).x))
        default:
            break
        }
    }

    /// How far a flick at this velocity travels as it decelerates, at the scroll view's
    /// normal rate: what a `DragGesture` adds for its predicted end translation.
    private static func projection(of velocity: CGFloat) -> CGFloat {
        let rate = UIScrollView.DecelerationRate.normal.rawValue
        return velocity / 1000 * rate / (1 - rate)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isOpen = false

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            guard abs(velocity.x) > abs(velocity.y) else { return false }
            return velocity.x < 0 || isOpen
        }

        /// Alongside the scroll view's pan, as the `DragGesture` was: excluding it lost the
        /// drag to the scroll view and the row stopped swiping at all.
        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}
