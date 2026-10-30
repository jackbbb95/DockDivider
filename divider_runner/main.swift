//
//  main.swift
//  divider_runner
//
//  Created by Jack Bogle on 10/27/26.
//
//  ActionType, SystemActionType, and ActionConfig in this file mirror
//  DockDivider/Generator/ActionConfig.swift so divider_runner compiles
//  as a standalone, zero-dependency Mach-O binary embedded inside each
//  synthesized divider .app bundle.
//

import Foundation
import AppKit

// MARK: - Action Models (Mirrored from ActionConfig.swift)

enum ActionType: String, CaseIterable, Identifiable, Codable {
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

enum SystemActionType: String, CaseIterable, Identifiable, Codable {
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

struct ActionConfig: Codable, Equatable {
    var actionType: ActionType = .none
    var appBundleURLs: [String] = []
    var webURLs: [String] = []
    var systemAction: SystemActionType = .hideOthers
    var shortcutName: String = ""
    var shellCommand: String = ""
    var runInTerminal: Bool = false

    static let none = ActionConfig()

    enum CodingKeys: String, CodingKey {
        case actionType
        case appBundleURLs
        case webURLs
        case systemAction
        case shortcutName
        case shellCommand
        case runInTerminal
    }

    init(
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

    init(from decoder: Decoder) throws {
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

// MARK: - Helpers

func openApplicationAndWait(at appURL: URL, in group: DispatchGroup) {
    group.enter()
    NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
        group.leave()
    }
}

func runAppleScript(_ lines: [String]) {
    let scriptProcess = Process()
    scriptProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    var args: [String] = []
    for line in lines {
        args.append("-e")
        args.append(line)
    }
    scriptProcess.arguments = args
    scriptProcess.standardOutput = Pipe()
    scriptProcess.standardError = Pipe()
    try? scriptProcess.run()
    scriptProcess.waitUntilExit()
}

// MARK: - Main Execution

// 1. Locate own bundle Resources/ActionConfig.json
guard let execURL = Bundle.main.executableURL else { exit(0) }
let bundleURL = execURL.deletingLastPathComponent().deletingLastPathComponent()
let configURL = bundleURL.appendingPathComponent("Resources/ActionConfig.json")

guard let data = try? Data(contentsOf: configURL),
      let config = try? JSONDecoder().decode(ActionConfig.self, from: data) else {
    exit(0)
}

let group = DispatchGroup()

// 2. Execute configured action
switch config.actionType {
case .none:
    exit(0)

case .openAppsAndURLs:
    for pathOrURL in config.appBundleURLs {
        let trimmed = pathOrURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let url: URL
        if trimmed.hasPrefix("file://"), let parsed = URL(string: trimmed) {
            url = parsed
        } else if let parsed = URL(string: trimmed), parsed.scheme != nil {
            url = parsed
        } else {
            url = URL(fileURLWithPath: trimmed)
        }

        openApplicationAndWait(at: url, in: group)
    }

    for rawURL in config.webURLs {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let urlStr = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

case .systemAction:
    switch config.systemAction {
    case .hideOthers:
        NSWorkspace.shared.hideOtherApplications()

    case .startScreensaver:
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        openApplicationAndWait(at: url, in: group)

    case .screenshot:
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        openApplicationAndWait(at: url, in: group)

    case .openTrash:
        runAppleScript([
            "tell application \"Finder\"",
            "open trash",
            "activate",
            "end tell"
        ])

    case .emptyTrash:
        runAppleScript([
            "tell application \"Finder\"",
            "empty trash",
            "end tell"
        ])

    case .toggleDarkMode:
        runAppleScript([
            "tell application \"System Events\"",
            "tell appearance preferences",
            "set dark mode to not dark mode",
            "end tell",
            "end tell"
        ])

    case .toggleMute:
        runAppleScript([
            "set volume output muted (not (output muted of (get volume settings)))"
        ])

    case .missionControl:
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        openApplicationAndWait(at: url, in: group)

    case .launchpad:
        let url = URL(fileURLWithPath: "/System/Applications/Launchpad.app")
        openApplicationAndWait(at: url, in: group)

    case .activityMonitor:
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        openApplicationAndWait(at: url, in: group)

    case .colorMeter:
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Digital Color Meter.app")
        openApplicationAndWait(at: url, in: group)

    case .clearClipboard:
        NSPasteboard.general.clearContents()

    case .sleepDisplays:
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
        process.waitUntilExit()

    case .openDownloads:
        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(downloadsURL)
        }

    case .openAirDrop:
        let airdropAppURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")
        if FileManager.default.fileExists(atPath: airdropAppURL.path) {
            openApplicationAndWait(at: airdropAppURL, in: group)
        } else {
            runAppleScript([
                "tell application \"Finder\"",
                "activate",
                "tell application \"System Events\" to keystroke \"R\" using {command down, shift down}",
                "end tell"
            ])
        }
    }

case .runShortcut:
    let trimmed = config.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
        let shortcutsCLI = "/usr/bin/shortcuts"
        if FileManager.default.isExecutableFile(atPath: shortcutsCLI) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shortcutsCLI)
            process.arguments = ["run", trimmed]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
        } else if let encodedName = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "shortcuts://run-shortcut?name=\(encodedName)") {
            NSWorkspace.shared.open(url)
        }
    }

case .shellCommand:
    let cmd = config.shellCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cmd.isEmpty else { break }

    if config.runInTerminal {
        // Create a temporary executable .command script
        let tempDir = FileManager.default.temporaryDirectory
        let scriptFileName = "dockdivider-\(UUID().uuidString.prefix(8)).command"
        let scriptURL = tempDir.appendingPathComponent(scriptFileName)

        let scriptContent = """
        #!/bin/zsh
        \(cmd)
        exec zsh
        """

        if (try? scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)) != nil {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            // Resolve user's default terminal:
            // 1. Check LaunchServices for default handler of .command files
            // 2. If Ghostty is installed, prioritize it as the default modern terminal
            let targetTerminalURL: URL? = {
                if let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: scriptURL) {
                    return defaultAppURL
                }
                if let ghosttyURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") {
                    return ghosttyURL
                }
                if FileManager.default.fileExists(atPath: "/Applications/Ghostty.app") {
                    return URL(fileURLWithPath: "/Applications/Ghostty.app")
                }
                return URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            }()

            group.enter()
            if let appURL = targetTerminalURL {
                NSWorkspace.shared.open([scriptURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                    group.leave()
                }
            } else {
                NSWorkspace.shared.open(scriptURL)
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                    group.leave()
                }
            }
        }
    } else {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", cmd]
        try? process.run()
        process.waitUntilExit()
    }
}

_ = group.wait(timeout: .now() + 3.0)
exit(0)
