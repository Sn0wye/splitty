import Testing
import UIKit
@testable import Splitty

/// Avatars are decoded off the main thread at the size they are drawn, rather than on the
/// first frame that shows them at the size they were uploaded.
struct AvatarDecodingTests {
    private func jpeg(width: Int, height: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            for row in 0..<16 {
                UIColor(hue: CGFloat(row) / 16, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: row * height / 16, width: width, height: height / 16))
            }
        }
        return try #require(image.jpegData(compressionQuality: 0.9))
    }

    @Test func aLargeAvatarIsDecodedAtTheLargestDrawnSize() throws {
        let image = try #require(AvatarImageCache.decodedForDisplay(try jpeg(width: 1024, height: 768)))
        let cgImage = try #require(image.cgImage)
        #expect(max(cgImage.width, cgImage.height) == AvatarImageCache.maxPixelSize)
        // Aspect kept: 1024x768 is 4:3.
        #expect(cgImage.height == AvatarImageCache.maxPixelSize * 3 / 4)
    }

    @Test func aSmallAvatarKeepsItsSize() throws {
        let image = try #require(AvatarImageCache.decodedForDisplay(try jpeg(width: 96, height: 96)))
        #expect(image.cgImage?.width == 96)
        #expect(image.cgImage?.height == 96)
    }

    @Test func unreadableDataIsNil() {
        #expect(AvatarImageCache.decodedForDisplay(Data("not an image".utf8)) == nil)
    }

    /// Evidence rather than a gate: what the first frame drawing a 1024px avatar into a
    /// 40pt circle costs on the main thread, both ways, and the bitmap each keeps.
    @Test @MainActor func drawingAPreparedAvatarIsCheaperOnTheMainThread() throws {
        let data = try jpeg(width: 1024, height: 1024)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40), format: format)
        let clock = ContinuousClock()
        var lazyBytes = 0
        var preparedBytes = 0

        let lazy = clock.measure {
            for _ in 0..<20 {
                let image = UIImage(data: data)!
                _ = renderer.image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 40, height: 40)) }
                lazyBytes = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            }
        }
        // Decoded off the main thread in the app; here only the draw is the main thread's.
        let decoded = (0..<20).map { _ in AvatarImageCache.decodedForDisplay(data)! }
        let prepared = clock.measure {
            for image in decoded {
                _ = renderer.image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 40, height: 40)) }
                preparedBytes = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            }
        }
        print("Avatar first draw on main, 20 images: UIImage(data:) \(lazy) (\(lazyBytes) bytes each), prepared \(prepared) (\(preparedBytes) bytes each)")
        #expect(prepared < lazy)
        #expect(preparedBytes < lazyBytes)
    }
}
