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

    // MARK: - Bundle Repair & Maintenance

    /// One bundle's pending repair work, computed away from the main actor.
    ///
    /// The plan holds Foundation values only: plist and model inspection happen
    /// during the scan, while icon rendering and IconServices application stay
    /// on the main actor in `applyRepair`.
    struct DividerBundleRepairPlan: Sendable {
        let bundleURL: URL
        let repairedPlistData: Data?
        /// The model with its orientation updated, when the Dock moved.
        let updatedModel: DividerModel?
        /// The bundle's current artwork, reused when no new icon was rendered.
        let existingIconData: Data?
        let latestRunnerURL: URL?
        let copyRunner: Bool
        let writeMarker: Bool
    }

    /// Scans the given folders and returns the bundles that need repair.
    ///
    /// This is pure filesystem and JSON work so callers can run it off the main
    /// actor. A large storage folder therefore costs a background scan instead
    /// of blocking launch or activation.
    nonisolated static func repairPlans(
        in directories: [URL],
        excluding excludedURL: URL? = nil
    ) -> [DividerBundleRepairPlan] {
        let fileManager = FileManager.default
        let latestRunnerURL = BundleStagingService.locateRunnerExecutable()
        let systemOrientation = DividerOrientation.currentSystemDockOrientation
        let excludedPath = excludedURL?.standardizedFileURL.path
        var plans: [DividerBundleRepairPlan] = []

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

                // Never touch the temporary pre-staged bundle managed by AppState.
                if let excludedPath,
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

                var repairedPlistData: Data?
                if let plistData = try? Data(contentsOf: infoPlistURL),
                   var plist = (try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)) as? [String: Any],
                   plist["LSBackgroundOnly"] != nil
                    || plist["CFBundleIconFile"] != nil
                    || plist["NSAppleEventsUsageDescription"] == nil {
                    plist.removeValue(forKey: "LSBackgroundOnly")
                    plist.removeValue(forKey: "CFBundleIconFile")
                    plist["LSUIElement"] = true
                    plist["NSAppleEventsUsageDescription"] = "Allows Dock Divider to perform Finder actions such as opening the Trash."
                    repairedPlistData = try? PropertyListSerialization.data(
                        fromPropertyList: plist,
                        format: .xml,
                        options: 0
                    )
                }

                var updatedModel: DividerModel?
                if let modelData = try? Data(contentsOf: modelURL),
                   var savedModel = try? JSONDecoder().decode(DividerModel.self, from: modelData) {
                    // Bundles written by DockDivider keep artwork in
                    // `CustomImage.png` and omit the bytes from JSON. Hydrate
                    // the image before a repair re-renders the icon.
                    if savedModel.style == .image, savedModel.imageData == nil {
                        savedModel.imageData = try? Data(contentsOf: customImageURL)
                    }

                    if (savedModel.style == .line || savedModel.style == .dashed),
                       savedModel.orientation != systemOrientation {
                        savedModel.orientation = systemOrientation
                        updatedModel = savedModel
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

                guard repairedPlistData != nil
                        || updatedModel != nil
                        || missingIconFork
                        || needsRunnerUpdate else {
                    continue
                }

                plans.append(
                    DividerBundleRepairPlan(
                        bundleURL: itemURL,
                        repairedPlistData: repairedPlistData,
                        updatedModel: updatedModel,
                        existingIconData: try? Data(contentsOf: iconURL),
                        latestRunnerURL: latestRunnerURL,
                        copyRunner: latestRunnerURL != nil,
                        writeMarker: !hasMarker || needsRunnerUpdate
                    )
                )
            }
        }

        return plans
    }

    /// Applies one repair plan.
    ///
    /// Icon rendering and `NSWorkspace.setIcon` stay on the main actor because
    /// AppKit and IconServices are not thread-safe; file writes, the runner
    /// copy, and `codesign` run in a background task.
    @MainActor
    static func applyRepair(_ plan: DividerBundleRepairPlan) async {
        let iconURL = plan.bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        let modelURL = plan.bundleURL.appendingPathComponent("Contents/Resources/DividerModel.json")

        var renderedIconData: Data?
        var customIcon: NSImage?
        if let model = plan.updatedModel {
            renderedIconData = IconRenderer.renderIconData(for: model)
            if renderedIconData != nil {
                customIcon = IconRenderer.renderNSImage(
                    for: model,
                    size: CGSize(width: 256, height: 256)
                )
            }
        }
        if customIcon == nil, let existingIconData = plan.existingIconData {
            customIcon = NSImage(data: existingIconData)
        }

        let infoPlistURL = plan.bundleURL.appendingPathComponent("Contents/Info.plist")
        let execURL = plan.bundleURL.appendingPathComponent("Contents/MacOS/divider_runner")

        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default

            if let repairedPlistData = plan.repairedPlistData {
                try? repairedPlistData.write(to: infoPlistURL)
            }
            if let renderedIconData, let model = plan.updatedModel {
                try? renderedIconData.write(to: iconURL)
                if let updatedModelData = try? JSONEncoder().encode(model.withoutEmbeddedImageData()) {
                    try? updatedModelData.write(to: modelURL)
                }
            }
            if plan.copyRunner, let latestRunnerURL = plan.latestRunnerURL {
                try? fileManager.removeItem(at: execURL)
                try? fileManager.copyItem(at: latestRunnerURL, to: execURL)
                try? fileManager.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: execURL.path
                )
            }
            if plan.writeMarker {
                try? BundleMarker.write(BundleMarker.makeCurrent(), to: plan.bundleURL)
            }

            try? BundleStagingService.signBundle(at: plan.bundleURL)
        }.value

        applyCustomIconAndNotify(customIcon, at: plan.bundleURL)

        await Task.detached(priority: .utility) {
            BundleStagingService.registerWithLaunchServices(at: plan.bundleURL)
        }.value
    }
}
