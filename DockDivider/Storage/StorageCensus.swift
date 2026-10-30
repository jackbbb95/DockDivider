//
//  StorageCensus.swift
//  DockDivider
//

import Foundation

nonisolated struct StorageItem: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case appBundle
        case nativeSpacer
    }

    let url: URL
    let kind: Kind
    let sizeBytes: Int64
    let createdAt: Date?
    let isLive: Bool
    let isExcluded: Bool

    var id: String { url.path }

    var displayName: String {
        switch kind {
        case .nativeSpacer:
            switch url.pathExtension {
            case "dockspace": return "Native spacer (full)"
            case "docksmallspace": return "Native spacer (small)"
            case "dockflexspace": return "Native spacer (flexible)"
            default: return "Native spacer"
            }
        case .appBundle:
            let baseName = url.deletingPathExtension().lastPathComponent
            let invisibleCharacters = CharacterSet(charactersIn: "\u{200A}\u{200B}\u{2060}\u{FEFF}")
            let cleaned = baseName
                .components(separatedBy: invisibleCharacters)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "Untitled divider" : cleaned
        }
    }

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

nonisolated struct StorageSummary: Equatable, Sendable {
    let itemCount: Int
    let totalBytes: Int64
    let unusedCount: Int
    let unusedBytes: Int64
    let liveSetAvailable: Bool
}

nonisolated struct StorageCensus: Equatable, Sendable {
    let items: [StorageItem]
    /// Items safe to remove: not referenced by the Dock, not the active staged
    /// bundle, and older than the grace period.
    let unusedItems: [StorageItem]
    /// False when the Dock configuration could not be read. Cleanup must stay
    /// disabled in that case.
    let liveSetAvailable: Bool

    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    var unusedBytes: Int64 {
        unusedItems.reduce(0) { $0 + $1.sizeBytes }
    }

    var summary: StorageSummary {
        StorageSummary(
            itemCount: items.count,
            totalBytes: totalBytes,
            unusedCount: unusedItems.count,
            unusedBytes: unusedBytes,
            liveSetAvailable: liveSetAvailable
        )
    }

    static let empty = StorageCensus(items: [], unusedItems: [], liveSetAvailable: false)
}

/// The source used to decide which storage items are currently referenced by the Dock.
nonisolated enum StorageLiveSet: Sendable, Equatable {
    case currentDock
    case known(Set<String>)
    case unavailable

    var isAvailable: Bool {
        switch self {
        case .currentDock, .known:
            return true
        case .unavailable:
            return false
        }
    }

    func resolvedPaths() -> Set<String>? {
        switch self {
        case .currentDock:
            return DockLiveItems.currentFileURLs()
        case .known(let paths):
            return paths
        case .unavailable:
            return nil
        }
    }
}
