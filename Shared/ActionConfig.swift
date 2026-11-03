//
//  ActionConfig.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import Foundation

// MARK: - Action Enums

enum ActionType: String, CaseIterable, Identifiable, Codable, Sendable {
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

enum SystemActionType: String, CaseIterable, Identifiable, Codable, Sendable {
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

    /// One-line explanation shown under the system action picker.
    nonisolated var detail: String {
        switch self {
        case .hideOthers: return "Hides every other app so the current app stays in front."
        case .startScreensaver: return "Starts the screen saver or locks the screen, depending on your settings."
        case .screenshot: return "Opens the macOS Screenshot utility."
        case .openTrash: return "Opens your Trash in Finder."
        case .emptyTrash: return "Permanently deletes everything in your Trash. This cannot be undone."
        case .toggleDarkMode: return "Switches between Light and Dark appearance."
        case .toggleMute: return "Mutes or unmutes the current output volume."
        case .missionControl: return "Shows all open windows and Spaces."
        case .launchpad: return "Opens Launchpad. Not available on every macOS release."
        case .activityMonitor: return "Opens Activity Monitor."
        case .colorMeter: return "Opens Digital Color Meter."
        case .clearClipboard: return "Removes the current contents of the clipboard."
        case .sleepDisplays: return "Puts the displays to sleep immediately."
        case .openDownloads: return "Opens your Downloads folder in Finder."
        case .openAirDrop: return "Opens AirDrop in Finder."
        }
    }

    /// Actions that require an app which may be absent on newer macOS
    /// releases. The editor hides these instead of offering a dead control.
    nonisolated var isAvailable: Bool {
        unavailableReason == nil
    }

    nonisolated var unavailableReason: String? {
        switch self {
        case .launchpad:
            guard !Self.exists(Self.launchpadPath) else { return nil }
            return "Launchpad is not included with this version of macOS."
        case .openAirDrop:
            guard !Self.exists(Self.airDropPath) else { return nil }
            return "AirDrop is not available in Finder on this version of macOS."
        default:
            return nil
        }
    }

    nonisolated static var availableCases: [SystemActionType] {
        allCases.filter(\.isAvailable)
    }

    private nonisolated static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    nonisolated static let launchpadPath = "/System/Applications/Launchpad.app"
    nonisolated static let airDropPath = "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app"
}

// MARK: - ActionConfig Model

struct ActionConfig: Codable, Equatable, Sendable {
    nonisolated static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var actionType: ActionType = .none
    var appBundleURLs: [String] = []
    var webURLs: [String] = []
    var systemAction: SystemActionType = .hideOthers
    var shortcutName: String = ""
    var shellCommand: String = ""
    var runInTerminal: Bool = false

    nonisolated static let none = ActionConfig()

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case actionType
        case appBundleURLs
        case webURLs
        case systemAction
        case shortcutName
        case shellCommand
        case runInTerminal
    }

    nonisolated init(
        schemaVersion: Int = ActionConfig.currentSchemaVersion,
        actionType: ActionType = .none,
        appBundleURLs: [String] = [],
        webURLs: [String] = [],
        systemAction: SystemActionType = .hideOthers,
        shortcutName: String = "",
        shellCommand: String = "",
        runInTerminal: Bool = false
    ) {
        self.schemaVersion = schemaVersion
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
        try container.encode(schemaVersion, forKey: .schemaVersion)
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
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        self.actionType = try container.decodeIfPresent(ActionType.self, forKey: .actionType) ?? .none
        self.appBundleURLs = try container.decodeIfPresent([String].self, forKey: .appBundleURLs) ?? []
        self.webURLs = try container.decodeIfPresent([String].self, forKey: .webURLs) ?? []
        self.systemAction = try container.decodeIfPresent(SystemActionType.self, forKey: .systemAction) ?? .hideOthers
        self.shortcutName = try container.decodeIfPresent(String.self, forKey: .shortcutName) ?? ""
        self.shellCommand = try container.decodeIfPresent(String.self, forKey: .shellCommand) ?? ""
        self.runInTerminal = try container.decodeIfPresent(Bool.self, forKey: .runInTerminal) ?? false
    }
}
