//
//  DividerValidation.swift
//  DockDivider
//

import Foundation

extension DividerModel {
    /// User-facing description of why this divider cannot work yet, if any.
    ///
    /// Validation is intentionally limited to conditions that produce a
    /// divider that silently does nothing. Appearance choices are always valid.
    var validationWarning: String? {
        if style == .image, imageData?.isEmpty != false {
            return "Choose an image before dragging this divider to the Dock."
        }

        switch actionConfig.actionType {
        case .none:
            return nil

        case .openAppsAndURLs:
            let hasApps = actionConfig.appBundleURLs.contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let hasURLs = actionConfig.webURLs.contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if !hasApps && !hasURLs {
                return "Add an app or web URL, or set Click Behavior to Do Nothing."
            }

        case .systemAction:
            if !actionConfig.systemAction.isAvailable {
                return actionConfig.systemAction.unavailableReason
                    ?? "Choose a system action that is available on this Mac."
            }

        case .runShortcut:
            if actionConfig.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Choose a Shortcut, or set Click Behavior to Do Nothing."
            }

        case .shellCommand:
            if actionConfig.shellCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Enter a shell command, or set Click Behavior to Do Nothing."
            }
        }

        return nil
    }
}
