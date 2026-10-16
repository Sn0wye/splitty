import Foundation
import MetricKit

/// Sends crashes, hangs and non-fatal API failures to `POST /client-reports`, which logs them
/// to Seq. The app never holds a Seq key: anything shipped in the binary can be lifted.
///
/// Release builds only. Reports go out anonymously, so the privacy manifest can declare crash
/// and diagnostic data as not linked to the user.
actor ClientReporter {
    static let shared = ClientReporter()

    enum Kind: String, Codable {
        case crash, hang, error
    }

    struct Report: Codable {
        let kind: Kind
        let appVersion: String
        let build: String
        let osVersion: String
        let deviceModel: String
        let message: String
        let payload: String?
    }

    /// Reports wait here until the API accepts them. MetricKit hands each diagnostic over once,
    /// and the launch after a crash may have no connection.
    private let queue = URL.applicationSupportDirectory.appending(path: "ClientReports", directoryHint: .isDirectory)
    /// Non-fatal failures already reported this session, so a failing screen that retries
    /// does not send the same report every time.
    private var reported: Set<String> = []
    private var flushing = false

    static let endpoint = "/client-reports"

    /// Subscribes to MetricKit and retries what an earlier launch could not send.
    nonisolated static func start() {
        #if !DEBUG
        MXMetricManager.shared.add(MetricKitSubscriber.shared)
        Task { await shared.flush() }
        #endif
    }

    /// A 5xx, or a response this build cannot decode, which is how a contract drift between
    /// the API and the app shows up. Once per endpoint and failure per session.
    nonisolated static func reportFailure(endpoint: String, _ message: String) {
        #if !DEBUG
        // The reporter's own request failing must not report itself.
        guard endpoint != Self.endpoint else { return }
        Task { await shared.reportFailure(endpoint: endpoint, message) }
        #endif
    }

    private func reportFailure(endpoint: String, _ message: String) async {
        // `/group/12` and `/group/13` are the same failure.
        let route = endpoint.replacing(/\d+/, with: "{id}")
        guard reported.insert("\(route) \(message)").inserted else { return }
        await enqueue(.current(kind: .error, message: "\(route): \(message)", payload: nil))
    }

    fileprivate func enqueue(_ report: Report) async {
        try? FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true)
        try? JSONEncoder().encode(report).write(to: queue.appending(path: "\(UUID().uuidString).json"))
        await flush()
    }

    private func flush() async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }

        let files = (try? FileManager.default.contentsOfDirectory(at: queue, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                try? FileManager.default.removeItem(at: file)
                continue
            }

            do {
                let _: EmptyResponse = try await APIClient.shared.request(
                    endpoint: Self.endpoint,
                    method: .POST,
                    body: body,
                    requiresAuth: false
                )
                try? FileManager.default.removeItem(at: file)
            } catch APIError.httpError(let status, _) where (400..<500).contains(status) && status != 429 {
                // Refused as invalid: sending it again cannot change the answer.
                try? FileManager.default.removeItem(at: file)
            } catch {
                // Offline, rate-limited or the API is down: keep it for the next launch.
                return
            }
        }
    }
}

extension ClientReporter.Report {
    /// The server caps the payload at 60,000 characters; JSON escaping can grow it, so cut short.
    static let payloadLimit = 50_000

    static func current(kind: ClientReporter.Kind, message: String, payload: String?, build: String? = nil) -> Self {
        let info = Bundle.main.infoDictionary
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return .init(
            kind: kind,
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: build ?? info?["CFBundleVersion"] as? String ?? "unknown",
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            deviceModel: deviceModel,
            message: String(message.prefix(512)),
            payload: payload.map { String($0.prefix(payloadLimit)) }
        )
    }

    /// The hardware identifier (`iPhone17,1`), not the marketing name.
    private static var deviceModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// MetricKit delivers the diagnostics of a crash or hang on a later launch, with unsymbolicated
/// call stacks. Symbolicate them against the archive's dSYM.
private final class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitSubscriber()

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let reports = payloads.flatMap { payload in
            (payload.crashDiagnostics ?? []).map(Self.report(crash:))
                + (payload.hangDiagnostics ?? []).map(Self.report(hang:))
        }
        guard !reports.isEmpty else { return }

        Task {
            for report in reports {
                await ClientReporter.shared.enqueue(report)
            }
        }
    }

    private static func report(crash: MXCrashDiagnostic) -> ClientReporter.Report {
        let parts = [
            crash.terminationReason,
            crash.exceptionType.map { "exception \($0)" },
            crash.exceptionCode.map { "code \($0)" },
            crash.signal.map { "signal \($0)" }
        ].compactMap { $0 }
        return .current(
            kind: .crash,
            message: parts.isEmpty ? "Crash" : parts.joined(separator: ", "),
            payload: String(decoding: crash.jsonRepresentation(), as: UTF8.self),
            build: crash.metaData.applicationBuildVersion
        )
    }

    private static func report(hang: MXHangDiagnostic) -> ClientReporter.Report {
        .current(
            kind: .hang,
            message: "Hang for \(hang.hangDuration.formatted())",
            payload: String(decoding: hang.jsonRepresentation(), as: UTF8.self),
            build: hang.metaData.applicationBuildVersion
        )
    }
}
