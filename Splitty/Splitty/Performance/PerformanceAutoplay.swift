import Darwin
import OSLog
import QuartzCore
import UIKit

/// A scripted, touch-free walk through the performance scenario, so a baseline and a
/// change can be compared without a person or a UI-automation driver in the loop.
///
/// UI automation reads the accessibility tree between gestures, and that read runs on
/// the app's main thread: in a trace it outweighs the app's own work. This drives the
/// screens the way a finger would instead, by moving the backing scroll view one display
/// frame at a time, and measures each phase from inside the process.
///
/// Launch with `-SplittyPerformanceScenario -SplittyPerformanceAutoplay`. Each phase is
/// also a Points of Interest interval named `Phase`, and
/// the run's results are logged and written to `Documents/performance-autoplay.json`.
@MainActor
enum PerformanceAutoplay {
    static var isEnabled: Bool {
        PerformanceScenarioLaunch.isEnabled
            && ProcessInfo.processInfo.arguments.contains("-SplittyPerformanceAutoplay")
    }

    private static let logger = Logger(subsystem: "com.snowye.Splitty", category: "PerformanceAutoplay")
    private static let signposter = OSSignposter(subsystem: "com.snowye.Splitty", category: .pointsOfInterest)
    private static var hasStarted = false

    /// Scroll speed of the scripted scrolls, in points per second: a brisk flick.
    private static let scrollSpeed: CGFloat = 3_000
    /// How far a scripted scroll travels at most before it turns back.
    private static let scrollDistance: CGFloat = 9_000

    static func start(appState: AppState) {
        guard isEnabled, !hasStarted else { return }
        hasStarted = true
        let launchMs = PerformanceClock.millisecondsSinceProcessStart()
        let launchCPU = PerformanceClock.mainThreadCPUMilliseconds()
        Task { @MainActor in
            var results: [PhaseResult] = [
                PhaseResult(name: "Launch", wallMs: launchMs, mainCPUMs: launchCPU, frames: 0, hitches: 0, hitchMs: 0)
            ]
            // Let the splash finish, the first avatars arrive, and a profiler attach.
            try? await Task.sleep(for: .seconds(6))

            await measure("GroupsScroll", into: &results) {
                await scrollTopmost(down: true)
                await scrollTopmost(down: false)
            }

            let group = PerformanceScenarios.groups[0]
            for round in 1...3 {
                await measure("OpenGroup\(round)", into: &results) {
                    appState.openGroup(group.id, seed: group)
                    try? await Task.sleep(for: .seconds(1.2))
                }
                if round == 1 {
                    await measure("TimelineScroll", into: &results) {
                        await scrollTopmost(down: true)
                        await scrollTopmost(down: false)
                    }
                }
                await measure("CloseGroup\(round)", into: &results) {
                    appState.showGroupList()
                    try? await Task.sleep(for: .seconds(1.0))
                }
            }

            report(results)
        }
    }

    // MARK: - Phases

    struct PhaseResult: Codable {
        let name: String
        let wallMs: Double
        let mainCPUMs: Double
        let frames: Int
        let hitches: Int
        /// Time past each late frame's deadline, summed: Apple's hitch time.
        let hitchMs: Double
    }

    @discardableResult
    private static func measure(
        _ name: String,
        into results: inout [PhaseResult],
        _ body: () async -> Void
    ) async -> PhaseResult {
        let monitor = FrameMonitor()
        let state = signposter.beginInterval("Phase", "\(name, privacy: .public)")
        let cpuStart = PerformanceClock.mainThreadCPUMilliseconds()
        let wallStart = CACurrentMediaTime()
        monitor.start()
        await body()
        monitor.stop()
        let result = PhaseResult(
            name: name,
            wallMs: (CACurrentMediaTime() - wallStart) * 1000,
            mainCPUMs: PerformanceClock.mainThreadCPUMilliseconds() - cpuStart,
            frames: monitor.frames,
            hitches: monitor.hitches,
            hitchMs: monitor.hitchMs
        )
        signposter.endInterval("Phase", state)
        results.append(result)
        return result
    }

