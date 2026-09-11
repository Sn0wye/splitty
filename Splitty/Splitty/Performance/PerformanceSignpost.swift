import OSLog
import SwiftUI

/// Stable Instruments interval names for the ProMotion baseline scenarios.
///
/// 120 Hz is a system choice. These markers bound the work the app does; they do not
/// request a refresh rate.
enum PerformanceSignpost {
    enum Interval: String {
        case launch = "Launch"
        case groupsScroll = "GroupsScroll"
        case timelineScroll = "TimelineScroll"
        case amountEntry = "AmountEntry"
        case swipeRelease = "SwipeRelease"
        case splitEdit = "SplitEdit"

        /// `OSSignposter` requires a `StaticString`. Keep the literal next to the case
        /// it names so begin/end cannot drift apart.
        var signpostName: StaticString {
            switch self {
            case .launch: "Launch"
            case .groupsScroll: "GroupsScroll"
            case .timelineScroll: "TimelineScroll"
            case .amountEntry: "AmountEntry"
            case .swipeRelease: "SwipeRelease"
            case .splitEdit: "SplitEdit"
            }
        }
    }

    private static let signposter = OSSignposter(
        subsystem: "com.snowye.Splitty",
        category: "PointsOfInterest"
    )

    static func begin(_ interval: Interval) -> OSSignpostIntervalState {
        signposter.beginInterval(interval.signpostName)
    }

    static func end(_ interval: Interval, _ state: OSSignpostIntervalState) {
        signposter.endInterval(interval.signpostName, state)
    }

    /// Ends after the current main-queue turn so SwiftUI can commit the mutation.
    static func around<T>(_ interval: Interval, perform: () throws -> T) rethrows -> T {
        let state = begin(interval)
        let value = try perform()
        DispatchQueue.main.async {
            end(interval, state)
        }
        return value
    }

    @MainActor private static var launchState: OSSignpostIntervalState?

    @MainActor
    static func beginLaunch() {
        guard launchState == nil else { return }
        launchState = begin(.launch)
    }

    @MainActor
    static func endLaunch() {
        guard let launchState else { return }
        end(.launch, launchState)
        self.launchState = nil
    }
}

extension View {
    /// Bounds a scroll from the first non-idle phase until the view is idle again.
    func performanceScrollSignpost(_ interval: PerformanceSignpost.Interval) -> some View {
        modifier(ScrollSignpostModifier(interval: interval))
    }
}

private struct ScrollSignpostModifier: ViewModifier {
    let interval: PerformanceSignpost.Interval
    @State private var state: OSSignpostIntervalState?

    func body(content: Content) -> some View {
        content.onScrollPhaseChange { oldPhase, newPhase in
            if oldPhase == .idle, newPhase != .idle {
                state = PerformanceSignpost.begin(interval)
            } else if newPhase == .idle, let state {
                PerformanceSignpost.end(interval, state)
                self.state = nil
            }
        }
    }
}
