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
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @GestureState private var translation: CGFloat = 0

    private static var actionWidth: CGFloat { 88 }
    /// Past this the row commits on release, the way a full swipe does in a system list.
    private static var commitWidth: CGFloat { 260 }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: Self.actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete")

            content
                .background(Color("card"))
                .offset(x: shownOffset)
        }
        .animation(.snappy(duration: 0.25), value: offset)
        .gesture(
            DragGesture(minimumDistance: 12)
                .updating($translation) { value, state, _ in
                    // Vertical intent belongs to the list, so only the horizontal part of a
                    // drag that is mostly horizontal is taken.
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                        return
                    }
                    state = value.translation.width
                }
                .onEnded(settle)
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

    private func settle(_ value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height) else { return }

        let travelled = offset + value.translation.width

        if travelled < -Self.commitWidth {
            offset = 0
            onDelete()
        } else {
            offset = travelled < -Self.actionWidth / 2 ? -Self.actionWidth : 0
        }
    }

    private func delete() {
        offset = 0
        onDelete()
    }
}
