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
///
/// The halves arrive on a lively spring but stop dead where they meet instead of sliding
/// past each other. The impact goes into the whole coin as one springy wobble, with the
/// success haptic at contact. `fromBrand` starts the halves coral and lets them turn green
/// as they close, for the full-screen moment; inline the coin is green throughout.
struct SettledCoin: View {
    var size: CGFloat = 28
    var fromBrand = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var separation: CGFloat = 1
    @State private var closing = false
    @State private var wobble: Double = 0
    @State private var contact = false

    var body: some View {
        SplittySymbol(separation: separation)
            .foregroundStyle(Color(fromBrand && !closing ? "brand" : "positive"))
            .modifier(SettledCoinWobble(elapsed: wobble))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .sensoryFeedback(.success, trigger: contact)
            .task {
                guard !contact else { return }
                if reduceMotion {
                    closing = true
                    separation = 0
                    contact = true
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.4)) { closing = true }
                withAnimation(Animation(SettledCoinSeat()), completionCriteria: .removed) {
                    separation = 0
                } completion: {
                    contact = true
                    withAnimation(.linear(duration: SettledCoinMotion.wobbleDuration)) {
                        wobble = SettledCoinMotion.wobbleDuration
                    }
                }
            }
    }
}

/// The settled coin's curves, the ones the landing page's `Coin.close` and `wobble` borrow.
enum SettledCoinMotion {
    /// Halves meeting. Livelier than the loader's join, because they stop at contact
    /// instead of letting the overshoot carry them through.
    static let close = Spring(response: closeResponse, dampingRatio: closeDamping)
    private static let closeResponse = 0.5
    private static let closeDamping = 0.55
    /// The whole coin taking the impact: kicked with a velocity, scale 1 to 1.
    static let wobble = Spring(response: 0.42, dampingRatio: 0.42)
    static let wobbleVelocity = 1.2
    static let wobbleDuration: TimeInterval = 1

    /// When the halves first meet: an underdamped step response first reaches its target
    /// at (π − acos ζ) / ω_d.
    static let contactTime: TimeInterval = {
        let naturalFrequency = 2 * Double.pi / closeResponse
        let dampedFrequency = naturalFrequency * (1 - closeDamping * closeDamping).squareRoot()
        return (Double.pi - acos(closeDamping)) / dampedFrequency
    }()

    /// The fraction of the way the halves have travelled, or nil once they have met.
    static func closeProgress(at time: TimeInterval) -> Double? {
        guard time < contactTime else { return nil }
        return min(close.value(target: 1.0, time: time), 1)
    }

    /// The coin's scale `time` seconds after contact.
    static func wobbleScale(at time: TimeInterval) -> Double {
        guard time < wobbleDuration else { return 1 }
        return 1 + wobble.value(fromValue: 0.0, toValue: 0.0, initialVelocity: wobbleVelocity, time: time)
    }
}

/// `SettledCoinMotion.close`, ending the first time it reaches its target.
private struct SettledCoinSeat: CustomAnimation {
    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        SettledCoinMotion.closeProgress(at: time).map { value.scaled(by: $0) }
    }
}

/// Scales by the wobble at `elapsed` seconds after contact. A spring from scale 1 to 1
/// has nothing to animate, so time is what animates and the curve is read from it.
private struct SettledCoinWobble: ViewModifier, Animatable {
    var elapsed: Double

    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    func body(content: Content) -> some View {
        content.scaleEffect(SettledCoinMotion.wobbleScale(at: elapsed))
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
