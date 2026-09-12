//
//  MemberAvatar.swift
//  Splitty
//

import SwiftUI

struct MemberAvatar: View {
    let display: MemberDisplay
    var size: CGFloat = 40

    var body: some View {
        CachedAsyncImage(url: display.avatarURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle()
                .fill(Color("muted"))
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundStyle(Color("muted-foreground"))
                }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
