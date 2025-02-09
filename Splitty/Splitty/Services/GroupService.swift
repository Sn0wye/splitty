//
//  GroupService.swift
//  Splitty
//
//  Created by Snowye on 07/02/25.
//

import Foundation

struct GroupService {
    static func fetchGroups(completion: @escaping (Result<[Group], Error>) -> Void) {
        guard let url = URL(string: APIEndpoints.Group.getGroups) else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1, userInfo: nil)))
            return
        }
        
        HTTPClient.shared.request(url: url, completion: completion)
    }
}
