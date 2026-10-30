//
//  MainWindowView.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState

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
                    .scrollIndicators(.hidden)
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
        .frame(minWidth: 880, idealWidth: 900, maxWidth: .infinity, minHeight: 560, idealHeight: 600, maxHeight: .infinity)
    }

    // MARK: - Storage Footer Bar

    private var storageLocationBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(appState.storageDisplayPath)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help("Folder where generated Dock Divider .app bundles are stored: \(appState.storageDisplayPath)")

            Spacer()

            Button("Change...") {
                appState.selectStorageDirectory()
            }
            .buttonStyle(.link)
            .font(.caption2)

            if appState.customStorageURL != nil {
                Button("Reset") {
                    appState.resetStorageDirectory()
                }
                .buttonStyle(.link)
                .font(.caption2)
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }
}
