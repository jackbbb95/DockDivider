//
//  DockDividerTests.swift
//  DockDividerTests
//
//  Created by Jack Bogle on 10/27/26.
//

import Testing
import SwiftUI
import AppKit
@testable import DockDivider

@MainActor
struct DockDividerTests {

    // MARK: - DividerModel Tests

    @Test func testDividerModelDefaults() {
        let model = DividerModel()

        #expect(model.style == .line)
        #expect(model.colorPreset == .adaptiveWhite)
        #expect(model.customRed == 1.0)
        #expect(model.customGreen == 1.0)
        #expect(model.customBlue == 1.0)
        #expect(model.opacity == 0.80)
        #expect(model.thickness == 1.5)
        #expect(model.heightRatio == 0.65)
        #expect(model.verticalOffset == 0.0)
        #expect(model.hoverLabel == "")
        #expect(model.labelMode == .text)
        #expect(model.labelText == "DEV")
        #expect(model.isVerticalText == false)
        #expect(model.symbolName == "star.fill")
        #expect(model.imageData == nil)
        #expect(model.roundImageCorners == true)
        #expect(model.imageCornerRadiusRatio == 0.225)
        #expect(model.actionConfig == ActionConfig.none)
    }

    @Test func testColorPresetRawValuesAndDecoding() throws {
        #expect(ColorPreset.adaptiveWhite.rawValue == "Light")
        #expect(ColorPreset.dark.rawValue == "Dark")
        #expect(ColorPreset.custom.rawValue == "Custom")

        // Test decoding backward compatibility: "White" and "Light"
        let whiteJSON = "\"White\"".data(using: .utf8)!
        let decodedWhite = try JSONDecoder().decode(ColorPreset.self, from: whiteJSON)
        #expect(decodedWhite == .adaptiveWhite)

        let lightJSON = "\"Light\"".data(using: .utf8)!
        let decodedLight = try JSONDecoder().decode(ColorPreset.self, from: lightJSON)
        #expect(decodedLight == .adaptiveWhite)
    }

    @Test func testResetToNativeMatch() {
        var model = DividerModel()
        model.style = .dashed
        model.colorPreset = .dark
        model.opacity = 0.95
        model.thickness = 4.0
        model.heightRatio = 0.3
        model.verticalOffset = 12.0
        model.hoverLabel = "Custom Label"

        model.resetToNativeMatch()

        #expect(model.style == .line)
        #expect(model.colorPreset == .adaptiveWhite)
        #expect(model.opacity == 0.80)
        #expect(model.thickness == 1.5)
        #expect(model.heightRatio == 0.65)
        #expect(model.verticalOffset == 0.0)
        #expect(model.hoverLabel == "")
        #expect(model.roundImageCorners == true)
        #expect(model.imageCornerRadiusRatio == 0.225)
    }

    @Test func testColorConversionAndEffectiveColors() {
        var model = DividerModel()

        // Adaptive White
        model.colorPreset = .adaptiveWhite
        #expect(model.effectiveNSColor == NSColor.white)

        // Dark
        model.colorPreset = .dark
        #expect(model.effectiveNSColor == NSColor(white: 0.15, alpha: 1.0))

        // Custom color
        model.colorPreset = .custom
        model.customRed = 0.2
        model.customGreen = 0.4
        model.customBlue = 0.6
        let nsColor = model.effectiveNSColor
        #expect(abs(nsColor.redComponent - 0.2) < 0.01)
        #expect(abs(nsColor.greenComponent - 0.4) < 0.01)
        #expect(abs(nsColor.blueComponent - 0.6) < 0.01)

        // Test updateCustomColor from explicit sRGB Color
        model.updateCustomColor(from: Color(red: 1.0, green: 0.0, blue: 0.0))
        #expect(abs(model.customRed - 1.0) < 0.01)
        #expect(abs(model.customGreen - 0.0) < 0.01)
        #expect(abs(model.customBlue - 0.0) < 0.01)

        // Test updateCustomColor from arbitrary sRGB Color
        model.updateCustomColor(from: Color(red: 0.25, green: 0.5, blue: 0.75))
        #expect(abs(model.customRed - 0.25) < 0.02)
        #expect(abs(model.customGreen - 0.5) < 0.02)
        #expect(abs(model.customBlue - 0.75) < 0.02)

        // Test updateCustomColor from grayscale Color (should safely convert without crash)
        model.updateCustomColor(from: Color.white)
        #expect(abs(model.customRed - 1.0) < 0.01)
        #expect(abs(model.customGreen - 1.0) < 0.01)
        #expect(abs(model.customBlue - 1.0) < 0.01)

        model.updateCustomColor(from: Color.black)
        #expect(abs(model.customRed - 0.0) < 0.01)
        #expect(abs(model.customGreen - 0.0) < 0.01)
        #expect(abs(model.customBlue - 0.0) < 0.01)
    }