    private static func report(_ results: [PhaseResult]) {
        for result in results {
            logger.notice(
                "phase=\(result.name, privacy: .public) wallMs=\(result.wallMs, format: .fixed(precision: 1)) mainCPUMs=\(result.mainCPUMs, format: .fixed(precision: 1)) frames=\(result.frames) hitches=\(result.hitches) hitchMs=\(result.hitchMs, format: .fixed(precision: 1))"
            )
        }
        logger.notice("autoplay finished")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(results),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        try? data.write(to: documents.appendingPathComponent("performance-autoplay.json"))
    }

    // MARK: - Scrolling

    /// Moves the front-most vertical scroll view toward its end (or back to its start) at a
    /// fixed speed, one display frame at a time, the way a dragging finger moves it.
    private static func scrollTopmost(down: Bool) async {
        guard let scrollView = frontmostScrollView() else {
            logger.error("no scroll view to drive")
            return
        }
        let top = -scrollView.adjustedContentInset.top
        let end = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        let bottom = max(top, min(end, top + scrollDistance))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let driver = ScrollDriver(scrollView: scrollView, speed: scrollSpeed, down: down, top: top, bottom: bottom) {
                continuation.resume()
            }
            driver.start()
        }
        try? await Task.sleep(for: .milliseconds(300))
    }

    private static func frontmostScrollView() -> UIScrollView? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard let window else { return nil }
        var best: (view: UIScrollView, area: CGFloat)?
        func visit(_ view: UIView) {
            if view.isHidden || view.alpha == 0 { return }
            if let scroll = view as? UIScrollView,
               scroll.contentSize.height > scroll.bounds.height + 1,
               scroll.window != nil {
                let frame = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
                let area = frame.isNull ? 0 : frame.width * frame.height
                if area > (best?.area ?? 0) { best = (scroll, area) }
            }
            view.subviews.forEach(visit)
        }
        visit(window)
        return best?.view
    }
}

/// Steps a scroll view's offset on every display frame until it reaches the end.
@MainActor
private final class ScrollDriver: NSObject {
    private let scrollView: UIScrollView
    private let speed: CGFloat
    private let down: Bool
    private let top: CGFloat
    private let bottom: CGFloat
    private let completion: () -> Void
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var retainSelf: ScrollDriver?

    init(scrollView: UIScrollView, speed: CGFloat, down: Bool, top: CGFloat, bottom: CGFloat, completion: @escaping () -> Void) {
        self.scrollView = scrollView
        self.speed = speed
        self.down = down
        self.top = top
        self.bottom = bottom
        self.completion = completion
    }

    func start() {
        retainSelf = self
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let lastTimestamp else { return }
        // Distance follows elapsed time, so a late frame jumps further, as under a finger.
        let delta = CGFloat(link.timestamp - lastTimestamp) * speed
        var y = scrollView.contentOffset.y + (down ? delta : -delta)
        let finished = down ? y >= bottom : y <= top
        y = min(max(y, top), bottom)
        scrollView.contentOffset.y = y
        if finished {
            link.invalidate()
            self.link = nil
            retainSelf = nil
            completion()
        }
    }
}

/// Counts frames and late frames while it runs.
@MainActor
private final class FrameMonitor: NSObject {
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private(set) var frames = 0
    private(set) var hitches = 0
    private(set) var hitchMs: Double = 0

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let lastTimestamp else { return }
        frames += 1
        let budget = link.targetTimestamp - link.timestamp
        let elapsed = link.timestamp - lastTimestamp
        if budget > 0, elapsed > budget * 1.5 {
            hitches += 1
            hitchMs += (elapsed - budget) * 1000
        }
    }
}

enum PerformanceClock {
    /// CPU time the main thread has used so far, user plus system.
    static func mainThreadCPUMilliseconds() -> Double {
        precondition(Thread.isMainThread)
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        let thread = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, thread) }
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return 0 }
        let user = Double(info.user_time.seconds) * 1000 + Double(info.user_time.microseconds) / 1000
        let system = Double(info.system_time.seconds) * 1000 + Double(info.system_time.microseconds) / 1000
        return user + system
    }

    /// Wall time since the kernel started this process.
    static func millisecondsSinceProcessStart() -> Double {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return 0 }
        let start = info.kp_proc.p_un.__p_starttime
        let startSeconds = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return (Date().timeIntervalSince1970 - startSeconds) * 1000
    }
}
