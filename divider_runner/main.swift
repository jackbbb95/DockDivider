//
//  main.swift
//  divider_runner
//
//  Created by Jack Bogle on 10/27/26.
//
//  ActionType, SystemActionType, and ActionConfig come from the shared
//  `Shared/ActionConfig.swift` source compiled into both DockDivider and
//  divider_runner, so the generated helper and the editor can never drift.
//

import Foundation
import AppKit
import OSLog

/// Kept in sync with `BundleMarker.currentRunnerVersion`. The app uses the
/// marker to decide whether an existing divider needs a runner upgrade.
let runnerVersion = "2"

let logger = Logger(subsystem: "me.bogle.DockDivider.runner", category: "actions")

// MARK: - Launch Helpers

/// Submits a launch request to LaunchServices and exits. The runner never
/// waits for the target app or URL to finish opening.
func openURL(_ url: URL) {
    if !NSWorkspace.shared.open(url) {
        logger.error("Unable to open \(url.absoluteString, privacy: .public)")
    }
}

/// Starts a child process and deliberately does not wait for it. Long-running
/// shell commands, Shortcuts, and utilities must not keep the helper alive.
func launchDetached(
    _ executablePath: String,
    arguments: [String],
    workingDirectory: URL? = nil
) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    if let workingDirectory {
        process.currentDirectoryURL = workingDirectory
    }
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
    } catch {
        logger.error("Unable to launch \(executablePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}

func runAppleScript(_ lines: [String]) {
    var arguments: [String] = []
    for line in lines {
        arguments.append("-e")
        arguments.append(line)
    }
    launchDetached("/usr/bin/osascript", arguments: arguments)
}

func resolvedURL(forPathOrURL value: String) -> URL? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if trimmed.hasPrefix("file://"), let parsed = URL(string: trimmed) {
        return parsed
    }
    if let parsed = URL(string: trimmed), parsed.scheme != nil {
        return parsed
    }
    return URL(fileURLWithPath: trimmed)
}

func emptyHomeTrash() {
    let trashURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".Trash", isDirectory: true)

    guard let items = try? FileManager.default.contentsOfDirectory(
        at: trashURL,
        includingPropertiesForKeys: nil
    ) else {
        logger.error("Unable to list the Trash.")
        return
    }

    for item in items {
        do {
            try FileManager.default.removeItem(at: item)
        } catch {
            logger.error("Unable to remove \(item.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

func confirmEmptyTrash() -> Bool {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    if #available(macOS 14.0, *) {
        application.activate()
    } else {
        application.activate(ignoringOtherApps: true)
    }

    let alert = NSAlert()
    alert.messageText = "Empty the Trash?"
    alert.informativeText = "This permanently deletes everything in the Trash. This cannot be undone."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Empty Trash")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
}

// MARK: - Main Execution

// `--version` is used by the app and by tests. Keep the output stable.
if CommandLine.arguments.contains("--version") {
    print("divider_runner \(runnerVersion)")
    exit(0)
}

// 1. Locate own bundle Resources/ActionConfig.json
guard let execURL = Bundle.main.executableURL else { exit(0) }
let bundleURL = execURL.deletingLastPathComponent().deletingLastPathComponent()
let configURL = bundleURL.appendingPathComponent("Resources/ActionConfig.json")

guard let data = try? Data(contentsOf: configURL),
      let config = try? JSONDecoder().decode(ActionConfig.self, from: data) else {
    logger.error("Missing or unreadable ActionConfig.json")
    exit(0)
}

logger.info("Executing action \(config.actionType.rawValue, privacy: .public)")

// 2. Execute configured action
switch config.actionType {
case .none:
    exit(0)

case .openAppsAndURLs:
    for pathOrURL in config.appBundleURLs {
        guard let url = resolvedURL(forPathOrURL: pathOrURL) else { continue }
        openURL(url)
    }

    for rawURL in config.webURLs {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let urlString = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        if let url = URL(string: urlString) {
            openURL(url)
        }
    }

case .systemAction:
    switch config.systemAction {
    case .hideOthers:
        NSWorkspace.shared.hideOtherApplications()

    case .startScreensaver:
        openURL(URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))

    case .screenshot:
        openURL(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))

    case .openTrash:
        openURL(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))

    case .emptyTrash:
        if confirmEmptyTrash() {
            emptyHomeTrash()
        }

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
        openURL(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))

    case .launchpad:
        let launchpadURL = URL(fileURLWithPath: "/System/Applications/Launchpad.app")
        if FileManager.default.fileExists(atPath: launchpadURL.path) {
            openURL(launchpadURL)
        } else {
            logger.error("Launchpad is not available on this version of macOS.")
        }

    case .activityMonitor:
        openURL(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))

    case .colorMeter:
        openURL(URL(fileURLWithPath: "/System/Applications/Utilities/Digital Color Meter.app"))

    case .clearClipboard:
        NSPasteboard.general.clearContents()

    case .sleepDisplays:
        launchDetached("/usr/bin/pmset", arguments: ["displaysleepnow"])

    case .openDownloads:
        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            openURL(downloadsURL)
        }

    case .openAirDrop:
        let airdropURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")
        if FileManager.default.fileExists(atPath: airdropURL.path) {
            openURL(airdropURL)
        } else {
            logger.error("AirDrop is not available in Finder on this version of macOS.")
        }
    }

case .runShortcut:
    let trimmed = config.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { break }

    let shortcutsCLI = "/usr/bin/shortcuts"
    if FileManager.default.isExecutableFile(atPath: shortcutsCLI) {
        launchDetached(shortcutsCLI, arguments: ["run", trimmed])
    } else if let encodedName = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "shortcuts://run-shortcut?name=\(encodedName)") {
        openURL(url)
    }

case .shellCommand:
    let command = config.shellCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !command.isEmpty else { break }

    if config.runInTerminal {
        let tempDirectory = FileManager.default.temporaryDirectory
        let scriptURL = tempDirectory.appendingPathComponent(
            "dockdivider-\(UUID().uuidString.prefix(8)).command"
        )

        // The script removes itself before running the user's command so
        // temporary launchers never accumulate in /tmp.
        let scriptContent = """
        #!/bin/zsh
        rm -f -- "$0"
        cd "$HOME" || true
        \(command)
        exec zsh
        """

        guard (try? scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)) != nil else {
            logger.error("Unable to write the temporary terminal script.")
            break
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let defaultHandler = NSWorkspace.shared.urlForApplication(toOpen: scriptURL)
        let terminalURL = defaultHandler ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")

        if FileManager.default.fileExists(atPath: terminalURL.path) {
            NSWorkspace.shared.open(
                [scriptURL],
                withApplicationAt: terminalURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                if let error {
                    logger.error("Unable to open the terminal: \(error.localizedDescription, privacy: .public)")
                }
            }
        } else {
            openURL(scriptURL)
        }
    } else {
        launchDetached(
            "/bin/zsh",
            arguments: ["-c", command],
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }
}

exit(0)
