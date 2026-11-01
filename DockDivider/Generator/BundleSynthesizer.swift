//
//  BundleSynthesizer.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import Foundation
import AppKit

/// Main-actor facade for divider bundle creation and repair.
///
/// File and subprocess work is delegated to `BundleStagingService`, which runs
/// off the main actor. Only the icon application and filesystem notification
/// steps remain here because AppKit/IconServices require the main thread.
enum BundleSynthesizer {

    // MARK: - Directory Resolution

    static func defaultOutputDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return try defaultOutputDirectory(applicationSupportDirectory: appSupport)
    }

    static func defaultOutputDirectory(applicationSupportDirectory: URL) throws -> URL {
        let outputDirectory = StorageLayout.defaultRoot(applicationSupportDirectory: applicationSupportDirectory)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        return outputDirectory
    }

    // MARK: - Native Spacer Creation

    /// Creates a native macOS Dock spacer trigger file (`.dockspace`, `.docksmallspace`, or `.dockflexspace`).
    /// When dragged onto the Dock, `Dock.app`'s `DOCKFileTileFactory` natively instantiates a `DOCKSpacerTile`
    /// (`spacer-tile`, `small-spacer-tile`, or `flex-spacer-tile`) with no tooltip and no click action.
    @discardableResult
    static func createNativeSpacerFile(
        size: SpacerSize = .regular,
        outputDirectory: URL? = nil
    ) throws -> URL {
        let targetDirectory: URL
        if let outputDirectory = outputDirectory {
            targetDirectory = outputDirectory
        } else {
            targetDirectory = try defaultOutputDirectory()
        }

        let fileURL = try BundleStagingService.createNativeSpacer(
            size: size,
            outputDirectory: targetDirectory
        )
        NSWorkspace.shared.noteFileSystemChanged(fileURL.path)
        return fileURL
    }

    // MARK: - App Bundle Creation

    @discardableResult
    @MainActor
    static func createDividerApp(
        iconData: Data,
        previewImage: NSImage? = nil,
        config: ActionConfig,
        hoverLabel: String?,
        model: DividerModel? = nil,
        outputDirectory: URL? = nil,
        registerWithLaunchServices: Bool = true
    ) throws -> URL {
        let targetDirectory: URL
        if let outputDirectory = outputDirectory {
            targetDirectory = outputDirectory
        } else {
            targetDirectory = try defaultOutputDirectory()
        }

        let appBundleURL = try BundleStagingService.createDividerApp(
            iconData: iconData,
            config: config,
            hoverLabel: hoverLabel,
            model: model,
            outputDirectory: targetDirectory
        )

        applyCustomIconAndNotify(
            previewImage ?? NSImage(data: iconData),
            at: appBundleURL
        )

        if registerWithLaunchServices {
            BundleStagingService.registerWithLaunchServices(at: appBundleURL)
        }

        return appBundleURL
    }

    // MARK: - Appearance & Registration

    /// Applies the un-enclosed custom icon, clears quarantine, and notifies the
    /// filesystem. Must run on the main actor because IconServices is not
    /// thread-safe.
    @MainActor
    static func applyCustomIconAndNotify(_ customIcon: NSImage?, at appBundleURL: URL) {
        if let customIcon {
            _ = NSWorkspace.shared.setIcon(customIcon, forFile: appBundleURL.path, options: [])
        }

        BundleStagingService.removeQuarantine(at: appBundleURL)
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: appBundleURL.path
        )
        NSWorkspace.shared.noteFileSystemChanged(appBundleURL.path)
    }

    /// Notifies the filesystem for artifacts that do not need an icon, such as
    /// native spacer trigger files.
    @MainActor
    static func notifyFileSystemChanged(at url: URL) {
        BundleStagingService.removeQuarantine(at: url)
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: url.path
        )
        NSWorkspace.shared.noteFileSystemChanged(url.path)
    }

    /// Strips extended attributes/quarantine, ad-hoc signs the `.app` bundle,
    /// applies the un-enclosed custom icon, and registers the bundle with
    /// LaunchServices.
    ///
    /// - Note: Bundle creation goes through `BundleStagingService` directly so
    ///   the signing work happens off the main actor. This synchronous variant
    ///   exists for repair, which still runs on the main actor.
    @MainActor
    static func finalizeAndSignBundle(
        at appBundleURL: URL,
        customIcon: NSImage?,
        registerWithLaunchServices: Bool = true
    ) {
        try? BundleStagingService.signBundle(at: appBundleURL)
        applyCustomIconAndNotify(customIcon, at: appBundleURL)

        if registerWithLaunchServices {
            BundleStagingService.registerWithLaunchServices(at: appBundleURL)
        }
    }

    // MARK: - Bundle Repair & Maintenance

    /// Repairs any previously generated divider `.app` bundles on disk (such as bundles
    /// created while the app was sandboxed or with `LSBackgroundOnly` in `Info.plist`, or
    /// whose orientation needs to flip when the user moves their Dock between Bottom and Left/Right)
    /// so dividers already placed in the user's Dock work cleanly without needing to be re-dragged.
    @MainActor
    static func repairExistingBundles(in directories: [URL], excluding excludedURL: URL? = nil) {
        let fileManager = FileManager.default
        let latestRunnerURL = BundleStagingService.locateRunnerExecutable()
        let systemOrientation = DividerOrientation.currentSystemDockOrientation
        let excludedPath = excludedURL?.standardizedFileURL.path

        for directory in directories {
            guard let items = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants]
            ) else {
                continue
            }

            for itemURL in items where itemURL.pathExtension == "app" {
                // Never touch unrelated .app bundles in a user-selected folder.
                guard BundleMarker.isDockDividerBundle(at: itemURL) else {
                    continue
                }

                // Never touch the temporary pre-staged bundle managed by AppState
                if let excludedPath = excludedPath,
                   itemURL.standardizedFileURL.path == excludedPath {
                    continue
                }

                let hasMarker = BundleMarker.exists(at: itemURL)
                let marker = BundleMarker.read(from: itemURL)

                let infoPlistURL = itemURL.appendingPathComponent("Contents/Info.plist")
                let iconURL = itemURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
                let execURL = itemURL.appendingPathComponent("Contents/MacOS/divider_runner")
                let iconForkURL = itemURL.appendingPathComponent("Icon\r")
                let modelURL = itemURL.appendingPathComponent("Contents/Resources/DividerModel.json")
                let customImageURL = itemURL.appendingPathComponent("Contents/Resources/CustomImage.png")

                guard fileManager.fileExists(atPath: infoPlistURL.path),
                      fileManager.fileExists(atPath: execURL.path) else {
                    continue
                }

                var needsPlistRepair = false
                if let plistData = try? Data(contentsOf: infoPlistURL),
                   var plist = (try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)) as? [String: Any] {
                    if plist["LSBackgroundOnly"] != nil || plist["CFBundleIconFile"] != nil || plist["NSAppleEventsUsageDescription"] == nil {
                        needsPlistRepair = true
                        plist.removeValue(forKey: "LSBackgroundOnly")
                        plist.removeValue(forKey: "CFBundleIconFile")
                        plist["LSUIElement"] = true
                        plist["NSAppleEventsUsageDescription"] = "Allows Dock Divider to perform Finder actions such as opening the Trash."
                        if let updatedData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                            try? updatedData.write(to: infoPlistURL)
                        }
                    }
                }

                var needsOrientationUpdate = false
                var updatedIconImage: NSImage? = nil
                if let modelData = try? Data(contentsOf: modelURL),
                   var savedModel = try? JSONDecoder().decode(DividerModel.self, from: modelData) {
                    // Bundles written by DockDivider keep artwork in `CustomImage.png`
                    // and omit the bytes from JSON. Hydrate the image before any
                    // repair that needs to re-render the icon.
                    if savedModel.style == .image, savedModel.imageData == nil {
                        savedModel.imageData = try? Data(contentsOf: customImageURL)
                    }

                    if (savedModel.style == .line || savedModel.style == .dashed),
                       savedModel.orientation != systemOrientation {
                        needsOrientationUpdate = true
                        savedModel.orientation = systemOrientation
                        if let newIconData = IconRenderer.renderIconData(for: savedModel) {
                            try? newIconData.write(to: iconURL)
                            updatedIconImage = IconRenderer.renderNSImage(for: savedModel, size: CGSize(width: 256, height: 256))
                            if let updatedModelData = try? JSONEncoder().encode(savedModel.withoutEmbeddedImageData()) {
                                try? updatedModelData.write(to: modelURL)
                            }
                        }
                    }
                }

                let missingIconFork = !fileManager.fileExists(atPath: iconForkURL.path)
                // Upgrading the runner by itself is reserved for bundles that
                // carry our marker. Legacy unmarked bundles are migrated only
                // when another repair (plist, orientation, or icon) touches
                // them, so a first launch does not re-sign an entire legacy
                // storage folder at once.
                let needsRunnerUpdate = hasMarker
                    && latestRunnerURL != nil
                    && marker?.runnerVersion != BundleMarker.currentRunnerVersion

                // Only re-sign and re-apply custom icon if the bundle actually needed migration/repair
                guard needsPlistRepair || needsOrientationUpdate || missingIconFork || needsRunnerUpdate else {
                    continue
                }

                if let latestRunnerURL = latestRunnerURL {
                    try? fileManager.removeItem(at: execURL)
                    try? fileManager.copyItem(at: latestRunnerURL, to: execURL)
                    try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: execURL.path)
                }

                let customIcon: NSImage? = updatedIconImage ?? {
                    guard let iconData = try? Data(contentsOf: iconURL) else { return nil }
                    return NSImage(data: iconData)
                }()

                // Migrate legacy bundles to the marker format, and refresh the
                // marker when a marked bundle's runner was upgraded.
                if !hasMarker
                    || (marker?.runnerVersion != BundleMarker.currentRunnerVersion
                        && needsRunnerUpdate) {
                    try? BundleMarker.write(BundleMarker.makeCurrent(), to: itemURL)
                }

                finalizeAndSignBundle(at: itemURL, customIcon: customIcon)
            }
        }
    }
}
