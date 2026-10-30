//
//  IconRenderer.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import Foundation
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

@MainActor
enum IconRenderer {

    // MARK: - ICNS Generation

    struct ICNSEntry {
        let pixelSize: Int
        let dpi: Int
    }

    /// Standard macOS `.icns` slot table.
    /// In the Apple ICNS specification, `64x64` (`32x32@2x`) and `1024x1024` (`512x512@2x`) are
    /// `@2x` Retina slots only (`144 DPI`), whereas `16`, `32`, `128`, `256`, and `512` exist at `72 DPI` (`@1x`).
    static let icnsEntries: [ICNSEntry] = [
        ICNSEntry(pixelSize: 16, dpi: 72),     // 16x16 @1x
        ICNSEntry(pixelSize: 32, dpi: 144),    // 16x16 @2x
        ICNSEntry(pixelSize: 32, dpi: 72),     // 32x32 @1x
        ICNSEntry(pixelSize: 64, dpi: 144),    // 32x32 @2x
        ICNSEntry(pixelSize: 128, dpi: 72),    // 128x128 @1x
        ICNSEntry(pixelSize: 256, dpi: 144),   // 256x256 @2x
        ICNSEntry(pixelSize: 256, dpi: 72),    // 256x256 @1x
        ICNSEntry(pixelSize: 512, dpi: 144),   // 256x256 @2x
        ICNSEntry(pixelSize: 512, dpi: 72),    // 512x512 @1x
        ICNSEntry(pixelSize: 1024, dpi: 144)   // 512x512 @2x
    ]

    static func renderIconData(for model: DividerModel) -> Data? {
        let key = cacheKey(for: model)
        if let key, let cached = RenderCache.shared.data(for: key) {
            return cached
        }

        guard let data = buildIconData(for: model) else {
            return nil
        }

        if let key {
            RenderCache.shared.store(data, for: key)
        }
        return data
    }

