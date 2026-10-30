//
//  ActionConfig.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import Foundation

// MARK: - Action Enums

nonisolated enum ActionType: String, CaseIterable, Identifiable, Codable, Sendable {
    case none = "none"
    case openAppsAndURLs = "openAppsAndURLs"
    case systemAction = "systemAction"
    case runShortcut = "runShortcut"
    case shellCommand = "shellCommand"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "Do Nothing (Silent)"
        case .openAppsAndURLs: return "Launch Apps & URLs"
        case .systemAction: return "System Utility Action"
        case .runShortcut: return "Run Apple Shortcut"
        case .shellCommand: return "Run Shell Command"
        }
    }
}

nonisolated enum SystemActionType: String, CaseIterable, Identifiable, Codable, Sendable {
    case hideOthers = "hideOthers"
    case startScreensaver = "startScreensaver"
    case screenshot = "screenshot"
    case openTrash = "openTrash"
    case emptyTrash = "emptyTrash"
    case toggleDarkMode = "toggleDarkMode"
    case toggleMute = "toggleMute"
    case missionControl = "missionControl"
    case launchpad = "launchpad"
    case activityMonitor = "activityMonitor"
    case colorMeter = "colorMeter"
    case clearClipboard = "clearClipboard"
    case sleepDisplays = "sleepDisplays"
    case openDownloads = "openDownloads"
    case openAirDrop = "openAirDrop"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hideOthers: return "Hide All Other Apps"
        case .startScreensaver: return "Start Screensaver / Lock"
        case .screenshot: return "Open Screenshot Utility"
        case .openTrash: return "Open Trash"
        case .emptyTrash: return "Empty Trash"
        case .toggleDarkMode: return "Toggle Dark Mode"
        case .toggleMute: return "Toggle Mute Audio"
        case .missionControl: return "Launch Mission Control"
        case .launchpad: return "Launchpad"
        case .activityMonitor: return "Activity Monitor"
        case .colorMeter: return "Digital Color Meter"
        case .clearClipboard: return "Clear Clipboard"
        case .sleepDisplays: return "Sleep Displays"
        case .openDownloads: return "Open Downloads"
        case .openAirDrop: return "Open AirDrop"
        }
    }
}

// MARK: - ActionConfig Model

nonisolated struct ActionConfig: Codable, Equatable, Sendable {
    var actionType: ActionType = .none
    var appBundleURLs: [String] = []
    var webURLs: [String] = []
    var systemAction: SystemActionType = .hideOthers
    var shortcutName: String = ""
    var shellCommand: String = ""
    var runInTerminal: Bool = false

    nonisolated static let none = ActionConfig()

    enum CodingKeys: String, CodingKey {
        case actionType
        case appBundleURLs
        case webURLs
        case systemAction
        case shortcutName
        case shellCommand
        case runInTerminal
    }

    nonisolated init(
        actionType: ActionType = .none,
        appBundleURLs: [String] = [],
        webURLs: [String] = [],
        systemAction: SystemActionType = .hideOthers,
        shortcutName: String = "",
        shellCommand: String = "",
        runInTerminal: Bool = false
    ) {
        self.actionType = actionType
        self.appBundleURLs = appBundleURLs
        self.webURLs = webURLs
        self.systemAction = systemAction
        self.shortcutName = shortcutName
        self.shellCommand = shellCommand
        self.runInTerminal = runInTerminal
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actionType, forKey: .actionType)
        try container.encode(appBundleURLs, forKey: .appBundleURLs)
        try container.encode(webURLs, forKey: .webURLs)
        try container.encode(systemAction, forKey: .systemAction)
        try container.encode(shortcutName, forKey: .shortcutName)
        try container.encode(shellCommand, forKey: .shellCommand)
        try container.encode(runInTerminal, forKey: .runInTerminal)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.actionType = try container.decodeIfPresent(ActionType.self, forKey: .actionType) ?? .none
        self.appBundleURLs = try container.decodeIfPresent([String].self, forKey: .appBundleURLs) ?? []
        self.webURLs = try container.decodeIfPresent([String].self, forKey: .webURLs) ?? []
        self.systemAction = try container.decodeIfPresent(SystemActionType.self, forKey: .systemAction) ?? .hideOthers
        self.shortcutName = try container.decodeIfPresent(String.self, forKey: .shortcutName) ?? ""
        self.shellCommand = try container.decodeIfPresent(String.self, forKey: .shellCommand) ?? ""
        self.runInTerminal = try container.decodeIfPresent(Bool.self, forKey: .runInTerminal) ?? false
    }
}
