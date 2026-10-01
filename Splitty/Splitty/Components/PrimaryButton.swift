//
//  PrimaryButton.swift
//  Splitty
//

import SwiftUI

/// The one commit on a screen, shaped like the system's own.
///
/// A full-width capsule rather than the small floating disc this replaces. A primary action
/// should be the most obvious thing on the screen and should say what it does — a 44pt
/// arrow parked in a corner was neither, and being small and floating is what let it end up
/// somewhere it did not belong.
///
/// Splitty Coral with white text. White on coral is 3.45:1, which the brand allows for large
/// text only, so the label is set bold at `title3` (20pt) rather than the system's 17pt.
struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    /// Read from the environment so `.disabled(_:)` applied by the caller styles the button
    /// as well as blocking it — a control that looks live and does nothing is worse than
    /// one that reads as unavailable.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.title3.weight(.bold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(
                Color("brand").opacity(isEnabled ? 1 : 0.35),
                in: Capsule()
            )
        }
        .buttonStyle(.pressable(scale: 0.97))
        .animation(.easeOut(duration: 0.2), value: isEnabled)
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(title: "Next") {}
        PrimaryButton(title: "Save") {}
            .disabled(true)
        PrimaryButton(title: "Save", isLoading: true) {}
    }
    .padding(20)
    .background(Color.expenseBackground)
}
