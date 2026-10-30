//
//  BundleStagingService.swift
//  DockDivider
//

import Foundation

/// Builds divider artifacts off the main actor.
///
/// Every bundle is assembled inside a hidden temporary directory in the target
/// storage folder, signed there, and then moved into place with a single
/// same-volume rename. A partially written bundle is therefore never visible to
/// the Dock, `StorageMaintenance`, or the user.
nonisolated enum BundleStagingService {

    // MARK: - Divider App Bundles

    static func createDividerApp(
        iconData: Data,
        config: ActionConfig,
        hoverLabel: String?,
        model: DividerModel?,
        outputDirectory: URL
    ) throws -> URL {
        let fileManager = FileManager.default

        try createDirectory(outputDirectory)

        guard let runnerURL = locateRunnerExecutable() else {
            throw StagingError.runnerUnavailable
        }

        let stagingRoot = outputDirectory.appendingPathComponent(
            ".staging-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        } catch {
            throw StagingError.storageUnavailable(error.localizedDescription)
        }
        defer {
            try? fileManager.removeItem(at: stagingRoot)
        }

        let sanitizedLabel = sanitizeHoverLabel(hoverLabel)
        let bundleBaseName = sanitizedLabel.isEmpty
            ? "\u{200A}\(makeInvisibleID())"
            : "\(sanitizedLabel)\(makeInvisibleID())"
        let stagedBundleURL = stagingRoot.appendingPathComponent(
            "\(bundleBaseName).app",
            isDirectory: true
        )

        do {
            try populateDividerBundle(
                at: stagedBundleURL,
                runnerURL: runnerURL,
                iconData: iconData,
                config: config,
                hoverLabel: hoverLabel,
                model: model
            )
        } catch let error as StagingError {
            throw error
        } catch {
            throw StagingError.writeFailed(error.localizedDescription)
        }

        try signBundle(at: stagedBundleURL)

        let finalURL = outputDirectory.appendingPathComponent(
            "\(bundleBaseName).app",
            isDirectory: true
        )
        do {
            try fileManager.moveItem(at: stagedBundleURL, to: finalURL)
        } catch {
            throw StagingError.finalizeFailed(error.localizedDescription)
        }

        return finalURL
    }

    private static func populateDividerBundle(
        at appBundleURL: URL,
        runnerURL: URL,
        iconData: Data,
        config: ActionConfig,
        hoverLabel: String?,
        model: DividerModel?
    ) throws {
        let fileManager = FileManager.default
        let contentsURL = appBundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macosURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        try fileManager.createDirectory(at: macosURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        // 1. Copy the pre-compiled runner executable.
        let destinationExecURL = macosURL.appendingPathComponent("divider_runner")
        try fileManager.copyItem(at: runnerURL, to: destinationExecURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationExecURL.path)

        // 2. Write Info.plist. CFBundleIconFile is intentionally omitted so
        // IconServices never wraps the divider in the default app-icon squircle.
        let sanitizedLabel = sanitizeHoverLabel(hoverLabel)
        let displayName = sanitizedLabel.isEmpty ? "\u{200A}" : sanitizedLabel
        let plistContent: [String: Any] = [
            "CFBundleIdentifier": "com.dockdivider.item.\(UUID().uuidString.lowercased())",
            "CFBundleExecutable": "divider_runner",
            "CFBundleName": displayName,
            "CFBundleDisplayName": displayName,
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1.0",
            "CFBundleShortVersionString": "1.0",
            "CFBundleInfoDictionaryVersion": "6.0",
            "NSHighResolutionCapable": true,
            "LSUIElement": true,
            "NSAppleEventsUsageDescription": "Allows Dock Divider to perform Finder actions such as opening the Trash.",
            "LSMinimumSystemVersion": "13.0"
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plistContent,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"), options: .atomic)

        // 3. Write PkgInfo.
        try Data("APPL????".utf8).write(
            to: contentsURL.appendingPathComponent("PkgInfo"),
            options: .atomic
        )

        // 4. Write icon, action config, optional custom artwork, and divider model.
        try iconData.write(
            to: resourcesURL.appendingPathComponent("AppIcon.icns"),
            options: .atomic
        )
        let configData = try JSONEncoder().encode(config)
        try configData.write(
            to: resourcesURL.appendingPathComponent("ActionConfig.json"),
            options: .atomic
        )
        if let model, model.style == .image, let imageData = model.imageData, !imageData.isEmpty {
            try imageData.write(
                to: resourcesURL.appendingPathComponent("CustomImage.png"),
                options: .atomic
            )
        }
        if let model, let modelData = try? JSONEncoder().encode(model.withoutEmbeddedImageData()) {
            try? modelData.write(
                to: resourcesURL.appendingPathComponent("DividerModel.json"),
                options: .atomic
            )
        }

        // 5. Ownership marker, written before signing so it is covered by the
        // signature like every other bundle resource.
        try BundleMarker.write(BundleMarker.makeCurrent(), to: appBundleURL)
    }

    // MARK: - Native Spacers

    static func createNativeSpacer(
        size: SpacerSize = .regular,
        outputDirectory: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        try createDirectory(outputDirectory)

        let identifier = UUID().uuidString.prefix(8)
        let fileName = "Spacer-\(identifier).\(size.fileExtension)"
        let temporaryURL = outputDirectory.appendingPathComponent(".staging-\(UUID().uuidString).\(size.fileExtension)")
        let finalURL = outputDirectory.appendingPathComponent(fileName)

        do {
            try Data().write(to: temporaryURL, options: .atomic)
            try fileManager.moveItem(at: temporaryURL, to: finalURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw StagingError.writeFailed(error.localizedDescription)
        }

        return finalURL
    }

    // MARK: - Signing, Quarantine & Registration

    /// Removes extended attributes and ad-hoc signs the bundle. Runs off-main.
    static func signBundle(at appBundleURL: URL) throws {
        let iconForkURL = appBundleURL.appendingPathComponent("Icon\r")
        try? FileManager.default.removeItem(at: iconForkURL)

        removeQuarantine(at: appBundleURL)

        _ = runProcess("/usr/bin/xattr", arguments: ["-cr", appBundleURL.path])

        let result = runProcess(
            "/usr/bin/codesign",
            arguments: ["--force", "--deep", "--sign", "-", appBundleURL.path]
        )
        guard result.status == 0 else {
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw StagingError.signingFailed(detail.isEmpty ? "codesign failed." : detail)
        }

        removeQuarantine(at: appBundleURL)
    }

    static func removeQuarantine(at url: URL) {
        removexattr(url.path, "com.apple.quarantine", 0)

        let execURL = url.appendingPathComponent("Contents/MacOS/divider_runner")
        if FileManager.default.fileExists(atPath: execURL.path) {
            removexattr(execURL.path, "com.apple.quarantine", 0)
        }
    }

    /// Registers the finished bundle with LaunchServices so the Dock picks up
    /// the correct icon and metadata immediately. Runs off-main.
    static func registerWithLaunchServices(at appBundleURL: URL) {
        let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        guard FileManager.default.isExecutableFile(atPath: lsregisterPath) else { return }
        _ = runProcess(lsregisterPath, arguments: ["-f", "-R", "-trusted", appBundleURL.path])
    }

    // MARK: - Runner Resolution

    static func locateRunnerExecutable() -> URL? {
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

        return candidateURLs.first { fileManager.fileExists(atPath: $0.path) }
    }

    // MARK: - Helpers

    private static func createDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw StagingError.storageUnavailable(error.localizedDescription)
        }
    }

    private static func sanitizeHoverLabel(_ hoverLabel: String?) -> String {
        guard let raw = hoverLabel else { return "" }
        let illegalCharacters = CharacterSet.controlCharacters
            .union(.newlines)
        let cleanedScalars = raw.unicodeScalars.filter { !illegalCharacters.contains($0) }
        var cleaned = String(String.UnicodeScalarView(cleanedScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count > 64 {
            cleaned = String(cleaned.prefix(64))
        }
        return cleaned
    }

    /// Encodes a random UUID into non-combining zero-width Unicode characters
    /// so every generated bundle has a unique filename with 0 pt rendered text.
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

    private struct ProcessResult {
        let status: Int32
        let output: String
    }

    private static func runProcess(_ executablePath: String, arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return ProcessResult(status: -1, output: error.localizedDescription)
        }

        // Read before waiting so a verbose child cannot fill the pipe buffer
        // and deadlock.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            status: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }
}
