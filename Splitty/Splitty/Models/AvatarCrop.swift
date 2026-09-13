import CoreGraphics

struct AvatarCrop: Equatable {
    let normalizedRect: CGRect

    static let fullImage = AvatarCrop(normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1))

    init(normalizedRect: CGRect) {
        self.normalizedRect = CGRect(
            x: min(max(normalizedRect.minX, 0), 1),
            y: min(max(normalizedRect.minY, 0), 1),
            width: min(max(normalizedRect.width, 0), 1),
            height: min(max(normalizedRect.height, 0), 1)
        )
    }
}
