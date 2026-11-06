//
//  CachedAsyncImage.swift
//  Splitty
//

import ImageIO
import SwiftUI

/// Avatars are immutable for a given URL, so a decoded image is worth keeping
/// for the whole session.
///
/// `AsyncImage` restarts its load every time its view appears and throws the
/// result away when the view goes away, which is why faces flickered back in on
/// every navigation. This cache holds decoded images in memory and dedupes
/// concurrent loads of the same URL, with a private `URLCache` behind it so the
/// bytes survive a relaunch too.
@MainActor
final class AvatarImageCache {
    static let shared = AvatarImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    init() {
        memory.countLimit = 300

        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "splitty-avatars"
        )
        // Avatar bytes are content-addressed by URL; revalidating them on every
        // appearance is the round trip we are trying to remove.
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    /// Already-decoded image, if any. Lets a view render on its first frame
    /// instead of flashing a placeholder.
    func cached(_ url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }

        if let running = inFlight[url] {
            return await running.value
        }

        let task = Task.detached(priority: .userInitiated) { [session] () -> UIImage? in
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return Self.decodedForDisplay(data) ?? UIImage(data: data)
        }
        inFlight[url] = task

        let image = await task.value
        inFlight[url] = nil
        if let image {
            memory.setObject(image, forKey: url as NSURL)
        }
        return image
    }

    /// The largest face the app draws, in pixels: the 112pt profile avatar at 3x.
    nonisolated static let maxPixelSize = 336

    /// Decodes on the calling thread, at no more than `maxPixelSize`, through ImageIO's
    /// thumbnail path. `UIImage(data:)` defers decoding to the first frame that draws the
    /// image, which is on the main thread, and keeps the source's full resolution for a
    /// 40pt circle. Nil when ImageIO cannot read the data.
    nonisolated static func decodedForDisplay(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Drop-in replacement for the subset of `AsyncImage` this app uses, backed by
/// ``AvatarImageCache`` so a face loads once per session rather than once per
/// screen.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { AvatarImageCache.shared.cached($0) })
    }

    var body: some View {
        // `Group` is a model type in this app, so spell out the SwiftUI one.
        SwiftUI.Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            // Recycled rows can hand us a different URL; re-read the cache so we
            // never show the previous member's face.
            if let hit = AvatarImageCache.shared.cached(url) {
                image = hit
                return
            }
            image = nil
            image = await AvatarImageCache.shared.image(for: url)
        }
    }
}
