//
//  StorageCleanupView.swift
//  DockDivider
//

import SwiftUI
import Foundation

/// Confirmation-based cleanup for generated dividers that are no longer
/// referenced by the Dock. Nothing is removed until the user presses the
/// destructive button and confirms.
struct StorageCleanupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var census: StorageCensus?
    @State private var isLoading = true
    @State private var isCleaning = false
    @State private var errorMessage: String?
    @State private var showingConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Group {
                if isLoading {
                    ProgressView("Scanning storage…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let census {
                    censusContent(census)
                } else {
                    Text("Unable to read the storage folder.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()
            footer
        }
        .padding(18)
        .frame(width: 560, height: 470)
        .task { await loadCensus() }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $showingConfirmation
        ) {
            Button("Move to Trash", role: .destructive) {
                Task { await cleanUp() }
            }
        } message: {
            Text("Divider bundles currently in your Dock are never removed. You can restore deleted items from the Trash.")
        }
        .alert(
            "Cleanup Failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Storage Cleanup")
                    .font(.headline)
                Text(appState.storageDisplayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Reveal in Finder") {
                appState.revealStorageDirectoryInFinder()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    // MARK: - Census Content

    @ViewBuilder
    private func censusContent(_ census: StorageCensus) -> some View {
        if !census.liveSetAvailable {
            warningCard(
                systemImage: "exclamationmark.triangle",
                title: "Dock configuration unavailable",
                message: "DockDivider could not read which dividers are currently in your Dock. Cleanup is disabled to avoid deleting a divider that is still in use."
            )
        } else if census.items.isEmpty {
            emptyState
        } else {
            Text(summaryText(for: census))
                .font(.callout)
                .foregroundStyle(.secondary)

            if census.unusedItems.isEmpty {
                warningCard(
                    systemImage: "checkmark.circle",
                    title: "Nothing to clean up",
                    message: "Every item in this folder is referenced by your Dock or was created moments ago."
                )
            } else {
                List(census.unusedItems) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.kind == .appBundle ? "app" : "rectangle.dashed")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.displayName)
                                .lineLimit(1)
                            Text(detailText(for: item))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Text(item.sizeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 1)
                }
                .listStyle(.inset)

                Text("Items created in the last minute are excluded so a divider you just dragged is never offered for cleanup.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailText(for item: StorageItem) -> String {
        guard item.kind == .appBundle else {
            return item.url.lastPathComponent
        }
        guard let createdAt = item.createdAt else {
            return "Generated divider"
        }
        let date = createdAt.formatted(date: .abbreviated, time: .shortened)
        return "Generated \(date)"
    }

    private func summaryText(for census: StorageCensus) -> String {
        let totalSize = ByteCountFormatter.string(fromByteCount: census.totalBytes, countStyle: .file)
        if census.unusedItems.isEmpty {
            return "\(census.items.count) managed items use \(totalSize)."
        }
        let unusedSize = ByteCountFormatter.string(fromByteCount: census.unusedBytes, countStyle: .file)
        return "\(census.items.count) managed items use \(totalSize). \(census.unusedItems.count) items (\(unusedSize)) are not referenced by the Dock."
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("No generated dividers found")
                .font(.headline)
            Text("Drag a divider into the Dock and it will appear here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func warningCard(systemImage: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(systemImage == "checkmark.circle" ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if isCleaning {
                ProgressView()
                    .controlSize(.small)
                Text("Moving items to the Trash…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            if let census, census.liveSetAvailable, !census.unusedItems.isEmpty {
                Button("Move \(census.unusedItems.count) to Trash…", role: .destructive) {
                    showingConfirmation = true
                }
                .disabled(isCleaning)
            }
        }
    }

    private var confirmationTitle: String {
        let count = census?.unusedItems.count ?? 0
        return "Move \(count) item\(count == 1 ? "" : "s") to the Trash?"
    }

    // MARK: - Actions

    private func loadCensus() async {
        isLoading = true
        let result = await appState.loadStorageCensus()
        census = result
        isLoading = false
    }

    private func cleanUp() async {
        guard let census else { return }
        isCleaning = true
        defer { isCleaning = false }

        do {
            try await appState.cleanUpStorage(census.unusedItems)
            await loadCensus()
        } catch {
            errorMessage = error.localizedDescription
            await loadCensus()
        }
    }
}
