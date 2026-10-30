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
    @State private var availableShortcuts: [String] = []
    @State private var isLoadingShortcuts: Bool = false

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
                VStack(alignment: .leading, spacing: 4) {
                    TextField("https://example.com, https://github.com", text: Binding(
                        get: {
                            config.webURLs.joined(separator: ", ")
                        },
                        set: { newValue in
                            config.webURLs = newValue
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Text("Multiple URLs can be separated by commas.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var systemActionSection: some View {
        SettingsLabeledRow("Action:") {
            Picker("System Action", selection: $config.systemAction) {
                ForEach(SystemActionType.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .labelsHidden()
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

                    Button {
                        loadUserShortcuts()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh Shortcuts List")
                }
            } else {
                HStack(spacing: 6) {
                    TextField("e.g. Toggle Focus Mode", text: $config.shortcutName)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        loadUserShortcuts()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh Shortcuts List")
                }
            }
        }
        .onAppear {
            loadUserShortcuts()
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
                Toggle("Open in Terminal window", isOn: $config.runInTerminal)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Shortcuts Loader

    private func loadUserShortcuts() {
        let shortcutsCLI = "/usr/bin/shortcuts"
        guard FileManager.default.isExecutableFile(atPath: shortcutsCLI) else { return }

        DispatchQueue.main.async {
            self.isLoadingShortcuts = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shortcutsCLI)
            process.arguments = ["list"]
            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = Pipe()

            var loaded: [String] = []
            if (try? process.run()) != nil {
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if let output = String(data: data, encoding: .utf8) {
                    loaded = output
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
            }

            DispatchQueue.main.async {
                self.availableShortcuts = loaded
                self.isLoadingShortcuts = false
            }
        }
    }

    // MARK: - App Row & Picker

    private func appRow(for appURLString: String) -> some View {
        let fileURL = (URL(string: appURLString)?.standardizedFileURL ?? URL(fileURLWithPath: appURLString)).standardizedFileURL
        let displayName = fileURL.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)

        return HStack(spacing: 8) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)

            Text(displayName.isEmpty ? appURLString : displayName)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            Button {
                config.appBundleURLs.removeAll(where: { $0 == appURLString })
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove application")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
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
