import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Splitty

struct AvatarImageProcessorTests {
    @Test func producesASmallSquareJPEGWithoutLocationMetadata() throws {
        let source = try imageDataWithLocationMetadata(width: 900, height: 600)

        let output = try AvatarImageProcessor.prepare(source, crop: .fullImage)
        let imageSource = try #require(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])

        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 512)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 512)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(CGImageSourceGetType(imageSource) as String? == UTType.jpeg.identifier)
        #expect(output.count < 2_000_000)
    }

    private func imageDataWithLocationMetadata(width: Int, height: Int) throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let imageData = try #require(image.jpegData(compressionQuality: 1))
        let source = try #require(CGImageSourceCreateWithData(imageData as CFData, nil))
        let type = try #require(CGImageSourceGetType(source))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, type, 1, nil))
        let metadata: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 51.5,
                kCGImagePropertyGPSLatitudeRef: "N"
            ]
        ]
        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
