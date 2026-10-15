import SwiftUI

/// Picks up from the launch screen: one coin on the brand ground, cut and slid apart into
/// the mark. The ground and the symbol follow the app icon — white on coral in light, coral
/// on ink in dark.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var separation: CGFloat = 0
    @State private var scale: CGFloat = 0.86

    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            // The reversed cut: a light mark on a coloured ground reads heavier.
            SplittySymbol(separation: separation, cut: .reversed)
                .foregroundStyle(Color("LaunchSymbol"))
                .frame(width: 112, height: 112)
                .scaleEffect(scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
        // Touches go to the content underneath while the splash fades out.
        .allowsHitTesting(false)
        .task {
            if reduceMotion {
                separation = 1
                scale = 1
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                onFinished()
                return
            }

            // Give the launch frame time to render before the coin moves.
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                scale = 1
            }
            // Hand off once the cut has visibly landed, not after a fixed wait.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.68).delay(0.1)) {
                separation = 1
            } completion: {
                onFinished()
            }
        }
    }
}

#Preview {
    SplashView(onFinished: {})
}
