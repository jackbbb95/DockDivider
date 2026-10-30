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

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    /// Folders that may contain bundles written by older DockDivider builds.
    static func repairDirectories(for storageDirectory: URL) -> [URL] {
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
    func repairExistingBundles(in storageDirectory: URL, excluding excludedURL: URL?) {
        guard isEnabled else { return }

        BundleSynthesizer.repairExistingBundles(
            in: Self.repairDirectories(for: storageDirectory),
            excluding: excludedURL
        )
    }
}
