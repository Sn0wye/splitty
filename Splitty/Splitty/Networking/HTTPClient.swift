//
//  HTTPClient.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import Foundation

enum HTTPMethod: String {
    case GET, POST, PUT, DELETE
}

struct HTTPClient {
    static let shared = HTTPClient()
    
    private init() {}

    func request<T: Decodable>(
        url: URL,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        headers: [String: String] = [:],
        requiresAuth: Bool = true,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body

        // Ensure Authorization and Content-Type headers are included
        var requestHeaders = headers
        
        // Add bearer token from TokenManager if authentication is required
        if requiresAuth {
            guard let bearerToken = TokenManager.shared.getBearerToken() else {
                completion(.failure(NSError(
                    domain: "Authentication Error",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "No valid authentication token found"]
                )))
                return
            }
            requestHeaders["Authorization"] = bearerToken
        }
        
        requestHeaders["Content-Type"] = "application/json"
        
        // Apply headers correctly
        requestHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "Invalid response", code: -2, userInfo: nil)))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let statusError = NSError(domain: "HTTP Error", code: httpResponse.statusCode, userInfo: nil)
                completion(.failure(statusError))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: -1, userInfo: nil)))
                return
            }

            do {
                let decodedData = try JSONDecoder().decode(T.self, from: data)
                print("✅ Response:", decodedData)
                completion(.success(decodedData))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
