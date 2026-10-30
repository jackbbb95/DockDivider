//
//  BundleSynthesizer.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import Foundation
import AppKit

enum BundleSynthesizer {

    // MARK: - Directory Resolution

    static func defaultOutputDirectory() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let outputDirectory = appSupport.appendingPathComponent("DockDividers", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
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
        let fileManager = FileManager.default
        let targetDirectory: URL
        if let outputDirectory = outputDirectory {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            targetDirectory = outputDirectory
        } else {
            targetDirectory = try defaultOutputDirectory()
        }

        let uniqueID = UUID().uuidString.prefix(8)
        let fileURL = targetDirectory.appendingPathComponent("Spacer-\(uniqueID).\(size.fileExtension)")
        try Data().write(to: fileURL)
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
        outputDirectory: URL? = nil
    ) throws -> URL {
        let fileManager = FileManager.default
        let targetDirectory: URL
        if let outputDirectory = outputDirectory {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            targetDirectory = outputDirectory
        } else {
            targetDirectory = try defaultOutputDirectory()
        }

        // Encode a unique ID using non-combining zero-width Unicode characters
        // (\u{200B} and \u{2060}). When hoverLabel is empty, we prefix with a single
        // Hair Space (\u{200A}, ~1pt advance width, 0 visible ink pixels).
        // Why \u{200A} is required: Dock.app's DOCKLabelLayer reuses a single shared
        // CALayer across Dock icons. If a tile's label measures 0px wide (pure zero-width chars),
        // CGBitmapContextCreate(width: 0) returns NULL and DOCKLabelLayer bails out without
        // overwriting the previous icon's cached label image—causing the tooltip to display
        // the name of whichever app was hovered previously! A single \u{200A} gives width >= 1px
        // so DOCKLabelLayer overwrites the tooltip with a blank 1px image.
        let invisibleID = makeInvisibleID()
        let sanitizedLabel = sanitizeHoverLabel(hoverLabel)
        let bundleBaseName = sanitizedLabel.isEmpty ? "\u{200A}\(invisibleID)" : "\(sanitizedLabel)\(invisibleID)"
        let appBundleURL = targetDirectory.appendingPathComponent("\(bundleBaseName).app", isDirectory: true)

        let contentsURL = appBundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macosURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        try fileManager.createDirectory(at: macosURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        // 1. Copy the pre-compiled runner executable
        guard let runnerURL = locateRunnerExecutable() else {
            throw NSError(domain: "DockDivider", code: 404, userInfo: [NSLocalizedDescriptionKey: "divider_runner binary missing"])
        }

        let destinationExecURL = macosURL.appendingPathComponent("divider_runner")
        try fileManager.copyItem(at: runnerURL, to: destinationExecURL)

        // Ensure execution permissions (chmod +x)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationExecURL.path)

        // 2. Write Info.plist (omit CFBundleIconFile so macOS IconServices never wraps
        // the icon in the default app-icon squircle enclosure; we apply the un-enclosed
        // transparent icon directly to the bundle via NSWorkspace.shared.setIcon below).
        let displayName = sanitizedLabel.isEmpty ? "\u{200A}" : sanitizedLabel
        let plistContent: [String: Any] = [
            "CFBundleIdentifier": "com.dockdivider.item.\(UUID().uuidString.lowercased())",
            "CFBundleExecutable": "divider_runner",
            "CFBundleName": displayName,
            "CFBundleDisplayName": displayName,
            "CFBundlePackageType": "APPL",
            "LSUIElement": true,
            "NSAppleEventsUsageDescription": "Allows Dock Divider to perform Finder actions such as opening the Trash.",
            "LSMinimumSystemVersion": "13.0"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plistContent, format: .xml, options: 0)
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        // 3. Write PkgInfo
        let pkgInfoData = "APPL????".data(using: .utf8)!
        try pkgInfoData.write(to: contentsURL.appendingPathComponent("PkgInfo"))

        // 4. Write AppIcon.icns, ActionConfig.json, and optional DividerModel.json
        try iconData.write(to: resourcesURL.appendingPathComponent("AppIcon.icns"))
        let configData = try JSONEncoder().encode(config)
        try configData.write(to: resourcesURL.appendingPathComponent("ActionConfig.json"))
        if let model = model, let modelData = try? JSONEncoder().encode(model) {
            try? modelData.write(to: resourcesURL.appendingPathComponent("DividerModel.json"))
        }

        // 5. Sign, apply un-enclosed icon, and register with LaunchServices
        finalizeAndSignBundle(at: appBundleURL, customIcon: previewImage ?? NSImage(data: iconData))

        return appBundleURL
    }

    // MARK: - Bundle Signing & Registration

    /// Strips extended attributes/quarantine, ad-hoc signs the `.app` bundle, applies the
    /// un-enclosed custom icon, and registers the bundle with LaunchServices.
    @MainActor
    static func finalizeAndSignBundle(at appBundleURL: URL, customIcon: NSImage?) {
        let fileManager = FileManager.default
        let execURL = appBundleURL.appendingPathComponent("Contents/MacOS/divider_runner")
        let iconForkURL = appBundleURL.appendingPathComponent("Icon\r")

        // Remove any prior Icon\r fork and extended attributes before running codesign
        try? fileManager.removeItem(at: iconForkURL)
        removexattr(appBundleURL.path, "com.apple.quarantine", 0)
        removexattr(execURL.path, "com.apple.quarantine", 0)

        runProcess("/usr/bin/xattr", arguments: ["-cr", appBundleURL.path])
        runProcess("/usr/bin/codesign", arguments: ["--force", "--deep", "--sign", "-", appBundleURL.path])

        // Apply the transparent icon as a custom bundle file icon (Icon\r) AFTER signing.
        // On macOS, CFBundleIconFile icons are automatically placed inside a gray rounded-square
        // app-icon squircle enclosure by IconServices, whereas custom icons set via
        // NSWorkspace.shared.setIcon are rendered 100% un-enclosed with transparent backgrounds.
        // Always execute NSWorkspace.shared.setIcon on the main thread, as AppKit/IconServices
        // is not thread-safe when rasterizing NSImage representations off the main thread.
        if let customIcon = customIcon {
            let applyIconBlock = {
                guard FileManager.default.fileExists(atPath: appBundleURL.path) else { return }
                _ = NSWorkspace.shared.setIcon(customIcon, forFile: appBundleURL.path, options: [])
            }
            if Thread.isMainThread {
                applyIconBlock()
            } else {
                DispatchQueue.main.sync(execute: applyIconBlock)
            }
        }

        // Ensure quarantine is never present after setIcon
        removexattr(appBundleURL.path, "com.apple.quarantine", 0)
        removexattr(execURL.path, "com.apple.quarantine", 0)

        // Touch modification date and register with LaunchServices so Dock & LaunchServices
        // immediately trust and recognize the bundle
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: appBundleURL.path)
        if Thread.isMainThread {
            NSWorkspace.shared.noteFileSystemChanged(appBundleURL.path)
        } else {
            DispatchQueue.main.async {
                NSWorkspace.shared.noteFileSystemChanged(appBundleURL.path)
            }
        }

        let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        if fileManager.isExecutableFile(atPath: lsregisterPath) {
            runProcess(lsregisterPath, arguments: ["-f", "-R", "-trusted", appBundleURL.path])
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
        let latestRunnerURL = locateRunnerExecutable()
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
                // Never touch the temporary pre-staged bundle managed by AppState
                if let excludedPath = excludedPath,
                   itemURL.standardizedFileURL.path == excludedPath {
                    continue
                }

                let infoPlistURL = itemURL.appendingPathComponent("Contents/Info.plist")
                let iconURL = itemURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
                let execURL = itemURL.appendingPathComponent("Contents/MacOS/divider_runner")
                let iconForkURL = itemURL.appendingPathComponent("Icon\r")
                let modelURL = itemURL.appendingPathComponent("Contents/Resources/DividerModel.json")

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
                   var savedModel = try? JSONDecoder().decode(DividerModel.self, from: modelData),
                   (savedModel.style == .line || savedModel.style == .dashed),
                   savedModel.orientation != systemOrientation {
                    needsOrientationUpdate = true
                    savedModel.orientation = systemOrientation
                    if let newIconData = IconRenderer.renderIconData(for: savedModel) {
                        try? newIconData.write(to: iconURL)
                        updatedIconImage = IconRenderer.renderNSImage(for: savedModel, size: CGSize(width: 256, height: 256))
                        if let updatedModelData = try? JSONEncoder().encode(savedModel) {
                            try? updatedModelData.write(to: modelURL)
                        }
                    }
                }

                let missingIconFork = !fileManager.fileExists(atPath: iconForkURL.path)

                // Only re-sign and re-apply custom icon if the bundle actually needed migration/repair
                guard needsPlistRepair || needsOrientationUpdate || missingIconFork else {
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
                finalizeAndSignBundle(at: itemURL, customIcon: customIcon)
            }
        }
    }

