//
//  DraftPersistence.swift
//  DockDivider
//

import Foundation

/// Persists the last edited design in Application Support.
///
/// The draft is stored outside `UserDefaults` so custom artwork does not bloat
/// the preferences plist. Writes are atomic and happen off the main actor.
nonisolated enum DraftPersistence {
    static let fileName = "Draft.json"

    static func url(in applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    static func load(from applicationSupportDirectory: URL) -> DividerModel? {
        guard let data = try? Data(contentsOf: url(in: applicationSupportDirectory)) else {
            return nil
        }
        return try? JSONDecoder().decode(DividerModel.self, from: data)
    }

    static func save(_ draft: DividerModel, to applicationSupportDirectory: URL) {
        let directory = applicationSupportDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(draft)
            try data.write(to: url(in: directory), options: .atomic)
        } catch {
            // Persistence is best-effort; a failed save must never block editing
            // or staging.
        }
    }
}
