//
//  DividerModel.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import Foundation

// MARK: - Supporting Enums

nonisolated enum DividerStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case line = "line"
    case dashed = "dashed"
    case dot = "dot"
    case label = "label"
    case spacer = "spacer"
    case image = "image"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .line: return "Line"
        case .dashed: return "Dashed"
        case .dot: return "Dot"
        case .label: return "Label"
        case .spacer: return "Spacer"
        case .image: return "Image"
        }
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.lowercased() {
        case "line": self = .line
        case "dashed": self = .dashed
        case "dot": self = .dot
        case "label": self = .label
        case "spacer": self = .spacer
        case "image": self = .image
        default: self = .line
        }
    }
}

nonisolated enum LabelMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case text = "text"
    case symbol = "symbol"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .symbol: return "SF Symbol"
        }
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.lowercased() {
        case "text": self = .text
        case "symbol", "sf symbol": self = .symbol
        default: self = .text
        }
    }
}

nonisolated enum ColorPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case adaptiveWhite = "adaptiveWhite"
    case dark = "dark"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .adaptiveWhite: return "Light"
        case .dark: return "Dark"
        case .custom: return "Custom"
        }
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.lowercased() {
        case "white", "light", "adaptivewhite": self = .adaptiveWhite
        case "dark": self = .dark
        case "custom": self = .custom
        default: self = .adaptiveWhite
        }
    }
}

nonisolated enum DividerOrientation: String, CaseIterable, Identifiable, Codable, Sendable {
    case vertical = "vertical"
    case horizontal = "horizontal"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vertical: return "Vertical"
        case .horizontal: return "Horizontal"
        }
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw.lowercased().contains("horizontal") || raw.contains("Side") {
            self = .horizontal
        } else {
            self = .vertical
        }
    }

    /// Reads `com.apple.dock` preferences to detect whether the user's macOS Dock is positioned
    /// on the bottom of the screen (`.vertical` separator) or on the left/right side (`.horizontal` separator).
    nonisolated static var currentSystemDockOrientation: DividerOrientation {
        if let dockDefaults = UserDefaults(suiteName: "com.apple.dock"),
           let pos = dockDefaults.string(forKey: "orientation")?.lowercased(),
           (pos == "left" || pos == "right") {
            return .horizontal
        }
        return .vertical
    }
}

nonisolated enum SpacerSize: String, CaseIterable, Identifiable, Codable, Sendable {
    case regular = "regular"
    case small = "small"
    case flex = "flex"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .regular: return "Full"
        case .small: return "Half"
        case .flex: return "Flexible"
        }
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.lowercased() {
        case "regular", "full": self = .regular
        case "small", "half": self = .small
        case "flex", "flexible": self = .flex
        default: self = .regular
        }
    }

    var fileExtension: String {
        switch self {
        case .regular: return "dockspace"
        case .small: return "docksmallspace"
        case .flex: return "dockflexspace"
        }
    }
}

// MARK: - DividerModel Definition

nonisolated struct DividerModel: Identifiable, Equatable, Sendable, Codable {
    var id: UUID = UUID()
    var style: DividerStyle = .line {
        didSet {
            if style != .image && heightRatio > 1.0 {
                heightRatio = 1.0
            }
        }
    }
    var orientation: DividerOrientation = .vertical
    var spacerSize: SpacerSize = .regular
    var colorPreset: ColorPreset = .adaptiveWhite
    var customRed: Double = 1.0
    var customGreen: Double = 1.0
    var customBlue: Double = 1.0
    var opacity: Double = 0.80
    var thickness: Double = 1.5
    var heightRatio: Double = 0.65
    var verticalOffset: Double = 0.0
    var hoverLabel: String = ""
    var labelMode: LabelMode = .text
    var labelText: String = "DEV"
    var isVerticalText: Bool = false
    var symbolName: String = "star.fill"
    var imageData: Data? = nil
    var imageID: UUID? = nil
    var roundImageCorners: Bool = true
    var imageCornerRadiusRatio: Double = 0.225
    var actionConfig: ActionConfig = ActionConfig.none

    // MARK: - Computed Properties

    /// Returns true when the divider's effective color is dark (relative luminance < 0.45),
    /// allowing preview wells to automatically render a contrasting light backdrop.
    var isDarkLuminance: Bool {
        guard style != .image && style != .spacer else { return false }
        switch colorPreset {
        case .adaptiveWhite:
            return false
        case .dark:
            return true
        case .custom:
            let luminance = 0.2126 * customRed + 0.7152 * customGreen + 0.0722 * customBlue
            return luminance < 0.45
        }
    }

    /// Returns true when a Spacer has a Tooltip or Click Action configured,
    /// which requires synthesizing a full-width `.app` bundle instead of a native `.dockspace` tile.
    var requiresAppBundleForSpacer: Bool {
        !hoverLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || actionConfig.actionType != .none
    }

    /// Copy that is safe to embed in a generated bundle.
    ///
    /// Custom artwork is written once as `Resources/CustomImage.png`; embedding
    /// the same bytes again inside `DividerModel.json` would roughly double the
    /// bundle size.
    nonisolated func withoutEmbeddedImageData() -> DividerModel {
        var copy = self
        copy.imageData = nil
        return copy
    }

    // MARK: - Mutating Methods

    mutating func resetToNativeMatch() {
        style = .line
        orientation = DividerOrientation.currentSystemDockOrientation
        spacerSize = .regular
        colorPreset = .adaptiveWhite
        opacity = 0.80
        thickness = 1.5
        heightRatio = 0.65
        verticalOffset = 0.0
        hoverLabel = ""
        roundImageCorners = true
        imageCornerRadiusRatio = 0.225
    }

    // MARK: - Coding Keys & Initializer

    enum CodingKeys: String, CodingKey {
        case id
        case style
        case orientation
        case spacerSize
        case colorPreset
        case customRed
        case customGreen
        case customBlue
        case opacity
        case thickness
        case heightRatio
        case verticalOffset
        case hoverLabel
        case labelMode
        case labelText
        case isVerticalText
        case symbolName
        case imageData
        case imageID
        case roundImageCorners
        case imageCornerRadiusRatio
        case actionConfig
    }

    nonisolated init(
        id: UUID = UUID(),
        style: DividerStyle = .line,
        orientation: DividerOrientation = .vertical,
        spacerSize: SpacerSize = .regular,
        colorPreset: ColorPreset = .adaptiveWhite,
        customRed: Double = 1.0,
        customGreen: Double = 1.0,
        customBlue: Double = 1.0,
        opacity: Double = 0.80,
        thickness: Double = 1.5,
        heightRatio: Double = 0.65,
        verticalOffset: Double = 0.0,
        hoverLabel: String = "",
        labelMode: LabelMode = .text,
        labelText: String = "DEV",
        isVerticalText: Bool = false,
        symbolName: String = "star.fill",
        imageData: Data? = nil,
        imageID: UUID? = nil,
        roundImageCorners: Bool = true,
        imageCornerRadiusRatio: Double = 0.225,
        actionConfig: ActionConfig = ActionConfig.none
    ) {
        self.id = id
        self.style = style
        self.orientation = orientation
        self.spacerSize = spacerSize
        self.colorPreset = colorPreset
        self.customRed = customRed
        self.customGreen = customGreen
        self.customBlue = customBlue
        self.opacity = opacity
        self.thickness = thickness
        self.heightRatio = heightRatio
        self.verticalOffset = verticalOffset
        self.hoverLabel = hoverLabel
        self.labelMode = labelMode
        self.labelText = labelText
        self.isVerticalText = isVerticalText
        self.symbolName = symbolName
        self.imageData = imageData
        self.imageID = imageID
        self.roundImageCorners = roundImageCorners
        self.imageCornerRadiusRatio = imageCornerRadiusRatio
        self.actionConfig = actionConfig
    }
}

