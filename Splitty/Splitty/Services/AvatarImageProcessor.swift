import UIKit

enum AvatarImageProcessor {
    static let outputSize = CGSize(width: 512, height: 512)

    /// Redrawing into a fresh bitmap and encoding it again removes the source metadata,
    /// including GPS data.
    static func prepare(_ sourceData: Data, crop: AvatarCrop) throws -> Data {
        guard let image = UIImage(data: sourceData), image.size.width > 0, image.size.height > 0 else {
            throw AvatarUploadError.invalidImage
        }

        let proposedRect = CGRect(
            x: crop.normalizedRect.minX * image.size.width,
            y: crop.normalizedRect.minY * image.size.height,
            width: crop.normalizedRect.width * image.size.width,
            height: crop.normalizedRect.height * image.size.height
        ).intersection(CGRect(origin: .zero, size: image.size))
        guard proposedRect.width > 0, proposedRect.height > 0 else {
            throw AvatarUploadError.invalidImage
        }
        let side = min(proposedRect.width, proposedRect.height)
        let sourceRect = CGRect(
            x: proposedRect.midX - side / 2,
            y: proposedRect.midY - side / 2,
            width: side,
            height: side
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let rendered = renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: outputSize))
            let scale = outputSize.width / sourceRect.width
            let drawRect = CGRect(
                x: -sourceRect.minX * scale,
                y: -sourceRect.minY * scale,
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            image.draw(in: drawRect)
        }

        guard let data = rendered.jpegData(compressionQuality: 0.8) else {
            throw AvatarUploadError.encodingFailed
        }
        return data
    }
}
