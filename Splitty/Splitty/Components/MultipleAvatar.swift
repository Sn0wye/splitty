import SwiftUI

/// How many faces a group card can show before the row becomes a count.
///
/// Four 40pt circles still fit a phone card. A fifth one, overlapped or not, is
/// what stretched the card past the screen.
struct AvatarStack: Equatable {
    static let maxVisibleFaces = 4

    let urls: [URL]
    let overflow: Int

    static func from(_ urls: [URL], total: Int? = nil) -> AvatarStack {
        let people = total ?? urls.count
        if people <= maxVisibleFaces {
            return AvatarStack(urls: Array(urls.prefix(people)), overflow: 0)
        }

        let visible = Array(urls.prefix(maxVisibleFaces - 1))
        return AvatarStack(urls: visible, overflow: people - visible.count)
    }
}

struct MultipleAvatar: View {
    let urls: [URL]
    var total: Int? = nil

    private var stack: AvatarStack { .from(urls, total: total) }

    var body: some View {
        let people = total ?? urls.count
        HStack(spacing: -12) {
            ForEach(Array(stack.urls.enumerated()), id: \.offset) { _, url in
                face(url)
            }

            if stack.overflow > 0 {
                overflowBadge(stack.overflow)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(people == 1 ? "1 member" : "\(people) members")
    }

    private func face(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                Circle()
                    .fill(Color("muted"))
                    .overlay(ProgressView().controlSize(.mini))
            case .success(let image):
                image.resizable()
                    .scaledToFill()
            case .failure:
                Circle()
                    .fill(Color("muted"))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color("muted-foreground"))
                    }
            @unknown default:
                EmptyView()
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(Color("card"), lineWidth: 2)
        }
    }

    private func overflowBadge(_ count: Int) -> some View {
        Text("+\(count)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color("muted-foreground"))
            .frame(width: 40, height: 40)
            .background(Color("muted"), in: Circle())
            .overlay {
                Circle().stroke(Color("card"), lineWidth: 2)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        MultipleAvatar(urls: [
            URL(string: "https://github.com/Sn0wye.png")!,
            URL(string: "https://github.com/diego3g.png")!,
            URL(string: "https://github.com/vinirossado.png")!,
        ])
        MultipleAvatar(
            urls: (1...8).compactMap { URL(string: "https://picsum.photos/id/\($0)/1024/1024") },
            total: 50
        )
    }
    .padding()
    .background(Color("card"))
}
