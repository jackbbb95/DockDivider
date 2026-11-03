//
//  StorageLocationStore.swift
//  DockDivider
//

import Foundation
import AppKit
import Combine

/// Owns the user's chosen storage root and its security-scoped bookmark.
///
/// `AppState` coordinates staging and UI state; this type is the only place
/// that reads or writes the bookmark or manages security-scope lifetimes.
@MainActor
final class StorageLocationStore: ObservableObject {
    static let bookmarkKey = "DockDivider.customStorageBookmark"

    @Published private(set) var customStorageURL: URL?

    private var securityScopeToken: SecurityScopeToken?
    private let defaults: UserDefaults
    private let applicationSupportDirectory: URL

    init(userDefaults: UserDefaults, applicationSupportDirectory: URL) {
        self.defaults = userDefaults
        self.applicationSupportDirectory = applicationSupportDirectory
        restoreBookmark()
    }

    var effectiveStorageDirectory: URL {
        if let customStorageURL {
            return StorageLayout.effectiveDirectory(forSelectedRoot: customStorageURL)
        }
        return StorageLayout.effectiveDirectory(forSelectedRoot: applicationSupportDirectory)
    }

    var storageDisplayPath: String {
        (effectiveStorageDirectory.path as NSString).abbreviatingWithTildeInPath
    }

    /// True when bundles live in the default Application Support folder.
    var isUsingDefaultStorageLocation: Bool {
        customStorageURL == nil
    }

    /// Non-fatal warning shown when the chosen folder lives inside an app
    /// container, where removing the app could delete the Dock's backing files.
    var storageLocationWarning: String? {
        let path = StoragePath.canonical(effectiveStorageDirectory)
        let home = StoragePath.canonical(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
        let containerPrefix = home + "/Library/Containers/"
        guard path.hasPrefix(containerPrefix) else { return nil }
        return "This folder is inside an app container. Removing DockDivider could remove the bundles your Dock icons point to."
    }

    @discardableResult
    func selectStorageDirectory() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose a folder root. DockDivider creates a “DockDividers” subfolder inside it for generated apps."
        panel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }
        updateCustomStorageURL(url)
        return true
    }

    func resetStorageDirectory() {
        updateCustomStorageURL(nil)
    }

    func updateCustomStorageURL(_ url: URL?) {
        securityScopeToken = nil

        if let url {
            securityScopeToken = SecurityScopeToken(url)
            if let bookmark = Self.makeBookmark(for: url) {
                defaults.set(bookmark, forKey: Self.bookmarkKey)
            }
            customStorageURL = url
        } else {
            defaults.removeObject(forKey: Self.bookmarkKey)
            customStorageURL = nil
        }
    }

    func revealInFinder() {
        let directory = effectiveStorageDirectory
        StorageMaintenance.ensureReadme(in: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path)
    }

    private func restoreBookmark() {
        guard let bookmarkData = defaults.data(forKey: Self.bookmarkKey) else {
            return
        }

        var isStale = false
        var resolvedURL: URL?

        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            resolvedURL = url
        } else if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            resolvedURL = url
        }

        guard let url = resolvedURL else {
            defaults.removeObject(forKey: Self.bookmarkKey)
            return
        }

        securityScopeToken = SecurityScopeToken(url)
        customStorageURL = url

        if isStale {
            if let newBookmark = Self.makeBookmark(for: url) {
                defaults.set(newBookmark, forKey: Self.bookmarkKey)
            }
        }
    }

    /// Creates a security-scoped bookmark when the location supports it, and
    /// falls back to a plain bookmark otherwise.
    private static func makeBookmark(for url: URL) -> Data? {
        (try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) ?? (try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ))
    }
}

/// Automatically balances `startAccessingSecurityScopedResource` and `stopAccessingSecurityScopedResource`.
private final class SecurityScopeToken {
    private let url: URL

    init(_ url: URL) {
        self.url = url
        _ = url.startAccessingSecurityScopedResource()
    }

    deinit {
        url.stopAccessingSecurityScopedResource()
    }
}
