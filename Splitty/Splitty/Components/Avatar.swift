//
//  Avatar.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

struct Avatar: View {
//    var url: URL
    
    var body: some View {
        AsyncImage(url: URL(string: "https://github.com/Sn0wye.png")) { phase in
            switch phase {
            case .empty:
                ProgressView()
            case .success(let image):
                image.resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            case .failure:
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.gray)
            @unknown default:
                EmptyView()
            }
        }
    }
}
