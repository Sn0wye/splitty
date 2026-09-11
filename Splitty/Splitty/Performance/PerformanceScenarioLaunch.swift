import OSLog
import UIKit

/// Launch-argument hook so Instruments can load the deterministic baseline data
/// without a backend. Not a refresh-rate request.
enum PerformanceScenarioLaunch {
    private static let logger = Logger(
        subsystem: "com.snowye.Splitty",
        category: "PerformanceBaseline"
    )

    static var isEnabled: Bool {
        enabled(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    static func enabled(arguments: [String], environment: [String: String]) -> Bool {
        arguments.contains("-SplittyPerformanceScenario")
            || environment["SPLITTY_PERFORMANCE_SCENARIO"] == "1"
    }

    static func logDeviceConditions() {
        guard isEnabled else { return }

        let thermal = switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
        logger.notice(
            "baseline thermal=\(thermal, privacy: .public) lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled) reduceMotion=\(UIAccessibility.isReduceMotionEnabled)"
        )
    }
}
