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

    /// Small least-recently-used store used for both rendered images and ICNS
    /// payloads. Reading an entry promotes it so bursts of preview passes keep
    /// the images they are actively drawing.
    private struct LRUCache<Key: Hashable, Value> {
        private var values: [Key: Value] = [:]
        private var order: [Key] = []
        private let limit: Int

        init(limit: Int) {
            self.limit = limit
        }

        mutating func value(for key: Key) -> Value? {
            guard let value = values[key] else { return nil }
            touch(key)
            return value
        }

        mutating func insert(_ value: Value, for key: Key) {
            values[key] = value
            touch(key)

            while order.count > limit {
                values.removeValue(forKey: order.removeFirst())
            }
        }

        mutating func removeAll() {
            values.removeAll()
            order.removeAll()
        }

        private mutating func touch(_ key: Key) {
            if let index = order.firstIndex(of: key) {
                order.remove(at: index)
            }
            order.append(key)
        }
    }

    private var images = LRUCache<CacheKey, CGImage>(limit: 64)
    private var iconData = LRUCache<RenderKey, Data>(limit: 12)

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
        guard let image = images.value(for: key) else {
            imageMisses += 1
            return nil
        }
        return image
    }

    func store(_ image: CGImage, for renderKey: RenderKey, pixelSize: Int) {
        images.insert(image, for: CacheKey(renderKey: renderKey, pixelSize: pixelSize))
    }

    // MARK: - ICNS Data

    func data(for renderKey: RenderKey) -> Data? {
        guard let data = iconData.value(for: renderKey) else {
            iconDataMisses += 1
            return nil
        }
        return data
    }

    func store(_ data: Data, for renderKey: RenderKey) {
        iconData.insert(data, for: renderKey)
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
        iconData.removeAll()
        sourceImages.removeAllObjects()
        imageMisses = 0
        iconDataMisses = 0
    }
}
