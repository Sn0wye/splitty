//
//  HTTPClient.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import Foundation

import Foundation

struct HTTPClient {
    static let shared = HTTPClient()
    
    private init() {}

    func request<T: Decodable>(
        url: URL,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        headers: [String: String] = [:],
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body

        // Ensure Authorization and Content-Type headers are included
        var requestHeaders = headers
        requestHeaders["Authorization"] = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJodHRwOi8vc2NoZW1hcy54bWxzb2FwLm9yZy93cy8yMDA1LzA1L2lkZW50aXR5L2NsYWltcy9uYW1laWRlbnRpZmllciI6IjQiLCJodHRwOi8vc2NoZW1hcy54bWxzb2FwLm9yZy93cy8yMDA1LzA1L2lkZW50aXR5L2NsYWltcy9uYW1lIjoiSm9obiBEb2UiLCJodHRwOi8vc2NoZW1hcy54bWxzb2FwLm9yZy93cy8yMDA1LzA1L2lkZW50aXR5L2NsYWltcy9lbWFpbGFkZHJlc3MiOiJqb2huQGV4YW1wbGUuY29tIiwic3ViIjoiam9obkBleGFtcGxlLmNvbSIsImV4cCI6MTczOTQ5NDM0MywiaXNzIjoiU3BsaXR0eSJ9.gx0Ddpsdtto0YPGbT2JYVm_EAkPe66djjNyvmS-zmos"
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
