//
//  BrandMark.swift
//  Splitty
//

import SwiftUI

/// The Splitty symbol: one coin cut into two equal halves and slid apart.
///
/// Drawn rather than bundled so it can move. `separation` runs from 0, the whole coin, to 1,
/// the mark as the brand kit draws it; everything between is the halves sliding along the
/// cut. Static logos come from the asset catalog (`Logo`, `Lockup`), which are the masters
/// themselves — this exists for the moments the halves have to travel.
struct SplittySymbol: Shape {
    enum Cut {
        /// The master: radius 68 and a 16-unit gap on the 256 grid.
        case regular
        /// For light shapes on dark or coral grounds, which read heavier: radius 67, gap 18.
        case reversed

        fileprivate var radius: CGFloat { self == .regular ? 68 : 67 }
        fileprivate var halfGap: CGFloat { self == .regular ? 8 : 9 }
    }

    var separation: CGFloat = 1
    var cut: Cut = .regular

    var animatableData: CGFloat {
        get { separation }
        set { separation = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let unit = side / 256
        let origin = CGPoint(x: rect.midX, y: rect.midY)
        let radius = cut.radius * unit
        // Each half sits 40 units off centre vertically and half the gap horizontally.
        let dx = cut.halfGap * unit * separation
        let dy = 40 * unit * separation

        var path = Path()
        // Angles grow clockwise on screen, so 90°→270° is the left half and -90°→90° the right.
        path.addArc(
            center: CGPoint(x: origin.x - dx, y: origin.y - dy),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        path.addArc(
            center: CGPoint(x: origin.x + dx, y: origin.y + dy),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// The brand's loading motion: the halves slide together and apart again.
struct SplittyLoader: View {
    var size: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwiftUI.Group {
            if reduceMotion {
                SplittySymbol()
                    .phaseAnimator([1.0, 0.45]) { content, opacity in
                        content.opacity(opacity)
                    } animation: { _ in .easeInOut(duration: 0.8) }
            } else {
                PhaseAnimator([1.0, 0.0]) { separation in
                    SplittySymbol(separation: separation)
                } animation: { separation in
                    separation == 0
                        ? .spring(response: 0.45, dampingFraction: 0.8)
                        : .spring(response: 0.5, dampingFraction: 0.62).delay(0.12)
                }
            }
        }
        .foregroundStyle(Color("brand"))
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(Text(L10n.Common.loading))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Everyone is square: the halves come back together into one coin.
struct SettledCoin: View {
    var size: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var separation: CGFloat = 1

    var body: some View {
        SplittySymbol(separation: separation)
            .foregroundStyle(Color("positive"))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .sensoryFeedback(.success, trigger: separation == 0)
            .task {
                guard separation != 0 else { return }
                if reduceMotion {
                    separation = 0
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    separation = 0
                }
            }
    }
}

/// An SF Symbol on a soft coral disc — the one place a screen with nothing in it gets
/// colour, so an empty state reads as an invitation rather than an error.
struct BrandBadge: View {
    let symbol: String
    var size: CGFloat = 64

    var body: some View {
        // The glyph takes the accent, not the fill: coral on its own 12% tint is 2.7:1 in
        // light, under the 3:1 an icon needs. Coral Deep there is 4:1; dark keeps coral.
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(Color("brand").opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 32) {
        HStack(spacing: 24) {
            SplittySymbol(separation: 0).frame(width: 64, height: 64)
            SplittySymbol(separation: 0.5).frame(width: 64, height: 64)
            SplittySymbol().frame(width: 64, height: 64)
        }
        .foregroundStyle(Color("brand"))
        SplittyLoader()
        SettledCoin()
        BrandBadge(symbol: "receipt")
        Image("Lockup").resizable().scaledToFit().frame(height: 64)
    }
    .padding()
}