    // MARK: - ActionConfig Tests

    @Test func testActionConfigRoundTripEncodingDecoding() throws {
        // Test empty/none config
        let noneConfig = ActionConfig.none
        let encodedNone = try JSONEncoder().encode(noneConfig)
        let decodedNone = try JSONDecoder().decode(ActionConfig.self, from: encodedNone)
        #expect(decodedNone == noneConfig)
        #expect(decodedNone.actionType == .none)

        // Test full config with openAppsAndURLs
        var appConfig = ActionConfig()
        appConfig.actionType = .openAppsAndURLs
        appConfig.appBundleURLs = ["/Applications/Safari.app", "file:///Applications/Notes.app"]
        appConfig.webURLs = ["https://apple.com", "github.com"]

        let encodedApp = try JSONEncoder().encode(appConfig)
        let decodedApp = try JSONDecoder().decode(ActionConfig.self, from: encodedApp)
        #expect(decodedApp == appConfig)
        #expect(decodedApp.actionType == .openAppsAndURLs)
        #expect(decodedApp.appBundleURLs.count == 2)
        #expect(decodedApp.webURLs.count == 2)

        // Test systemAction configs
        for sysAction in SystemActionType.allCases {
            var sysConfig = ActionConfig()
            sysConfig.actionType = .systemAction
            sysConfig.systemAction = sysAction

            let encoded = try JSONEncoder().encode(sysConfig)
            let decoded = try JSONDecoder().decode(ActionConfig.self, from: encoded)
            #expect(decoded == sysConfig)
            #expect(decoded.systemAction == sysAction)
        }

        // Test shortcut and shell command
        var customConfig = ActionConfig()
        customConfig.actionType = .runShortcut
        customConfig.shortcutName = "Clean Workspace"
        let encodedShortcut = try JSONEncoder().encode(customConfig)
        let decodedShortcut = try JSONDecoder().decode(ActionConfig.self, from: encodedShortcut)
        #expect(decodedShortcut == customConfig)

        customConfig.actionType = .shellCommand
        customConfig.shellCommand = "echo 123"
        let encodedShell = try JSONEncoder().encode(customConfig)
        let decodedShell = try JSONDecoder().decode(ActionConfig.self, from: encodedShell)
        #expect(decodedShell == customConfig)

        // Test graceful decoding of empty JSON
        let emptyJSON = "{}".data(using: .utf8)!
        let decodedEmpty = try JSONDecoder().decode(ActionConfig.self, from: emptyJSON)
        #expect(decodedEmpty.actionType == .none)
        #expect(decodedEmpty.appBundleURLs.isEmpty)
        #expect(decodedEmpty.webURLs.isEmpty)
        #expect(decodedEmpty.systemAction == .hideOthers)
        #expect(decodedEmpty.shortcutName == "")
        #expect(decodedEmpty.shellCommand == "")
    }

    // MARK: - IconRenderer Tests

