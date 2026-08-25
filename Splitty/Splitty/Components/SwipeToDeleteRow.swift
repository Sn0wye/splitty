//
//  SwipeToDeleteRow.swift
//  Splitty
//

import SwiftUI

/// A row that reveals a delete action when dragged left.
///
/// Not `.swipeActions`: the system draws its button as a rounded, inset shape, and these
/// rows are square and edge to edge. The gesture is the same one — drag to reveal, tap to
/// act, full swipe to act directly — so what changes is the shape, not the behaviour.
struct SwipeToDeleteRow<Content: View>: View {
    let onTap: () -> Void
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    /// Where the finger has the row. Plain `@State`, not `@GestureState`: the gesture state
    /// resets itself the instant the drag ends, which took the row home in a single frame
    /// with nothing to animate. Owning the value means the release is ours to spring.
    @State private var dragOffset: CGFloat = 0
    @State private var isSwiping = false
    /// Bumped when a release commits, so the haptic fires with the decision rather than
    /// with the alert that reports it.
    @State private var commitCount = 0

    private static var actionWidth: CGFloat { 88 }
    /// Past this, releasing asks. Short of it the row snaps back and nothing happens.
    private static var commitWidth: CGFloat { 44 }

    var body: some View {
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
            .accessibilityLabel("Delete")
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
                    onTap()
                }
                .offset(x: shownOffset)
        }
        .clipped()
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: commitCount)
        // Simultaneous, not exclusive: a plain `.gesture` loses the drag to the list's own
        // pan recogniser, which is why the row stopped swiping at all. Both see the drag,
        // and the horizontal-dominance check below is what keeps a scroll a scroll.
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onChanged { value in
                    // Direction is decided once, on the first move past the threshold, and
                    // then held for the rest of the drag. Re-deciding every frame let a
                    // curving finger hand the row back to the list mid-swipe.
                    if !isSwiping {
                        guard abs(value.translation.width) > abs(value.translation.height) else {
                            return
                        }
                        isSwiping = true
                    }
                    // No animation here on purpose: while the finger is down the row is
                    // glued to it, and the only motion is the one the hand is making.
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    settle(value)
                    // Cleared late: the tap lands on the same release as the drag's end.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        isSwiping = false
                    }
                }
        )
    }

    /// Clamped: the row opens to the action's width and resists past it, and never drags
    /// right of its resting place.
    private var shownOffset: CGFloat {
        let raw = dragOffset
        if raw > 0 { return 0 }
        return raw < -Self.actionWidth
            ? -Self.actionWidth + (raw + Self.actionWidth) / 3
            : raw
    }

    /// The row does not stay open. Releasing past the threshold asks the question and
    /// closes; the drag is the gesture, and the alert is where the decision is made.
    ///
    /// The threshold is applied to where the flick is *going*, not to where the finger
    /// happened to stop. A fast short swipe is a swipe — judging it on final position alone
    /// meant a flick that never travelled 44pt did nothing at all.
    private func settle(_ value: DragGesture.Value) {
        guard isSwiping else { return }

        let projected = value.predictedEndTranslation.width
        let committed = projected < -Self.commitWidth

        // Bounce, and only here: the row is coming home off a throw, and the overshoot is
        // the momentum the hand put into it. Nothing else in the row animates with bounce.
        withAnimation(.snappy(duration: 0.3, extraBounce: 0.1)) {
            dragOffset = 0
        }

        if committed {
            commitCount += 1
            onDelete()
        }
    }

    private func delete() {
        withAnimation(.snappy(duration: 0.3, extraBounce: 0.1)) {
            dragOffset = 0
        }
        commitCount += 1
        onDelete()
    }
}
