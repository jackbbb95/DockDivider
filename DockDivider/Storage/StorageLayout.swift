//
//  StorageLayout.swift
//  DockDivider
//

import Foundation

/// Layout rules for the folder that backs generated Dock dividers.
enum StorageLayout {
    /// Generated content always lives in a dedicated subfolder so a user-selected
    /// root such as ~/Applications never fills up with generated app bundles.
    static let folderName = "DockDividers"

    /// Returns the folder that should actually contain generated bundles.
    ///
    /// If the user already selected a folder named `DockDividers`, it is used
    /// as-is rather than creating a nested `DockDividers/DockDividers` folder.
    static func effectiveDirectory(forSelectedRoot root: URL) -> URL {
        let standardized = root.standardizedFileURL
        if standardized.lastPathComponent == folderName {
            return standardized
        }
        return standardized.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Default root used when the user has not chosen a custom location.
    static func defaultRoot(applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory.appendingPathComponent(folderName, isDirectory: true)
    }
}

/// Canonical path helpers shared by storage scanning and Dock reference matching.
enum StoragePath {
    static func canonical(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func canonical(_ urlString: String) -> String? {
        guard let url = URL(string: urlString), url.isFileURL else {
            if urlString.hasPrefix("/") {
                return canonical(URL(fileURLWithPath: urlString))
            }
            return nil
        }
        return canonical(url)
    }
}