    // MARK: - Process Execution & Helpers

    private static func runProcess(_ executablePath: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    private static func locateRunnerExecutable() -> URL? {
        let fileManager = FileManager.default
        var candidateURLs: [URL] = []
        if let mainRes = Bundle.main.url(forResource: "divider_runner", withExtension: nil) {
            candidateURLs.append(mainRes)
        }
        if let appStateBundle = Bundle(for: AppState.self).url(forResource: "divider_runner", withExtension: nil) {
            candidateURLs.append(appStateBundle)
        }
        for bundle in Bundle.allBundles {
            if let res = bundle.url(forResource: "divider_runner", withExtension: nil) {
                candidateURLs.append(res)
            }
        }
        let testBundleURL = Bundle(for: AppState.self).bundleURL
        let hostAppResources = testBundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("divider_runner")
        candidateURLs.append(hostAppResources)

        let appBundleResources = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/divider_runner")
        candidateURLs.append(appBundleResources)

        return candidateURLs.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    // MARK: - Identifier & String Helpers

    private static func sanitizeHoverLabel(_ hoverLabel: String?) -> String {
        let trimmed = hoverLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    /// Encodes a random UUID into a sequence of non-combining zero-width Unicode characters
    /// (\u{200B} Zero-Width Space and \u{2060} Word Joiner) so every generated `.app` bundle
    /// has a unique filename on disk with 0pt rendered text width.
    private static func makeInvisibleID() -> String {
        var result = ""
        var uuidBytes = UUID().uuid
        withUnsafeBytes(of: &uuidBytes) { rawBuffer in
            for byte in rawBuffer.prefix(4) {
                for bit in 0..<8 {
                    let isOne = ((byte >> bit) & 1) == 1
                    result.append(isOne ? "\u{2060}" : "\u{200B}")
                }
            }
        }
        return result
    }
}
