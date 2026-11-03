//
//  DockLiveItems.swift
//  DockDivider
//

import Foundation
import CoreFoundation

/// Reads the file URLs currently referenced by the user's Dock.
///
/// The Dock stores divider bundles as `file-data` entries inside
/// `persistent-apps`/`persistent-others` in `com.apple.dock`. Cleanup uses this
/// set to avoid deleting anything that is still backing a Dock tile.
enum DockLiveItems {
    /// Returns the canonical paths of every file referenced by the Dock, or
    /// `nil` when the Dock configuration cannot be read.
    ///
    /// A `nil` result must disable cleanup: treating an unreadable Dock as
    /// "nothing is live" would put every divider at risk.
    static func currentFileURLs() -> Set<String>? {
        let domain = "com.apple.dock" as CFString
        let keys = ["persistent-apps", "persistent-others"]

        var foundAnyValue = false
        var values: [Any] = []

        for key in keys {
            if let value = CFPreferencesCopyAppValue(key as CFString, domain) {
                foundAnyValue = true
                values.append(value)
            }
        }

        guard foundAnyValue else { return nil }

        var paths = Set<String>()
        for value in values {
            paths.formUnion(collectFileURLs(from: value))
        }
        return paths
    }

    private static func collectFileURLs(from value: Any) -> Set<String> {
        var result = Set<String>()

        if let dictionary = value as? [String: Any] {
            if let fileData = dictionary["file-data"] as? [String: Any],
               let urlString = fileData["_CFURLString"] as? String,
               let path = StoragePath.canonical(urlString) {
                result.insert(path)
            }
            for child in dictionary.values {
                result.formUnion(collectFileURLs(from: child))
            }
        } else if let array = value as? [Any] {
            for child in array {
                result.formUnion(collectFileURLs(from: child))
            }
        }

        return result
    }
}
