import SwiftUI

/// The circles use the same 1024-point proportions and 45-degree tilt as logo.svg.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var firstRing = 0.0
    @State private var secondRing = 0.0

    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            ZStack {
                ring(progress: firstRing)
                    .offset(x: -12)
                ring(progress: secondRing)
                    .offset(x: 12)
            }
            .rotationEffect(.degrees(45))
            .frame(width: 96, height: 96)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
        .task {
            if reduceMotion {
                firstRing = 1
                secondRing = 1
                try? await Task.sleep(for: .milliseconds(150))
            } else {
                // Give the empty launch frame time to render before drawing the paths.
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.7)) {
                    firstRing = 1
                }
                withAnimation(.easeOut(duration: 0.7).delay(0.12)) {
                    secondRing = 1
                }
                try? await Task.sleep(for: .milliseconds(900))
            }

            guard !Task.isCancelled else { return }
            onFinished()
        }
    }

    private func ring(progress: Double) -> some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255), lineWidth: 6)
            .frame(width: 48, height: 48)
    }
}

#Preview {
    SplashView(onFinished: {})
}
