//
//  MultipleAvatar.swift
//  Splitty
//
//  Created by Snowye on 06/02/25.
//

import SwiftUI

public struct MultipleAvatar: View {
    let urls: [URL]
    
    public var body: some View {
        HStack(spacing: -12) {
            ForEach(urls, id: \.self) { url in
                ZStack {
                    AsyncImage(url: url) { phase in
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
        }
    }
}

#Preview {
    MultipleAvatar(urls: [
        URL(string: "https://github.com/Sn0wye.png")!,
        URL(string: "https://github.com/diego3g.png")!,
        URL(string: "https://github.com/vinirossado.png")!,
    ])
}
