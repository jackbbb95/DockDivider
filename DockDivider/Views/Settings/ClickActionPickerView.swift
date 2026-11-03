//
//  ClickActionPickerView.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ClickActionPickerView: View {
    @Binding var config: ActionConfig
    @State private var availableShortcuts: [String] = ClickActionPickerView.cachedShortcuts ?? []
    @State private var isLoadingShortcuts: Bool = false
    @State private var shortcutLoadFailed: Bool = false
    @State private var pendingWebURL: String = ""
    @State private var webURLError: String?
    @State private var shellScriptError: String?

    private static var cachedShortcuts: [String]?
    private static var appIconCache: [String: NSImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Click Behavior (Optional)")
                .font(.headline)

            SettingsLabeledRow("When Clicked:") {
                Picker("When Clicked", selection: $config.actionType) {
                    ForEach(ActionType.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
            }

            switch config.actionType {
            case .none:
                EmptyView()

            case .openAppsAndURLs:
                appsAndURLsSection

            case .systemAction:
                systemActionSection

            case .runShortcut:
                shortcutSection

            case .shellCommand:
                shellCommandSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Subsections

    @ViewBuilder
    private var appsAndURLsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Applications
            SettingsLabeledRow("Applications:", alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if !config.appBundleURLs.isEmpty {
                        ForEach(config.appBundleURLs, id: \.self) { appURLString in
                            appRow(for: appURLString)
                        }
                    }

                    Button {
                        addApplications()
                    } label: {
                        Label("Add Application...", systemImage: "plus")
                    }
                }
            }

            // Web URLs
            SettingsLabeledRow("Web URLs:", alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if !config.webURLs.isEmpty {
                        ForEach(config.webURLs, id: \.self) { webURL in
                            webURLRow(for: webURL)
                        }
                    }

                    HStack(spacing: 6) {
                        TextField("https://example.com", text: $pendingWebURL)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                addWebURL()
                            }

                        Button("Add") {
                            addWebURL()
                        }
                        .disabled(pendingWebURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if let webURLError {
                        Text(webURLError)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Add one URL at a time. Missing schemes default to https://.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var systemActionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsLabeledRow("Action:") {
                Picker("System Action", selection: $config.systemAction) {
                    ForEach(SystemActionType.availableCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
            }

            Text(config.systemAction.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, SettingsLayout.labelWidth)
                .fixedSize(horizontal: false, vertical: true)

            if !config.systemAction.isAvailable {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(config.systemAction.unavailableReason ?? "This action is not available on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose Available Action") {
                        config.systemAction = SystemActionType.availableCases.first ?? .hideOthers
                    }
                    .font(.caption)
                }
            }

            if config.systemAction == .emptyTrash {
                Label(
                    "Empty Trash permanently deletes everything in the Trash the next time this divider is clicked.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var shortcutSection: some View {
        SettingsLabeledRow("Shortcut:") {
            if isLoadingShortcuts && availableShortcuts.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading shortcuts...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if !availableShortcuts.isEmpty {
                HStack(spacing: 6) {
                    Picker("Shortcut", selection: $config.shortcutName) {
                        if config.shortcutName.isEmpty {
                            Text("Select a Shortcut...").tag("")
                        } else if !availableShortcuts.contains(config.shortcutName) {
                            Text(config.shortcutName).tag(config.shortcutName)
                        }
                        ForEach(availableShortcuts, id: \.self) { shortcut in
                            Text(shortcut).tag(shortcut)
                        }
                    }
                    .labelsHidden()

                    shortcutRefreshButton
                }
            } else {
                HStack(spacing: 6) {
                    TextField("e.g. Toggle Focus Mode", text: $config.shortcutName)
                        .textFieldStyle(.roundedBorder)

                    shortcutRefreshButton
                }
            }
        }
        .onAppear {
            loadUserShortcuts()
        }

        if shortcutLoadFailed {
            Text("Couldn’t load the Shortcuts list. Enter the name manually or refresh.")
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(.leading, SettingsLayout.labelWidth)
        }
    }

    @ViewBuilder
    private var shellCommandSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsLabeledRow("Shell Command:", alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("e.g.\ncd ~/Projects/api\ngit pull && npm start", text: $config.shellCommand, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(size: 11, design: .monospaced))
                        .textFieldStyle(.roundedBorder)

                    Text(config.runInTerminal
                         ? "Opens in your default terminal and runs interactively."
                         : "Executed silently in the background via /bin/zsh -c.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsLabeledRow("") {
                HStack(spacing: 10) {
                    Button("Choose Script…") {
                        chooseShellScript()
                    }

                    Toggle("Open in Terminal window", isOn: $config.runInTerminal)
                        .font(.subheadline)
                }
            }

            if let shellScriptError {
                Text(shellScriptError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.leading, SettingsLayout.labelWidth)
            }
        }
    }

    // MARK: - Shortcuts Loader

    private var shortcutRefreshButton: some View {
        Button {
            loadUserShortcuts(force: true)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .help("Refresh Shortcuts List")
        .accessibilityLabel("Refresh Shortcuts list")
    }

    private func loadUserShortcuts(force: Bool = false) {
        if !force, let cached = Self.cachedShortcuts {
            if availableShortcuts != cached {
                availableShortcuts = cached
            }
            shortcutLoadFailed = false
            return
        }

        let shortcutsCLI = "/usr/bin/shortcuts"
        guard FileManager.default.isExecutableFile(atPath: shortcutsCLI) else {
            shortcutLoadFailed = true
            return
        }

        Task { @MainActor in
            isLoadingShortcuts = true
            shortcutLoadFailed = false

            let loaded = await Task.detached(priority: .utility) {
                Self.fetchShortcutNames(timeout: 5)
            }.value

            isLoadingShortcuts = false
            if let loaded {
                Self.cachedShortcuts = loaded
                availableShortcuts = loaded
                shortcutLoadFailed = false
            } else {
                shortcutLoadFailed = true
            }
        }
    }

    /// Runs `shortcuts list` off the main actor with a hard timeout. The runner
    /// action itself is detached; this list call is only for the editor.
    nonisolated private static func fetchShortcutNames(timeout: TimeInterval) -> [String]? {
        guard let result = BoundedProcess.run(
            executablePath: "/usr/bin/shortcuts",
            arguments: ["list"],
            timeout: timeout
        ), !result.timedOut else {
            return nil
        }

        return result.outputText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Web URLs

    private func addWebURL() {
        let trimmed = pendingWebURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            webURLError = "Enter a valid http or https URL."
            return
        }

        let normalized = url.absoluteString
        if !config.webURLs.contains(normalized) {
            config.webURLs.append(normalized)
        }
        pendingWebURL = ""
        webURLError = nil
    }

    private func webURLRow(for webURL: String) -> some View {
        SettingsRemovableRow(
            title: webURL,
            removeHelp: "Remove URL",
            removeAccessibilityLabel: "Remove \(webURL)",
            onRemove: {
                config.webURLs.removeAll(where: { $0 == webURL })
            }
        ) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shell Script Picker

    private func chooseShellScript() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "sh") ?? .plainText]
        panel.prompt = "Use Script"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            config.shellCommand = try String(contentsOf: url, encoding: .utf8)
            shellScriptError = nil
        } catch {
            shellScriptError = "DockDivider couldn’t read that script. Choose a UTF-8 text file."
        }
    }

    // MARK: - App Row & Picker

    private func appRow(for appURLString: String) -> some View {
        let fileURL = (URL(string: appURLString)?.standardizedFileURL ?? URL(fileURLWithPath: appURLString)).standardizedFileURL
        let displayName = fileURL.deletingPathExtension().lastPathComponent
        let icon = cachedAppIcon(for: fileURL.path)
        let title = displayName.isEmpty ? appURLString : displayName

        return SettingsRemovableRow(
            title: title,
            removeHelp: "Remove application",
            removeAccessibilityLabel: "Remove \(title)",
            onRemove: {
                config.appBundleURLs.removeAll(where: { $0 == appURLString })
            }
        ) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
        }
    }

    /// IconServices lookups are cheap but not free, and this view re-renders on
    /// every draft edit. Cache per application path for the session.
    private func cachedAppIcon(for path: String) -> NSImage {
        if let cached = Self.appIconCache[path] {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        Self.appIconCache[path] = icon
        return icon
    }

    private func addApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            for url in panel.urls {
                let absolute = url.absoluteString
                if !config.appBundleURLs.contains(absolute) {
                    config.appBundleURLs.append(absolute)
                }
            }
        }
    }
}
