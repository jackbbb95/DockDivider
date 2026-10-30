//
//  RenderCache.swift
//  DockDivider
//

import Foundation
import AppKit
import CoreGraphics

/// Small main-actor cache for rendered divider artwork.
///
/// Rendering is deterministic for a given `RenderKey` and pixel size, so both
/// SwiftUI previews and bundle staging can reuse the same CGImages. The cache is
/// intentionally bounded: it should smooth over body passes and debounce
/// settles, not become a second copy of the user's image library.
@MainActor
final class RenderCache {
    static let shared = RenderCache()

    private struct CacheKey: Hashable {
        let renderKey: RenderKey
        let pixelSize: Int
    }

    private var images: [CacheKey: CGImage] = [:]
    private var imageOrder: [CacheKey] = []
    private let imageLimit = 64

    private var iconData: [RenderKey: Data] = [:]
    private var iconDataOrder: [RenderKey] = []
    private let iconDataLimit = 12

    private let sourceImages = NSCache<NSString, NSImage>()
    private let sourceImageLimit = 8

    /// Number of cache misses since the last reset. Exposed for tests.
    private(set) var imageMisses: Int = 0
    private(set) var iconDataMisses: Int = 0

    private init() {
        sourceImages.countLimit = sourceImageLimit
    }

    // MARK: - CGImages

    func image(for renderKey: RenderKey, pixelSize: Int) -> CGImage? {
        let key = CacheKey(renderKey: renderKey, pixelSize: pixelSize)
        guard let image = images[key] else {
            imageMisses += 1
            return nil
        }

        if let index = imageOrder.firstIndex(of: key) {
            imageOrder.remove(at: index)
            imageOrder.append(key)
        }
        return image
    }

    func store(_ image: CGImage, for renderKey: RenderKey, pixelSize: Int) {
        let key = CacheKey(renderKey: renderKey, pixelSize: pixelSize)
        images[key] = image

        imageOrder.removeAll { $0 == key }
        imageOrder.append(key)

        while imageOrder.count > imageLimit {
            let evicted = imageOrder.removeFirst()
            images.removeValue(forKey: evicted)
        }
    }

    // MARK: - ICNS Data

    func data(for renderKey: RenderKey) -> Data? {
        guard let data = iconData[renderKey] else {
            iconDataMisses += 1
            return nil
        }

        if let index = iconDataOrder.firstIndex(of: renderKey) {
            iconDataOrder.remove(at: index)
            iconDataOrder.append(renderKey)
        }
        return data
    }

    func store(_ data: Data, for renderKey: RenderKey) {
        iconData[renderKey] = data

        iconDataOrder.removeAll { $0 == renderKey }
        iconDataOrder.append(renderKey)

        while iconDataOrder.count > iconDataLimit {
            let evicted = iconDataOrder.removeFirst()
            iconData.removeValue(forKey: evicted)
        }
    }

    // MARK: - Decoded Source Images

    /// Returns the custom image decoded once per `imageID`.
    ///
    /// ImageIO applies EXIF orientation and caps the decoded size at 1024 px.
    /// Models created before `imageID` existed simply decode without caching.
    func sourceImage(for model: DividerModel) -> NSImage? {
        guard let data = model.imageData, !data.isEmpty else {
            return nil
        }

        let cacheKey = model.imageID?.uuidString as NSString?
        if let cacheKey, let cached = sourceImages.object(forKey: cacheKey) {
            return cached
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceShouldCacheImmediately: true
        ]

        let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)

        guard let cgImage else {
            return nil
        }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )

        if let cacheKey {
            sourceImages.setObject(image, forKey: cacheKey)
        }
        return image
    }

    // MARK: - Reset

    func removeAll() {
        images.removeAll()
        imageOrder.removeAll()
        iconData.removeAll()
        iconDataOrder.removeAll()
        sourceImages.removeAllObjects()
        imageMisses = 0
        iconDataMisses = 0
    }
}