    private static func buildIconData(for model: DividerModel) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            UTType.icns.identifier as CFString,
            icnsEntries.count,
            nil
        ) else {
            return nil
        }

        // Reuse one CGImage for every ICNS entry that shares a pixel size.
        var sizeCache: [Int: CGImage] = [:]
        for entry in icnsEntries {
            let cgImage: CGImage?
            if let existing = sizeCache[entry.pixelSize] {
                cgImage = existing
            } else if let rendered = renderCGImage(for: model, pixelSize: entry.pixelSize) {
                sizeCache[entry.pixelSize] = rendered
                cgImage = rendered
            } else {
                cgImage = nil
            }

            if let image = cgImage {
                let properties: [CFString: Any] = [
                    kCGImagePropertyDPIWidth: entry.dpi,
                    kCGImagePropertyDPIHeight: entry.dpi
                ]
                CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            }
        }

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }

    // MARK: - Single Resolution Rendering

    static func renderNSImage(for model: DividerModel, size: CGSize = CGSize(width: 64, height: 64)) -> NSImage {
        let pixelSize = Int(max(size.width, size.height) * 2)
        if let cgImage = renderCGImage(for: model, pixelSize: pixelSize) {
            return NSImage(cgImage: cgImage, size: size)
        }
        return NSImage(size: size)
    }

    /// Returns the source image for the custom-image style, decoded once per
    /// `imageID` instead of once per ICNS pixel size.
    static func cachedSourceImage(for model: DividerModel) -> NSImage? {
        guard model.style == .image else { return nil }
        return RenderCache.shared.sourceImage(for: model)
    }

    static func renderCGImage(for model: DividerModel, pixelSize: Int) -> CGImage? {
        let key = cacheKey(for: model)
        if let key, let cached = RenderCache.shared.image(for: key, pixelSize: pixelSize) {
            return cached
        }

        guard let image = renderCGImageUncached(for: model, pixelSize: pixelSize) else {
            return nil
        }

        if let key {
            RenderCache.shared.store(image, for: key, pixelSize: pixelSize)
        }
        return image
    }

    private static func cacheKey(for model: DividerModel) -> RenderKey? {
        // A directly-assigned image without an identity cannot be cached safely:
        // two different images would share `imageID == nil` and collide.
        if model.style == .image, model.imageData != nil, model.imageID == nil {
            return nil
        }
        return RenderKey(model: model)
    }

    private static func renderCGImageUncached(for model: DividerModel, pixelSize: Int) -> CGImage? {
        let width = pixelSize
        let height = pixelSize
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        guard model.style != .spacer else {
            return context.makeImage()
        }

        let scale = CGFloat(pixelSize) / 64.0
        let vOffset = CGFloat(model.verticalOffset) * CGFloat(pixelSize)
        let color = model.effectiveNSColor.withAlphaComponent(CGFloat(model.opacity))
        context.setFillColor(color.cgColor)

        switch model.style {
        case .line:
            let lineWidth = max(1.0, CGFloat(model.thickness) * scale)
            let lineLength = CGFloat(pixelSize) * CGFloat(model.heightRatio)
            let rect: CGRect
            if model.orientation == .horizontal {
                // Horizontal line (—) for Left / Right vertical Dock orientation
                rect = CGRect(
                    x: (CGFloat(width) - lineLength) / 2.0,
                    y: (CGFloat(height) - lineWidth) / 2.0 + vOffset,
                    width: lineLength,
                    height: lineWidth
                )
            } else {
                // Vertical line (|) for Bottom horizontal Dock orientation
                rect = CGRect(
                    x: (CGFloat(width) - lineWidth) / 2.0,
                    y: (CGFloat(height) - lineLength) / 2.0 + vOffset,
                    width: lineWidth,
                    height: lineLength
                )
            }
            let path = CGPath(roundedRect: rect, cornerWidth: lineWidth / 2.0, cornerHeight: lineWidth / 2.0, transform: nil)
            context.addPath(path)
            context.fillPath()

        case .dashed:
            let lineWidth = max(1.0, CGFloat(model.thickness) * scale)
            let lineLength = CGFloat(pixelSize) * CGFloat(model.heightRatio)

            // Compute integer dash count in normalized 64pt space so every icon resolution
            // renders the exact same number of dashes, and solve for exact dashLength and
            // gapLength so all dashes are 100% uniform with no partial/clipped end dash.
            let baseWidth = max(1.0, CGFloat(model.thickness))
            let baseLength = 64.0 * CGFloat(model.heightRatio)
            let gapRatio: CGFloat = 0.75
            let idealDash = max(3.0, baseWidth * 2.4)
            let rawCount = Int(round((baseLength + gapRatio * idealDash) / ((1.0 + gapRatio) * idealDash)))
            let maxFittingCount = max(2, Int(floor((baseLength + gapRatio * baseWidth) / ((1.0 + gapRatio) * baseWidth))))
            let dashCount = max(2, min(rawCount, maxFittingCount))

            let totalUnits = CGFloat(dashCount) + CGFloat(dashCount - 1) * gapRatio
            let dashSpan = lineLength / totalUnits
            let gapSpan = dashSpan * gapRatio
            let cornerRadius = min(lineWidth, dashSpan) / 2.0

            if model.orientation == .horizontal {
                // Horizontal dashed line (- - -) for Left / Right vertical Dock orientation
                let startX = (CGFloat(width) - lineLength) / 2.0
                let y = (CGFloat(height) - lineWidth) / 2.0 + vOffset
                for i in 0..<dashCount {
                    let x = startX + CGFloat(i) * (dashSpan + gapSpan)
                    let rect = CGRect(x: x, y: y, width: dashSpan, height: lineWidth)
                    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
                    context.addPath(path)
                }
            } else {
                // Vertical dashed line (⋮) for Bottom horizontal Dock orientation
                let startY = (CGFloat(height) - lineLength) / 2.0 + vOffset
                let x = (CGFloat(width) - lineWidth) / 2.0
                for i in 0..<dashCount {
                    let y = startY + CGFloat(i) * (dashSpan + gapSpan)
                    let rect = CGRect(x: x, y: y, width: lineWidth, height: dashSpan)
                    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
                    context.addPath(path)
                }
            }
            context.fillPath()

        case .dot:
            let diameter = max(3.0, CGFloat(model.thickness) * scale * 2.0)
            let rect = CGRect(
                x: (CGFloat(width) - diameter) / 2.0,
                y: (CGFloat(height) - diameter) / 2.0 + vOffset,
                width: diameter,
                height: diameter
            )
            context.fillEllipse(in: rect)

        case .label:
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext

            context.saveGState()
            context.clip(to: CGRect(x: 0, y: 0, width: width, height: height))

            switch model.labelMode {
            case .text:
                let rawText = model.labelText.isEmpty ? "DEV" : String(model.labelText.prefix(4))
                let displayText = model.isVerticalText ? rawText.map { String($0) }.joined(separator: "\n") : rawText
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center

                let maximumDimension = CGFloat(pixelSize) * 0.90
                let fontSize = fittedLabelFontSize(
                    text: displayText,
                    isVertical: model.isVerticalText,
                    scale: scale,
                    heightRatio: CGFloat(model.heightRatio),
                    maximumDimension: maximumDimension
                )

                let font = NSFont.boldSystemFont(ofSize: fontSize)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraphStyle
                ]
                let attrString = NSAttributedString(string: displayText, attributes: attributes)
                let textSize = attrString.size()
                let textRect = CGRect(
                    x: (CGFloat(width) - textSize.width) / 2.0,
                    y: (CGFloat(height) - textSize.height) / 2.0 + vOffset,
                    width: textSize.width,
                    height: textSize.height
                )
                attrString.draw(in: textRect)

            case .symbol:
                let trimmedName = model.symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
                let symbolName = trimmedName.isEmpty ? "star.fill" : trimmedName
                let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
                    ?? NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)

                if let symbol = symbolImage {
                    let pointSize = max(10.0, 28.0 * scale * (CGFloat(model.heightRatio) / 0.65))
                    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
                        .applying(.init(paletteColors: [color]))
                    let configuredSymbol = symbol.withSymbolConfiguration(config) ?? symbol

                    let boundingBox = CGFloat(width) * CGFloat(model.heightRatio)
                    let symRect = aspectFitRect(
                        for: configuredSymbol.size,
                        boundingBox: boundingBox,
                        canvasWidth: width,
                        canvasHeight: height,
                        vOffset: vOffset
                    )
                    configuredSymbol.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                }
            }

            context.restoreGState()
            NSGraphicsContext.restoreGraphicsState()

        case .image:
            if let img = cachedSourceImage(for: model) {
                let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = graphicsContext

                let boundingBox = CGFloat(width) * CGFloat(model.heightRatio)
                let rect = aspectFitRect(
                    for: img.size,
                    boundingBox: boundingBox,
                    canvasWidth: width,
                    canvasHeight: height,
                    vOffset: vOffset
                )
                if model.roundImageCorners {
                    let cornerRadius = min(rect.width, rect.height) * CGFloat(model.imageCornerRadiusRatio)
                    let clipPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
                    clipPath.addClip()
                }
                img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: CGFloat(model.opacity))
                NSGraphicsContext.restoreGraphicsState()
            }

        case .spacer:
            break
        }

        return context.makeImage()
    }

    // MARK: - Style Drawing Helpers

    /// Shrinks the label until the measured text fits inside the icon canvas.
    /// A few points of margin are reserved so anti-aliased edges do not touch
    /// the canvas boundary.
    private static func fittedLabelFontSize(
        text: String,
        isVertical: Bool,
        scale: CGFloat,
        heightRatio: CGFloat,
        maximumDimension: CGFloat
    ) -> CGFloat {
        let normalizedRatio = max(0.2, heightRatio)
        let baseSize = (isVertical ? 14.0 : 18.0) * scale * (normalizedRatio / 0.65)
        var size = max(1.0, baseSize)
        let minimumSize = max(1.0, 4.0 * scale)

        while size > minimumSize {
            let font = NSFont.boldSystemFont(ofSize: size)
            let measured = (text as NSString).size(withAttributes: [.font: font])
            if measured.width <= maximumDimension, measured.height <= maximumDimension {
                return size
            }
            size -= max(0.25, size * 0.08)
        }

        return minimumSize
    }

    private static func aspectFitRect(
        for imageSize: NSSize,
        boundingBox: CGFloat,
        canvasWidth: Int,
        canvasHeight: Int,
        vOffset: CGFloat
    ) -> CGRect {
        let aspect = imageSize.width > 0 && imageSize.height > 0 ? (imageSize.width / imageSize.height) : 1.0
        let drawWidth: CGFloat
        let drawHeight: CGFloat
        if aspect >= 1.0 {
            drawWidth = boundingBox
            drawHeight = boundingBox / aspect
        } else {
            drawHeight = boundingBox
            drawWidth = boundingBox * aspect
        }
        return CGRect(
            x: (CGFloat(canvasWidth) - drawWidth) / 2.0,
            y: (CGFloat(canvasHeight) - drawHeight) / 2.0 + vOffset,
            width: drawWidth,
            height: drawHeight
        )
    }
}
