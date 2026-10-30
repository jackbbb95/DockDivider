//
//  AppState.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import Foundation
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published State

    @Published var draft: DividerModel = DividerModel()
    @Published private(set) var stagedAppURL: URL?
    @Published private(set) var isStaging: Bool = false
    @Published var lastError: String? = nil
    @Published private(set) var customStorageURL: URL? = nil

    // MARK: - Private Properties

    private static let storageBookmarkKey = "DockDivider.customStorageBookmark"
    private var isStagedBundleConsumed: Bool = false
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    var effectiveStorageDirectory: URL {
        if let customStorageURL = customStorageURL {
            return customStorageURL
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("DockDividers", isDirectory: true)
    }

    var storageDisplayPath: String {
        (effectiveStorageDirectory.path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - Initialization & Lifecycle

    init() {
        restoreCustomStorageBookmark()
        repairExistingDividerBundles()

        $draft
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.stageImmediately()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.repairExistingDividerBundles()
                }
            }
            .store(in: &cancellables)

        DispatchQueue.main.async { [weak self] in
            self?.stageImmediately()
        }
    }

    // MARK: - Storage Directory Management

    private func restoreCustomStorageBookmark() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: Self.storageBookmarkKey) else {
            return
        }
        var isStale = false
        var resolvedURL: URL?

        if let url = try? URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            resolvedURL = url
        } else if let url = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            resolvedURL = url
        }

        guard let url = resolvedURL else {
            UserDefaults.standard.removeObject(forKey: Self.storageBookmarkKey)
            return
        }

        _ = url.startAccessingSecurityScopedResource()
        customStorageURL = url

        if isStale {
            let newBookmark = (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
                ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
            if let newBookmark = newBookmark {
                UserDefaults.standard.set(newBookmark, forKey: Self.storageBookmarkKey)
            }
        }
    }

    func selectStorageDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose a folder to store generated Dock Divider apps (e.g. ~/Applications/DockDividers)"
        panel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first

        if panel.runModal() == .OK, let url = panel.url {
            updateCustomStorageURL(url)
        }
    }

    func resetStorageDirectory() {
        updateCustomStorageURL(nil)
    }

    func updateCustomStorageURL(_ url: URL?) {
        customStorageURL?.stopAccessingSecurityScopedResource()
        if let url = url {
            _ = url.startAccessingSecurityScopedResource()
            let bookmark = (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
                ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
            if let bookmark = bookmark {
                UserDefaults.standard.set(bookmark, forKey: Self.storageBookmarkKey)
            }
            customStorageURL = url
        } else {
            UserDefaults.standard.removeObject(forKey: Self.storageBookmarkKey)
            customStorageURL = nil
        }
        stageImmediately()
    }

    func revealStorageDirectoryInFinder() {
        try? FileManager.default.createDirectory(at: effectiveStorageDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: effectiveStorageDirectory.path)
    }

    // MARK: - Bundle Staging & Drag Lifecycle

    func stageImmediately() {
        let previousURL = (!isStagedBundleConsumed) ? stagedAppURL : nil

        // When in Blank Spacer mode with no click action and no custom hover tooltip,
        // fit native .dockspace / .docksmallspace / .dockflexspace trigger file so
        // Dock.app creates a true DOCKSpacerTile (zero tooltip bubble and zero clickability).
        let isPassiveNativeSpacer = (draft.style == .spacer)
            && (draft.actionConfig.actionType == .none)
            && draft.hoverLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if isPassiveNativeSpacer {
            do {
                let newURL = try BundleSynthesizer.createNativeSpacerFile(
                    size: draft.spacerSize,
                    outputDirectory: effectiveStorageDirectory
                )
                if let previousURL = previousURL, previousURL != newURL {
                    try? FileManager.default.removeItem(at: previousURL)
                }
                DispatchQueue.main.async {
                    if self.stagedAppURL != newURL {
                        self.stagedAppURL = newURL
                    }
                    self.isStagedBundleConsumed = false
                    if self.lastError != nil {
                        self.lastError = nil
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    if self.lastError != error.localizedDescription {
                        self.lastError = error.localizedDescription
                    }
                }
            }
            return
        }

        guard let iconData = IconRenderer.renderIconData(for: draft) else {
            DispatchQueue.main.async {
                if self.lastError != "Failed to render icon data" {
                    self.lastError = "Failed to render icon data"
                }
            }
            return
        }

        // Use 256x256 pt (@2x = 512x512 px) for NSWorkspace.shared.setIcon so IconServices
        // never attempts to encode an invalid 1024x1024 @1x (2048px) slot
        let previewImage = IconRenderer.renderNSImage(for: draft, size: CGSize(width: 256, height: 256))

        do {
            let newURL = try BundleSynthesizer.createDividerApp(
                iconData: iconData,
                previewImage: previewImage,
                config: draft.actionConfig,
                hoverLabel: draft.hoverLabel,
                model: draft,
                outputDirectory: effectiveStorageDirectory
            )
            if let previousURL = previousURL, previousURL != newURL {
                try? FileManager.default.removeItem(at: previousURL)
            }
            DispatchQueue.main.async {
                if self.stagedAppURL != newURL {
                    self.stagedAppURL = newURL
                }
                self.isStagedBundleConsumed = false
                if self.lastError != nil {
                    self.lastError = nil
                }
            }
        } catch {
            DispatchQueue.main.async {
                if self.lastError != error.localizedDescription {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func consumeStagedBundleForDrag() -> URL? {
        if stagedAppURL == nil || isStagedBundleConsumed || !FileManager.default.fileExists(atPath: stagedAppURL?.path ?? "") {
            stageImmediately()
        }
        guard let urlToDrag = stagedAppURL else {
            return nil
        }

        isStagedBundleConsumed = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.stageImmediately()
        }

        return urlToDrag
    }

    // MARK: - Bundle Maintenance & Repair

    private func repairExistingDividerBundles() {
        var directoriesToRepair: [URL] = [effectiveStorageDirectory]
        let homeDir = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let legacySandboxDir = homeDir
            .appendingPathComponent("Library/Containers/me.bogle.DockDivider/Data/Library/Application Support/DockDividers", isDirectory: true)
        if legacySandboxDir.path != effectiveStorageDirectory.path {
            directoriesToRepair.append(legacySandboxDir)
        }
        BundleSynthesizer.repairExistingBundles(in: directoriesToRepair, excluding: stagedAppURL)
    }
}
