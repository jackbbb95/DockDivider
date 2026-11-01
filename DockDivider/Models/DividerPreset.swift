//
//  DividerPreset.swift
//  DockDivider
//

import Foundation

/// A small set of starting points offered on first launch.
///
/// Presets change only the divider's look. A click action or tooltip already
/// configured by the user survives, so reopening onboarding can never wipe
/// behavior.
nonisolated enum DividerPreset: String, CaseIterable, Identifiable, Sendable {
    case line
    case dashed
    case dot
    case label
    case spacer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: return "Line"
        case .dashed: return "Dashed"
        case .dot: return "Dot"
        case .label: return "Label"
        case .spacer: return "Spacer"
        }
    }

    var systemImage: String {
        switch self {
        case .line: return "minus"
        case .dashed: return "ellipsis"
        case .dot: return "circle.fill"
        case .label: return "character.textbox"
        case .spacer: return "square.dashed"
        }
    }

    var resultingStyle: DividerStyle {
        switch self {
        case .line: return .line
        case .dashed: return .dashed
        case .dot: return .dot
        case .label: return .label
        case .spacer: return .spacer
        }
    }

    func apply(to model: inout DividerModel) {
        model.style = resultingStyle
        model.orientation = DividerOrientation.currentSystemDockOrientation
        model.colorPreset = .adaptiveWhite
        model.opacity = 0.80
        model.heightRatio = 0.65
        model.verticalOffset = 0.0

        switch self {
        case .line:
            model.thickness = 1.5
        case .dashed:
            model.thickness = 1.5
        case .dot:
            model.thickness = 3.0
        case .label:
            model.thickness = 1.5
            model.labelMode = .text
            model.labelText = "DEV"
            model.isVerticalText = false
        case .spacer:
            model.thickness = 1.5
        }
    }
}
