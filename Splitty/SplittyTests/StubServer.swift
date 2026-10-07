import Foundation
@testable import Splitty

/// A fake API reached through `URLProtocol`. Each server answers only for its own random
/// host, so suites that run in parallel never see each other's requests.
final class StubServer: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (status: Int, body: Data)

    let baseURL: String
    private let handler: Handler
    private let lock = NSLock()
    private var recorded: [URLRequest] = []

    init(handler: @escaping Handler) {
        baseURL = "https://\(UUID().uuidString.lowercased()).splitty.test"
        self.handler = handler
        StubURLProtocol.register(self, for: URL(string: baseURL)!.host!)
    }

    var requests: [URLRequest] { lock.withLock { recorded } }

    func requests(to path: String) -> [URLRequest] {
        requests.filter { $0.url?.path == path }
    }

    func client(
        credentials: any CredentialStore,
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(
            session: URLSession(configuration: configuration),
            credentials: credentials,
            baseURL: baseURL,
            notificationCenter: notificationCenter
        )
    }

    fileprivate func respond(to request: URLRequest) throws -> (status: Int, body: Data) {
        lock.withLock { recorded.append(request) }
        return try handler(request)
    }
}

extension URLRequest {
    var bearer: String? {
        value(forHTTPHeaderField: "Authorization").map { String($0.dropFirst("Bearer ".count)) }
    }

    var jsonBody: [String: Any]? {
        httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}

func json(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

/// A JWT whose payload carries only `exp` and a nonce. Nothing on the client checks the
/// signature, so the third segment is filler.
func jwt(expiresIn interval: TimeInterval) -> String {
    let payload = json([
        "exp": Date().addingTimeInterval(interval).timeIntervalSince1970,
        "jti": UUID().uuidString
    ])
    let encoded = payload.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "eyJhbGciOiJIUzI1NiJ9.\(encoded).signature"
}

final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Credentials?

    init(_ credentials: Credentials? = nil) {
        stored = credentials
    }

    func load() -> Credentials? { lock.withLock { stored } }
    func save(_ credentials: Credentials) { lock.withLock { stored = credentials } }
    func clear() { lock.withLock { stored = nil } }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var servers: [String: StubServer] = [:]

    static func register(_ server: StubServer, for host: String) {
        lock.withLock { servers[host] = server }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = request
        // `URLSession` hands a protocol the body as a stream, never as `httpBody`.
        if request.httpBody == nil, let stream = request.httpBodyStream {
            request.httpBody = Self.read(stream)
        }

        let server = Self.lock.withLock { Self.servers[request.url?.host ?? ""] }
        do {
            guard let server else { throw URLError(.cannotFindHost) }
            let (status, body) = try server.respond(to: request)
            client?.urlProtocol(
                self,
                didReceive: HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
