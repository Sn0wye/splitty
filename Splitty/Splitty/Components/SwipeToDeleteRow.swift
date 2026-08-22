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

    @State private var offset: CGFloat = 0
    @State private var isSwiping = false
    @GestureState private var translation: CGFloat = 0

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
        .animation(.snappy(duration: 0.25), value: offset)
        // Simultaneous, not exclusive: a plain `.gesture` loses the drag to the list's own
        // pan recogniser, which is why the row stopped swiping at all. Both see the drag,
        // and the horizontal-dominance check below is what keeps a scroll a scroll.
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .updating($translation) { value, state, _ in
                    // Vertical intent belongs to the list, so only the horizontal part of a
                    // drag that is mostly horizontal is taken.
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                        return
                    }
                    state = value.translation.width
                }
                .onChanged { value in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        isSwiping = true
                    }
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
        let raw = offset + translation
        if raw > 0 { return 0 }
        return raw < -Self.actionWidth
            ? -Self.actionWidth + (raw + Self.actionWidth) / 3
            : raw
    }

    /// The row does not stay open. Releasing past the threshold asks the question and
    /// closes; the drag is the gesture, and the alert is where the decision is made.
    private func settle(_ value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height) else { return }

        let travelled = offset + value.translation.width
        offset = 0

        if travelled < -Self.commitWidth {
            onDelete()
        }
    }

    private func delete() {
        offset = 0
        onDelete()
    }
}
