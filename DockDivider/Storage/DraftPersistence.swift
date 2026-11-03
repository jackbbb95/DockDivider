//
//  DraftPersistence.swift
//  DockDivider
//

import Foundation

/// Persists the last edited design in Application Support.
///
/// The draft is stored outside `UserDefaults` so custom artwork does not bloat
/// the preferences plist. Artwork is written once as `DraftImage.png` rather
/// than base64-encoded into `Draft.json`, mirroring how generated bundles keep
/// the image next to the model. Writes are atomic.
enum DraftPersistence {
    static let fileName = "Draft.json"
    static let imageFileName = "DraftImage.png"

    static func url(in applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    static func imageURL(in applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory.appendingPathComponent(imageFileName, isDirectory: false)
    }

    static func load(from applicationSupportDirectory: URL) -> DividerModel? {
        guard let data = try? Data(contentsOf: url(in: applicationSupportDirectory)) else {
            return nil
        }
        guard var draft = try? JSONDecoder().decode(DividerModel.self, from: data) else {
            return nil
        }

        // Drafts written by earlier builds embed the artwork in the JSON; only
        // reach for the sidecar file when the model has no bytes of its own.
        if draft.imageData == nil,
           let image = try? Data(contentsOf: imageURL(in: applicationSupportDirectory)),
           !image.isEmpty {
            draft.imageData = image
        }
        return draft
    }

    /// Saves the draft, keeping the artwork in a sidecar file.
    ///
    /// Called on the main actor after the debounce. The JSON payload and the
    /// image are small and the image write is skipped when the bytes have not
    /// changed, so a burst of edits costs one JSON write per settle rather than
    /// a full base64 copy of the artwork.
    static func save(_ draft: DividerModel, to applicationSupportDirectory: URL) {
        do {
            try FileManager.default.createDirectory(
                at: applicationSupportDirectory,
                withIntermediateDirectories: true
            )

            let imageURL = imageURL(in: applicationSupportDirectory)
            if let imageData = draft.imageData, !imageData.isEmpty {
                let existing = try? Data(contentsOf: imageURL)
                if existing != imageData {
                    try imageData.write(to: imageURL, options: .atomic)
                }
            } else if FileManager.default.fileExists(atPath: imageURL.path) {
                try? FileManager.default.removeItem(at: imageURL)
            }

            let storedDraft = draft.withoutEmbeddedImageData()
            let data = try JSONEncoder().encode(storedDraft)
            try data.write(to: url(in: applicationSupportDirectory), options: .atomic)
        } catch {
            // Persistence is best-effort; a failed save must never block editing
            // or staging.
        }
    }
}
