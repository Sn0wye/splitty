//
//  APIEndpoints.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

struct APIEndpoints {
    static let baseURL = "http://127.0.0.1:8080"
    
    struct Profile {
        static let getProfile = baseURL + "/profile"
    }
    
    struct Group {
        static let getGroups = baseURL + "/group"
    }
}
