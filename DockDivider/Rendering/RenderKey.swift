//
//  RenderKey.swift
//  DockDivider
//

import Foundation

/// Identity of everything that affects the rendered divider artwork.
///
/// Properties that only affect bundle metadata (click actions, URLs, shell
/// commands, hover labels) are deliberately excluded, so editing those fields
/// reuses the cached icon instead of re-rendering it.
struct RenderKey: Hashable, Sendable {
    let style: DividerStyle
    let orientation: DividerOrientation
    let spacerSize: SpacerSize
    let colorPreset: ColorPreset
    let customRGB: UInt32
    let opacity: Double
    let thickness: Double
    let heightRatio: Double
    let verticalOffset: Double
    let labelMode: LabelMode
    let labelText: String
    let isVerticalText: Bool
    let symbolName: String
    let imageID: UUID?
    let roundImageCorners: Bool
    let imageCornerRadiusRatio: Double

    init(model: DividerModel) {
        self.style = model.style
        self.orientation = model.orientation
        self.spacerSize = model.style == .spacer ? model.spacerSize : .regular

        if model.style == .spacer {
            self.colorPreset = .adaptiveWhite
            self.customRGB = 0
            self.opacity = 1.0
        } else {
            self.colorPreset = model.colorPreset
            self.customRGB = model.colorPreset == .custom
                ? Self.packedRGB(red: model.customRed, green: model.customGreen, blue: model.customBlue)
                : 0
            self.opacity = model.opacity
        }

        let usesStroke = model.style.supportsThickness
        self.thickness = usesStroke ? model.thickness : 0
        self.heightRatio = model.style == .spacer ? 1.0 : model.heightRatio
        self.verticalOffset = model.style == .spacer ? 0 : model.verticalOffset

        if model.style == .label {
            self.labelMode = model.labelMode
            self.labelText = model.labelMode == .text ? model.labelText : ""
            self.isVerticalText = model.labelMode == .text ? model.isVerticalText : false
            self.symbolName = model.labelMode == .symbol ? model.symbolName : ""
        } else {
            self.labelMode = .text
            self.labelText = ""
            self.isVerticalText = false
            self.symbolName = ""
        }

        if model.style == .image {
            self.imageID = model.imageID
            self.roundImageCorners = model.roundImageCorners
            self.imageCornerRadiusRatio = model.imageCornerRadiusRatio
        } else {
            self.imageID = nil
            self.roundImageCorners = true
            self.imageCornerRadiusRatio = 0
        }
    }

    private static func packedRGB(red: Double, green: Double, blue: Double) -> UInt32 {
        let r = UInt32((min(max(red, 0), 1) * 255).rounded())
        let g = UInt32((min(max(green, 0), 1) * 255).rounded())
        let b = UInt32((min(max(blue, 0), 1) * 255).rounded())
        return (r << 16) | (g << 8) | b
    }
}