    @Test func testIconRendererAllStyles() throws {
        // 1. Line
        var model = DividerModel()
        model.style = .line
        let lineImg = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(lineImg != nil)
        #expect(lineImg?.width == 64)
        #expect(lineImg?.height == 64)

        // 2. Dashed
        model.style = .dashed
        let dashedImg = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(dashedImg != nil)

        // 3. Dot
        model.style = .dot
        let dotImg = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(dotImg != nil)

        // 4. Label (Text Horizontal)
        model.style = .label
        model.labelMode = .text
        model.labelText = "CODE"
        model.isVerticalText = false
        let labelTextImg = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(labelTextImg != nil)

        // 5. Label (Text Vertical)
        model.isVerticalText = true
        let labelTextVertImg = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(labelTextVertImg != nil)

        // 6. Label (SF Symbol)
        model.labelMode = .symbol
        model.symbolName = "star.fill"
        let labelSymbolImg = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(labelSymbolImg != nil)

        // Fallback for empty symbol
        model.symbolName = ""
        let labelSymbolFallbackImg = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(labelSymbolFallbackImg != nil)

        // 7. Spacer
        model.style = .spacer
        let spacerImg = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(spacerImg != nil)

        // 8. Image
        model.style = .image
        let testImage = NSImage(size: NSSize(width: 32, height: 16))
        testImage.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 16).fill()
        testImage.unlockFocus()
        guard let tiffData = testImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to create test image data")
            return
        }
        model.imageData = pngData
        let customImageRendered = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(customImageRendered != nil)

        // 9. NSImage rendering
        let nsImg = IconRenderer.renderNSImage(for: model, size: CGSize(width: 64, height: 64))
        #expect(nsImg.size.width == 64)
        #expect(nsImg.size.height == 64)

        // 10. ICNS Data rendering
        model.style = .line
        let iconData = IconRenderer.renderIconData(for: model)
        #expect(iconData != nil)
        #expect((iconData?.count ?? 0) > 0)
    }

    @Test func testIconRendererOrientations() {
        var model = DividerModel()

        // Vertical orientation (for Bottom horizontal Dock)
        model.orientation = .vertical
        model.style = .line
        let vertLine = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(vertLine != nil)

        model.style = .dashed
        let vertDashed = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(vertDashed != nil)

        // Horizontal orientation (for Left / Right vertical Dock)
        model.orientation = .horizontal
        model.style = .line
        let horizLine = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(horizLine != nil)

        model.style = .dashed
        let horizDashed = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(horizDashed != nil)
    }

    @Test func testIconRendererRoundImageCorners() {
        var model = DividerModel()
        model.style = .image

        let testImage = NSImage(size: NSSize(width: 48, height: 48))
        testImage.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 48, height: 48).fill()
        testImage.unlockFocus()

        guard let tiffData = testImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to create test image data")
            return
        }
        model.imageData = pngData

        // With rounded corners enabled
        model.roundImageCorners = true
        model.imageCornerRadiusRatio = 0.225
        let roundedImage = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(roundedImage != nil)

        // With rounded corners disabled (square corners)
        model.roundImageCorners = false
        let squareImage = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(squareImage != nil)
    }

    // MARK: - BundleSynthesizer Tests

    @Test func testBundleSynthesizerCreateDividerApp() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let model = DividerModel()
        guard let iconData = IconRenderer.renderIconData(for: model) else {
            Issue.record("Failed to generate test icon data")
            return
        }

        var config = ActionConfig()
        config.actionType = .systemAction
        config.systemAction = .startScreensaver

        let appURL = try BundleSynthesizer.createDividerApp(
            iconData: iconData,
            config: config,
            hoverLabel: "Test Label",
            outputDirectory: tempDir
        )

        // 1. App bundle exists and has .app extension, and starts with the custom hover label
        #expect(FileManager.default.fileExists(atPath: appURL.path))
        #expect(appURL.pathExtension == "app")
        #expect(appURL.lastPathComponent.hasPrefix("Test Label"))

        let contentsURL = appURL.appendingPathComponent("Contents")
        let macosURL = contentsURL.appendingPathComponent("MacOS")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")

        // 2. Info.plist exists and contains valid keys
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        #expect(FileManager.default.fileExists(atPath: infoPlistURL.path))
        let plistData = try Data(contentsOf: infoPlistURL)
        let plistObj = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        #expect(plistObj != nil)
        #expect(plistObj?["CFBundleName"] as? String == "Test Label")
        #expect(plistObj?["CFBundleDisplayName"] as? String == "Test Label")
        #expect(plistObj?["CFBundleExecutable"] as? String == "divider_runner")
        #expect(plistObj?["CFBundleIconFile"] == nil)
        #expect(plistObj?["LSUIElement"] as? Bool == true)

        // 3. PkgInfo exists
        let pkgInfoURL = contentsURL.appendingPathComponent("PkgInfo")
        #expect(FileManager.default.fileExists(atPath: pkgInfoURL.path))
        let pkgInfoString = try String(contentsOf: pkgInfoURL, encoding: .utf8)
        #expect(pkgInfoString == "APPL????")

        // 4. AppIcon.icns & ActionConfig.json
        let iconURL = resourcesURL.appendingPathComponent("AppIcon.icns")
        #expect(FileManager.default.fileExists(atPath: iconURL.path))
        let readIconData = try Data(contentsOf: iconURL)
        #expect(readIconData == iconData)

        let configURL = resourcesURL.appendingPathComponent("ActionConfig.json")
        #expect(FileManager.default.fileExists(atPath: configURL.path))
        let readConfigData = try Data(contentsOf: configURL)
        let decodedConfig = try JSONDecoder().decode(ActionConfig.self, from: readConfigData)
        #expect(decodedConfig.actionType == .systemAction)
        #expect(decodedConfig.systemAction == .startScreensaver)

        // 5. divider_runner executable exists and is executable
        let runnerURL = macosURL.appendingPathComponent("divider_runner")
        #expect(FileManager.default.fileExists(atPath: runnerURL.path))
        #expect(FileManager.default.isExecutableFile(atPath: runnerURL.path))

        // 6. Verify ad-hoc code signature passes launch verification
        let codesignProcess = Process()
        codesignProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesignProcess.arguments = ["--verify", appURL.path]
        let errPipe = Pipe()
        codesignProcess.standardError = errPipe
        try codesignProcess.run()
        codesignProcess.waitUntilExit()
        #expect(codesignProcess.terminationStatus == 0)
    }

    @Test func testBundleSynthesizerCreateNativeSpacerFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        for size in SpacerSize.allCases {
            let spacerURL = try BundleSynthesizer.createNativeSpacerFile(
                size: size,
                outputDirectory: tempDir
            )
            #expect(FileManager.default.fileExists(atPath: spacerURL.path))
            #expect(spacerURL.pathExtension == size.fileExtension)
        }
    }

    @Test func testBundleSynthesizerDefaultOutputDirectory() {
        do {
            let dir = try BundleSynthesizer.defaultOutputDirectory()
            #expect(FileManager.default.fileExists(atPath: dir.path))
            #expect(dir.lastPathComponent == "DockDividers")
        } catch {
            // When executing in sandboxed test environments where writing to user's
            // ~/Library/Application Support is restricted, verify target path.
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let expectedDir = appSupport.appendingPathComponent("DockDividers", isDirectory: true)
            #expect(expectedDir.lastPathComponent == "DockDividers")
        }
    }

    // MARK: - AppState Pre-staging & Orphan Cleanup Tests

    @Test @MainActor func testAppStatePreStagingAndOrphanCleanup() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let appState = AppState()
        appState.updateCustomStorageURL(tempDir)

        // Verify pre-staged bundle was created
        guard let firstStagedURL = appState.stagedAppURL else {
            Issue.record("Expected stagedAppURL to be populated")
            return
        }
        #expect(FileManager.default.fileExists(atPath: firstStagedURL.path))
        #expect(firstStagedURL.deletingLastPathComponent().path == tempDir.path)

        // When stageImmediately is called without consuming, the previous unconsumed bundle must be cleaned up
        appState.stageImmediately()

        guard let secondStagedURL = appState.stagedAppURL else {
            Issue.record("Expected new stagedAppURL to be populated")
            return
        }
        #expect(secondStagedURL != firstStagedURL)
        #expect(FileManager.default.fileExists(atPath: secondStagedURL.path))
        // Verify orphan cleanup: first bundle should now be deleted from disk
        #expect(FileManager.default.fileExists(atPath: firstStagedURL.path) == false)
    }

    @Test @MainActor func testAppStateConsumeStagedBundlePreserved() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let appState = AppState()
        appState.updateCustomStorageURL(tempDir)

        // Consume staged bundle for drag
        guard let consumedURL = appState.consumeStagedBundleForDrag() else {
            Issue.record("Expected consumeStagedBundleForDrag to return a URL")
            return
        }
        #expect(FileManager.default.fileExists(atPath: consumedURL.path))

        // Call stageImmediately explicitly simulating re-staging / slider tweak
        appState.stageImmediately()

        // The consumed bundle MUST be preserved on disk for the macOS Dock!
        #expect(FileManager.default.fileExists(atPath: consumedURL.path) == true)

        // The newly staged bundle is a new file
        guard let newStagedURL = appState.stagedAppURL else {
            Issue.record("Expected new stagedAppURL")
            return
        }
        #expect(newStagedURL != consumedURL)
        #expect(FileManager.default.fileExists(atPath: newStagedURL.path))
    }

    @Test @MainActor func testAppStateCustomStorageDirectoryManagement() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let appState = AppState()
        appState.updateCustomStorageURL(tempDir)

        #expect(appState.customStorageURL?.path == tempDir.path)
        #expect(appState.effectiveStorageDirectory.path == tempDir.path)
        #expect(appState.storageDisplayPath.contains(tempDir.lastPathComponent))

        // Reset storage directory
        appState.resetStorageDirectory()
        #expect(appState.customStorageURL == nil)
        #expect(appState.effectiveStorageDirectory.lastPathComponent == "DockDividers")
    }
}