// MARK: - Explicit Nonisolated Codable Conformance

extension DividerModel {
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(style, forKey: .style)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(spacerSize, forKey: .spacerSize)
        try container.encode(colorPreset, forKey: .colorPreset)
        try container.encode(customRed, forKey: .customRed)
        try container.encode(customGreen, forKey: .customGreen)
        try container.encode(customBlue, forKey: .customBlue)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(thickness, forKey: .thickness)
        try container.encode(heightRatio, forKey: .heightRatio)
        try container.encode(verticalOffset, forKey: .verticalOffset)
        try container.encode(hoverLabel, forKey: .hoverLabel)
        try container.encode(labelMode, forKey: .labelMode)
        try container.encode(labelText, forKey: .labelText)
        try container.encode(isVerticalText, forKey: .isVerticalText)
        try container.encode(symbolName, forKey: .symbolName)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encodeIfPresent(imageID, forKey: .imageID)
        try container.encode(roundImageCorners, forKey: .roundImageCorners)
        try container.encode(imageCornerRadiusRatio, forKey: .imageCornerRadiusRatio)
        try container.encode(actionConfig, forKey: .actionConfig)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.style = try container.decodeIfPresent(DividerStyle.self, forKey: .style) ?? .line
        self.orientation = try container.decodeIfPresent(DividerOrientation.self, forKey: .orientation) ?? .vertical
        self.spacerSize = try container.decodeIfPresent(SpacerSize.self, forKey: .spacerSize) ?? .regular
        self.colorPreset = try container.decodeIfPresent(ColorPreset.self, forKey: .colorPreset) ?? .adaptiveWhite
        self.customRed = try container.decodeIfPresent(Double.self, forKey: .customRed) ?? 1.0
        self.customGreen = try container.decodeIfPresent(Double.self, forKey: .customGreen) ?? 1.0
        self.customBlue = try container.decodeIfPresent(Double.self, forKey: .customBlue) ?? 1.0
        self.opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.80
        self.thickness = try container.decodeIfPresent(Double.self, forKey: .thickness) ?? 1.5
        self.heightRatio = try container.decodeIfPresent(Double.self, forKey: .heightRatio) ?? 0.65
        self.verticalOffset = try container.decodeIfPresent(Double.self, forKey: .verticalOffset) ?? 0.0
        self.hoverLabel = try container.decodeIfPresent(String.self, forKey: .hoverLabel) ?? ""
        self.labelMode = try container.decodeIfPresent(LabelMode.self, forKey: .labelMode) ?? .text
        self.labelText = try container.decodeIfPresent(String.self, forKey: .labelText) ?? "DEV"
        self.isVerticalText = try container.decodeIfPresent(Bool.self, forKey: .isVerticalText) ?? false
        self.symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "star.fill"
        self.imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        self.imageID = try container.decodeIfPresent(UUID.self, forKey: .imageID)
        if self.imageID == nil, self.imageData != nil {
            self.imageID = UUID()
        }
        self.roundImageCorners = try container.decodeIfPresent(Bool.self, forKey: .roundImageCorners) ?? true
        self.imageCornerRadiusRatio = try container.decodeIfPresent(Double.self, forKey: .imageCornerRadiusRatio) ?? 0.225
        self.actionConfig = try container.decodeIfPresent(ActionConfig.self, forKey: .actionConfig) ?? ActionConfig.none
    }
}
