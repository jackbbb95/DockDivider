//
//  DividerModel+AppKit.swift
//  DockDivider
//
//  App-only presentation helpers. Keeping these out of `DividerModel.swift`
//  leaves the persisted model free of SwiftUI/AppKit dependencies.
//

import SwiftUI
import AppKit

extension DividerModel {
    @MainActor
    var effectiveColor: Color {
        switch colorPreset {
        case .adaptiveWhite:
            return Color.white
        case .dark:
            return Color(white: 0.15)
        case .custom:
            return Color(.sRGB, red: customRed, green: customGreen, blue: customBlue, opacity: 1.0)
        }
    }

    @MainActor
    var effectiveNSColor: NSColor {
        switch colorPreset {
        case .adaptiveWhite:
            return NSColor.white
        case .dark:
            return NSColor(white: 0.15, alpha: 1.0)
        case .custom:
            return NSColor(srgbRed: CGFloat(customRed), green: CGFloat(customGreen), blue: CGFloat(customBlue), alpha: 1.0)
        }
    }

    @MainActor
    mutating func updateCustomColor(from newColor: Color) {
        let nsColor = NSColor(newColor)
        guard let srgbColor = nsColor.usingColorSpace(.sRGB) else { return }
        customRed = Double(srgbColor.redComponent)
        customGreen = Double(srgbColor.greenComponent)
        customBlue = Double(srgbColor.blueComponent)
    }
}
