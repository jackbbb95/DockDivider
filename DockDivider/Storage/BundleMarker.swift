//
//  BundleMarker.swift
//  DockDivider
//

import Foundation

/// Metadata written into every generated divider bundle.
///
/// The marker lets repair and cleanup distinguish DockDivider-generated bundles
/// from unrelated `.app` bundles in a user-selected folder. Bundles created by
/// older builds are still recognised by their `divider_runner` executable.
struct BundleMarker: Codable, Equatable, Sendable {
    static let fileName = ".dockdivider.json"
    static let currentSchemaVersion = 1
    static let currentRunnerVersion = "2"

    var schemaVersion: Int
    var appVersion: String
    var runnerVersion: String
    var createdAt: Date

    static func makeCurrent() -> BundleMarker {
        BundleMarker(
            schemaVersion: currentSchemaVersion,
            appVersion: hostAppVersion,
            runnerVersion: currentRunnerVersion,
            createdAt: Date()
        )
    }

    static var hostAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func url(for bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent("Contents/Resources/\(fileName)")
    }

    static func exists(at bundleURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: url(for: bundleURL).path)
    }

    static func read(from bundleURL: URL) -> BundleMarker? {
        guard let data = try? Data(contentsOf: url(for: bundleURL)) else {
            return nil
        }
        return try? JSONDecoder().decode(BundleMarker.self, from: data)
    }

    static func write(_ marker: BundleMarker, to bundleURL: URL) throws {
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(marker)
        try data.write(to: url(for: bundleURL), options: .atomic)
    }

    /// Returns true for bundles this app owns.
    ///
    /// New bundles always carry a marker. Legacy bundles (created before the
    /// marker existed) are detected by the runner executable they contain.
    static func isDockDividerBundle(at bundleURL: URL) -> Bool {
        guard bundleURL.pathExtension == "app" else { return false }
        if exists(at: bundleURL) { return true }
        let legacyRunnerURL = bundleURL.appendingPathComponent("Contents/MacOS/divider_runner")
        return FileManager.default.fileExists(atPath: legacyRunnerURL.path)
    }
}
