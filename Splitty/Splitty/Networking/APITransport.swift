import Foundation

/// Builds, sends and decodes API requests, with no notion of who is signed in.
struct APITransport: Sendable {
    /// Resolved once at startup; a misconfigured build fails on every request rather
    /// than falling back to a hardcoded host.
    let baseURL: Result<String, Error>
    let session: URLSession

    func makeRequest(endpoint: String, method: HTTPMethod, body: [String: Any]?) throws -> URLRequest {
        guard let url = URL(string: try baseURL.get() + endpoint) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                throw APIError.invalidRequestBody
            }
        }

        return request
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            return (data, httpResponse)
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            // SwiftUI owns tasks such as pull-to-refresh and may cancel them when their
            // view disappears. Cancellation is control flow, not a failed connection.
            throw CancellationError()
        } catch {
            throw APIError.networkError(error)
        }
    }

    func decode<T: Decodable>(
        _ type: T.Type,
        endpoint: String,
        data: Data,
        response: HTTPURLResponse
    ) throws -> T {
        guard 200...299 ~= response.statusCode else {
            throw Self.refusal(status: response.statusCode, data: data)
        }

        // A 204 carries no body; decoding one is a failure that has nothing to report.
        if data.isEmpty, let empty = EmptyResponse() as? T {
            return empty
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Log the JSON response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("❌ Decoding error for endpoint \(endpoint)")
                print("📄 JSON Response: \(jsonString)")
            }
            throw APIError.decodingError(error)
        }
    }

    /// What the server said when it refused, read once from either error shape the API
    /// produces: its own `ErrorResponse`, which may name the refusal with a code this build
    /// knows, or the validation dictionary `ModelState` returns.
    private static func refusal(status: Int, data: Data) -> APIError {
        let json = data.isEmpty ? nil : (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = json.flatMap(serverMessage(from:))
        if let code = (json?["code"] as? String).flatMap(APIErrorCode.init(rawValue:)) {
            return .refused(status, code: code, message: message)
        }
        return .httpError(status, message: message)
    }

    private static func serverMessage(from json: [String: Any]) -> String? {
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }

        if let errors = json["errors"] as? [String: Any] {
            let messages = errors.values.compactMap { $0 as? [String] }.flatMap { $0 }
            if !messages.isEmpty { return messages.joined(separator: " ") }
        }

        return nil
    }
}
