//
//  MemberAvatar.swift
//  Splitty
//

import SwiftUI

struct MemberAvatar: View {
    let display: MemberDisplay
    var size: CGFloat = 40

    var body: some View {
        AsyncImage(url: display.avatarURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Circle()
                    .fill(Color("muted"))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.4, weight: .medium))
                            .foregroundStyle(Color("muted-foreground"))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
