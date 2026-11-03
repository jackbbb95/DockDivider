//
//  CustomImageProcessor.swift
//  DockDivider
//

import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct ProcessedImage: Sendable {
    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let imageID: UUID
}

enum ImageProcessingError: Error, Equatable, LocalizedError, Sendable {
    case unreadable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "DockDivider couldn’t read that image."
        case .encodingFailed:
            return "DockDivider couldn’t prepare that image for use."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unreadable:
            return "Try a PNG, JPEG, HEIC, TIFF, or SVG file."
        case .encodingFailed:
            return "Try exporting the image as a PNG and choosing it again."
        }
    }
}

/// Normalizes imported artwork once, before it reaches the renderer or a
/// generated bundle. Common formats go through ImageIO off the main actor;
/// formats ImageIO cannot rasterize (notably SVG) fall back to AppKit.
enum CustomImageProcessor {
    static let maximumPixelSize = 1024

    static func process(fileURL: URL) throws -> ProcessedImage {
        if let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) {
            return try process(source: source)
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            throw ImageProcessingError.unreadable
        }
        return try process(data: data)
    }

    static func process(data: Data) throws -> ProcessedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageProcessingError.unreadable
        }
        return try process(source: source)
    }

    private static func process(source: CGImageSource) throws -> ProcessedImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageProcessingError.unreadable
        }

        let pngData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            pngData as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageProcessingError.encodingFailed
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessingError.encodingFailed
        }

        return ProcessedImage(
            data: pngData as Data,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            imageID: UUID()
        )
    }

    /// AppKit fallback for vector formats such as SVG.
    @MainActor
    static func rasterize(image: NSImage) -> ProcessedImage? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let scale = min(1.0, CGFloat(maximumPixelSize) / max(sourceSize.width, sourceSize.height))
        let width = max(1, Int((sourceSize.width * scale).rounded()))
        let height = max(1, Int((sourceSize.height * scale).rounded()))

        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        representation.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
        image.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let data = representation.representation(using: .png, properties: [:]) else {
            return nil
        }

        return ProcessedImage(
            data: data,
            pixelWidth: width,
            pixelHeight: height,
            imageID: UUID()
        )
    }
}
