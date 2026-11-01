//
//  MainWindowView.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import SwiftUI
import Foundation
import AppKit

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var activeSheet: MainSheet?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 20) {
                // Left Column: Controls & Configuration
                VStack(alignment: .leading, spacing: 14) {
                    StyleSelectorView(style: $appState.draft.style)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            // Card 1: Appearance & Dimensions
                            AppearanceControlsView(model: $appState.draft)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                                        )
                                )

                            // Card 2: Click Behavior
                            ClickActionPickerView(config: $appState.draft.actionConfig)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                                        )
                                )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                    }
                    .scrollIndicators(.automatic)
                }
                .frame(width: 440)

                Divider()

                // Right Column: Live Dock Preview & Drag Well
                VStack(spacing: 16) {
                    DockPreviewBar(model: $appState.draft)

                    DragWellView(model: appState.draft)
                }
                .frame(minWidth: 380, maxWidth: .infinity)
            }

            Divider()

            // Storage Location Bar
            storageLocationBar
        }
        .padding(18)
        .frame(minWidth: 920, idealWidth: 940, maxWidth: .infinity, minHeight: 620, idealHeight: 700, maxHeight: .infinity)
        .background(InitialFocusClearer())
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .onboarding:
                OnboardingView()
                    .environmentObject(appState)
            case .storageCleanup:
                StorageCleanupView()
                    .environmentObject(appState)
            }
        }
        .task {
            guard appState.isOnboardingPresented else { return }
            // Let the main window finish its first layout before presenting.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, appState.isOnboardingPresented else { return }
            activeSheet = .onboarding
        }
    }

    // MARK: - Storage Footer Bar

    private var storageLocationBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(appState.storageDisplayPath)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help("Folder where generated Dock Divider .app bundles are stored: \(appState.storageDisplayPath)")

            Text(appState.isUsingDefaultStorageLocation ? "Default" : "Custom")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(Color.secondary.opacity(0.12))
                )
                .accessibilityLabel(appState.isUsingDefaultStorageLocation ? "Default storage location" : "Custom storage location")

            if let warning = appState.storageLocationWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help(warning)
                    .accessibilityLabel(warning)
            }

            if let summary = appState.storageSummary {
                Text(ByteCountFormatter.string(fromByteCount: summary.totalBytes, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .help("Total disk usage of the generated dividers in this folder")
                    .accessibilityLabel("Divider storage size")
            }

            Spacer()

            Button("Clean Up…") {
                activeSheet = .storageCleanup
            }
            .buttonStyle(.link)
            .font(.caption2)
            .help("Review generated dividers that are no longer referenced by your Dock")
            .accessibilityLabel("Clean up unused dividers")

            Button("Change…") {
                appState.selectStorageDirectory()
            }
            .buttonStyle(.link)
            .font(.caption2)
            .help("Choose a different folder for generated dividers")
            .accessibilityLabel("Change storage folder")

            if appState.customStorageURL != nil {
                Button("Reset") {
                    appState.resetStorageDirectory()
                }
                .buttonStyle(.link)
                .font(.caption2)
                .help("Return to the default storage folder")
                .accessibilityLabel("Reset storage folder")
            }

            Button {
                appState.revealStorageDirectoryInFinder()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reveal Divider Storage Folder in Finder")
            .accessibilityLabel("Reveal storage folder in Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }
}

// MARK: - Sheets

private enum MainSheet: String, Identifiable {
    case onboarding
    case storageCleanup

    var id: String { rawValue }
}

// MARK: - Initial Focus

/// Clears the first responder SwiftUI installs on the window's first text
/// field. The window itself becomes the first responder, so typing does not
/// land in the tooltip field until the user clicks or tabs into a control.
private struct InitialFocusClearer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        InitialFocusClearerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class InitialFocusClearerView: NSView {
    private var didClearFocus = false
    private var becameKeyObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        becameKeyObserver.map(NotificationCenter.default.removeObserver)
        becameKeyObserver = nil

        guard !didClearFocus, let window else { return }

        if window.isKeyWindow {
            clearFocus(in: window)
        } else {
            becameKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window else { return }
                self.clearFocus(in: window)
            }
        }
    }

    private func clearFocus(in window: NSWindow) {
        guard !didClearFocus else { return }
        didClearFocus = true

        if let becameKeyObserver {
            NotificationCenter.default.removeObserver(becameKeyObserver)
            self.becameKeyObserver = nil
        }

        // SwiftUI installs its initial first responder during the window's
        // attach/appearance pass, after the key notification. A short delay
        // lands after that pass without being noticeable.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak window] in
            window?.makeFirstResponder(nil)
        }
    }

    deinit {
        becameKeyObserver.map(NotificationCenter.default.removeObserver)
    }
}
