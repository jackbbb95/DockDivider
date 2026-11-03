//
//  BundleRepairer.swift
//  DockDivider
//

import Foundation

/// Chooses which storage folders need repair and runs the migration pass.
///
/// Repair is kept out of `AppState` so launch/activation behavior is easy to
/// test and change without touching staging or storage selection.
@MainActor
final class BundleRepairer {

    private let isEnabled: Bool
    private let minimumInterval: TimeInterval
    private let directoriesProvider: @MainActor (URL) -> [URL]
    private var lastRepairDirectoryPath: String?
    private var lastRepairDate: Date?
    private var isRepairing = false

    /// - Parameters:
    ///   - isEnabled: `false` in tests and when launch repair is disabled.
    ///   - minimumInterval: How long to trust a completed pass for the same
    ///     folder. Activation can fire many times per session; re-signing a
    ///     large folder on each one would be wasteful.
    ///   - directoriesProvider: Folders to scan for a storage directory.
    ///     Tests inject a temporary folder so a pass never touches the real
    ///     legacy sandbox folder.
    init(
        isEnabled: Bool,
        minimumInterval: TimeInterval = 300,
        directories: @escaping @MainActor (URL) -> [URL] = BundleRepairer.repairDirectories(for:)
    ) {
        self.isEnabled = isEnabled
        self.minimumInterval = minimumInterval
        self.directoriesProvider = directories
    }

    /// Folders that may contain bundles written by older DockDivider builds.
    nonisolated static func repairDirectories(for storageDirectory: URL) -> [URL] {
        var directories: [URL] = [storageDirectory]
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let legacySandboxDirectory = homeDirectory.appendingPathComponent(
            "Library/Containers/me.bogle.DockDivider/Data/Library/Application Support/DockDividers",
            isDirectory: true
        )

        if StoragePath.canonical(legacySandboxDirectory) != StoragePath.canonical(storageDirectory) {
            directories.append(legacySandboxDirectory)
        }
        return directories
    }

    /// Repairs bundles in the active storage folder and the legacy sandbox
    /// folder. `excludedURL` is the currently staged or dragged bundle, which
    /// must not be rewritten underneath the Dock.
    ///
    /// The scan and signing run off the main actor; only the brief per-bundle
    /// icon rendering and `NSWorkspace` calls hop back to it. Repeat passes for
    /// the same folder are throttled by `minimumInterval`.
    func repairExistingBundles(in storageDirectory: URL, excluding excludedURL: URL?) async {
        guard isEnabled, !isRepairing else { return }

        let directoryPath = StoragePath.canonical(storageDirectory)
        if lastRepairDirectoryPath == directoryPath,
           let lastRepairDate,
           Date().timeIntervalSince(lastRepairDate) < minimumInterval {
            return
        }

        isRepairing = true
        defer { isRepairing = false }

        let directories = directoriesProvider(storageDirectory)
        let plans = await Task.detached(priority: .utility) {
            BundleSynthesizer.repairPlans(in: directories, excluding: excludedURL)
        }.value

        for plan in plans {
            await BundleSynthesizer.applyRepair(plan)
        }

        lastRepairDirectoryPath = directoryPath
        lastRepairDate = Date()
    }
}
