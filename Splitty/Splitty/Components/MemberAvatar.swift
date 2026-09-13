//
//  MemberAvatar.swift
//  Splitty
//

import SwiftUI

struct MemberAvatar: View {
    let display: MemberDisplay
    var size: CGFloat = 40
    @ObservedObject private var authManager = AuthenticationManager.shared

    var body: some View {
        CachedAsyncImage(url: resolvedDisplay.avatarURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle()
                .fill(Color("muted"))
                .overlay {
                    Text(initials)
                        .font(.system(size: size * 0.34, weight: .semibold))
                        .foregroundStyle(Color("muted-foreground"))
                }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: String {
        let words = resolvedDisplay.name.split(whereSeparator: \.isWhitespace)
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private var resolvedDisplay: MemberDisplay {
        display.resolved(currentUser: authManager.currentUser)
    }
}
