//
//  DockDividerTests.swift
//  DockDividerTests
//
//  Created by Jack Bogle on 10/27/26.
//

import Testing
import SwiftUI
import AppKit
import ImageIO
@testable import DockDivider

// Staging tests launch `codesign` subprocesses and apply Finder icons through
// IconServices. Running them concurrently can crash the AppKit test host on CI,
// so keep the suite serialized.
@Suite(.serialized)
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
        #expect(ColorPreset.adaptiveWhite.rawValue == "adaptiveWhite")
        #expect(ColorPreset.dark.rawValue == "dark")
        #expect(ColorPreset.custom.rawValue == "custom")

        // Test decoding backward compatibility: "White" and "Light"
        let whiteJSON = "\"White\"".data(using: .utf8)!
        let decodedWhite = try JSONDecoder().decode(ColorPreset.self, from: whiteJSON)
        #expect(decodedWhite == .adaptiveWhite)

        let lightJSON = "\"Light\"".data(using: .utf8)!
        let decodedLight = try JSONDecoder().decode(ColorPreset.self, from: lightJSON)
        #expect(decodedLight == .adaptiveWhite)
    }

    @Test func testStableWireValuesDecodeLegacyNames() throws {
        func decode<T: Decodable>(_ type: T.Type, _ rawValue: String) throws -> T {
            try JSONDecoder().decode(T.self, from: Data("\"\(rawValue)\"".utf8))
        }

        #expect(try decode(DividerStyle.self, "Line") == DividerStyle.line)
        #expect(try decode(DividerStyle.self, "Dashed") == DividerStyle.dashed)
        #expect(try decode(DividerStyle.self, "Image") == DividerStyle.image)

        #expect(try decode(LabelMode.self, "Text") == LabelMode.text)
        #expect(try decode(LabelMode.self, "SF Symbol") == LabelMode.symbol)

        #expect(try decode(ColorPreset.self, "AdaptiveWhite") == ColorPreset.adaptiveWhite)
        #expect(try decode(ColorPreset.self, "Dark") == ColorPreset.dark)
        #expect(try decode(ColorPreset.self, "Custom") == ColorPreset.custom)

        #expect(try decode(DividerOrientation.self, "Vertical") == DividerOrientation.vertical)
        #expect(try decode(DividerOrientation.self, "Horizontal") == DividerOrientation.horizontal)

        #expect(try decode(SpacerSize.self, "Full") == SpacerSize.regular)
        #expect(try decode(SpacerSize.self, "Half") == SpacerSize.small)
        #expect(try decode(SpacerSize.self, "Flexible") == SpacerSize.flex)

        // New wire values keep decoding after the display names change.
        #expect(try decode(DividerStyle.self, "line") == DividerStyle.line)
        #expect(try decode(SpacerSize.self, "small") == SpacerSize.small)
    }

    @Test func testDraftPersistenceRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockDividerDraftTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        var model = DividerModel()
        model.style = .label
        model.colorPreset = .custom
        model.labelText = "SAVE"
        model.customRed = 0.25
        model.customGreen = 0.5
        model.customBlue = 0.75
        model.imageID = UUID()
        model.imageData = Data([0x01, 0x02, 0x03, 0x04])

        DraftPersistence.save(model, to: directory)

        #expect(FileManager.default.fileExists(atPath: DraftPersistence.url(in: directory).path))

        let loaded = try #require(DraftPersistence.load(from: directory))
        #expect(loaded == model)
    }

    @Test func testDraftPersistenceKeepsArtworkOutOfJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockDividerDraftImageTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        var model = DividerModel()
        model.style = .image
        model.imageID = UUID()
        model.imageData = Data(repeating: 0xAB, count: 4096)

        DraftPersistence.save(model, to: directory)

        let jsonData = try Data(contentsOf: DraftPersistence.url(in: directory))
        let jsonText = String(decoding: jsonData, as: UTF8.self)
        #expect(!jsonText.contains("imageData"))
        #expect(jsonData.count < model.imageData!.count)
        #expect(FileManager.default.fileExists(
            atPath: DraftPersistence.imageURL(in: directory).path
        ))

        let loaded = try #require(DraftPersistence.load(from: directory))
        #expect(loaded.imageData == model.imageData)
        #expect(loaded.imageID == model.imageID)
    }

    @Test func testDraftPersistenceRemovesArtworkWhenCleared() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockDividerDraftImageClearTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        var model = DividerModel()
        model.style = .image
        model.imageID = UUID()
        model.imageData = Data(repeating: 0xCD, count: 2048)
        DraftPersistence.save(model, to: directory)
        #expect(FileManager.default.fileExists(
            atPath: DraftPersistence.imageURL(in: directory).path
        ))

        model.imageData = nil
        model.imageID = nil
        DraftPersistence.save(model, to: directory)

        #expect(!FileManager.default.fileExists(
            atPath: DraftPersistence.imageURL(in: directory).path
        ))
        let loaded = try #require(DraftPersistence.load(from: directory))
        #expect(loaded.imageData == nil)
    }

    @Test func testBoundedProcessCapturesOutput() {
        let result = BoundedProcess.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf hello"],
            timeout: 5
        )

        #expect(result?.timedOut == false)
        #expect(result?.outputText == "hello")
        #expect(result?.terminationStatus == 0)
    }

    @Test func testBoundedProcessEscalatesToKillWhenTermIsIgnored() {
        let start = Date()
        let result = BoundedProcess.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "trap '' TERM; while true; do sleep 0.05; done"],
            timeout: 0.2
        )
        let elapsed = Date().timeIntervalSince(start)

        #expect(result?.timedOut == true)
        #expect(elapsed < 5)
    }

    @Test func testLiveManagedItemCountMatchesLiveBundles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockDividerLiveCountTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let divider = directory.appendingPathComponent("Divider.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: divider.appendingPathComponent("Contents/Resources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try BundleMarker.write(BundleMarker.makeCurrent(), to: divider)

        let unrelated = directory.appendingPathComponent("Unrelated.app", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)

        let spacer = directory.appendingPathComponent("Spacer-Test.dockspace")
        FileManager.default.createFile(atPath: spacer.path, contents: Data())

        let livePaths: Set<String> = [
            StoragePath.canonical(divider),
            StoragePath.canonical(unrelated),
            StoragePath.canonical(spacer)
        ]

        #expect(StorageMaintenance.liveManagedItemCount(in: directory, livePaths: livePaths) == 2)
        #expect(StorageMaintenance.liveManagedItemCount(in: directory, livePaths: []) == 0)
    }

    @Test func testAppStateLoadsPersistedDraft() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockDividerDraftStateTests-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "DockDividerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var saved = DividerModel()
        saved.labelText = "RESTORED"
        saved.style = .dashed
        DraftPersistence.save(saved, to: root)

        let appState = AppState(
            environment: AppEnvironment(
                userDefaults: defaults,
                applicationSupportDirectory: root,
                repairOnLaunch: false,
                stagesOnLaunch: false,
                stagesOnDraftChanges: false,
                registerWithLaunchServices: false,
                stagingDebounce: 0,
                persistsDraft: true,
                liveSet: .unavailable,
                appliesFinderIcons: false
            )
        )

        #expect(appState.draft.labelText == "RESTORED")
        #expect(appState.draft.style == .dashed)
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

    @Test func testResetAppearanceLeavesStyleAndActionAlone() {
        var model = DividerModel()
        model.style = .dashed
        model.colorPreset = .dark
        model.opacity = 0.95
        model.thickness = 4.0
        model.heightRatio = 0.3
        model.verticalOffset = 12.0
        model.hoverLabel = "Custom Label"
        model.actionConfig.actionType = .runShortcut
        model.actionConfig.shortcutName = "Focus"

        model.resetAppearance()

        #expect(model.style == .dashed)
        #expect(model.hoverLabel == "Custom Label")
        #expect(model.actionConfig.actionType == .runShortcut)
        #expect(model.actionConfig.shortcutName == "Focus")
        #expect(model.colorPreset == .adaptiveWhite)
        #expect(model.opacity == 0.80)
        #expect(model.thickness == 1.5)
        #expect(model.heightRatio == 0.65)
        #expect(model.verticalOffset == 0.0)
    }

    @Test func testValidationWarnsOnlyForConfigurationsThatDoNothing() {
        var model = DividerModel()
        #expect(model.validationWarning == nil)

        model.style = .image
        #expect(model.validationWarning != nil)
        model.imageData = Data([0x01])
        #expect(model.validationWarning == nil)

        model.style = .line
        model.actionConfig.actionType = .runShortcut
        #expect(model.validationWarning != nil)
        model.actionConfig.shortcutName = "Focus"
        #expect(model.validationWarning == nil)

        model.actionConfig.actionType = .shellCommand
        #expect(model.validationWarning != nil)
        model.actionConfig.shellCommand = "echo hello"
        #expect(model.validationWarning == nil)

        model.actionConfig.actionType = .openAppsAndURLs
        #expect(model.validationWarning != nil)
        model.actionConfig.webURLs = ["https://example.com"]
        #expect(model.validationWarning == nil)
    }

    @Test func testStorageLocationWarningForAppContainer() {
        let suiteName = "DockDividerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let containerSupport = home.appendingPathComponent(
            "Library/Containers/me.bogle.DockDivider/Data/Library/Application Support",
            isDirectory: true
        )

        let store = StorageLocationStore(
            userDefaults: defaults,
            applicationSupportDirectory: containerSupport
        )

        #expect(store.isUsingDefaultStorageLocation)
        #expect(store.storageLocationWarning != nil)

        let customRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockDividerStorageTests-\(UUID().uuidString)", isDirectory: true)
        store.updateCustomStorageURL(customRoot)
        #expect(!store.isUsingDefaultStorageLocation)
        #expect(store.storageLocationWarning == nil)
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
        #expect(decodedEmpty.schemaVersion == ActionConfig.currentSchemaVersion)
        #expect(decodedEmpty.appBundleURLs.isEmpty)
        #expect(decodedEmpty.webURLs.isEmpty)
        #expect(decodedEmpty.systemAction == .hideOthers)
        #expect(decodedEmpty.shortcutName == "")
        #expect(decodedEmpty.shellCommand == "")
    }

    @Test func testUnavailableSystemActionsAreHidden() {
        #expect(SystemActionType.hideOthers.isAvailable)
        for action in SystemActionType.availableCases {
            #expect(action.isAvailable)
        }

        let launchpadExists = FileManager.default.fileExists(
            atPath: SystemActionType.launchpadPath
        )
        #expect(SystemActionType.launchpad.isAvailable == launchpadExists)
        #expect(SystemActionType.availableCases.contains(.launchpad) == launchpadExists)

        if !launchpadExists {
            #expect(SystemActionType.launchpad.unavailableReason?.isEmpty == false)
        }
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

    @Test func testIconDataIncludes1024PixelSlot() throws {
        var model = DividerModel()
        model.style = .line

        guard let iconData = IconRenderer.renderIconData(for: model) else {
            Issue.record("Failed to render icon data")
            return
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockDividerIconTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let icnsURL = directory.appendingPathComponent("AppIcon.icns")
        let iconsetURL = directory.appendingPathComponent("AppIcon.iconset")
        try iconData.write(to: icnsURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "iconset", icnsURL.path, "-o", iconsetURL.path]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, "iconutil failed: \(output)")

        let retinaURL = iconsetURL.appendingPathComponent("icon_512x512@2x.png")
        #expect(FileManager.default.fileExists(atPath: retinaURL.path))

        guard let source = CGImageSourceCreateWithURL(retinaURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            Issue.record("Failed to read the 1024 px slot produced by iconutil")
            return
        }
        #expect(image.width == 1024)
        #expect(image.height == 1024)
    }

    @Test func testLineRendersWithinExpectedPixelBounds() {
        var model = DividerModel()
        model.style = .line
        model.orientation = .vertical
        model.heightRatio = 0.5
        model.thickness = 2.0
        model.opacity = 1.0

        let pixelSize = 128
        guard let image = IconRenderer.renderCGImage(for: model, pixelSize: pixelSize),
              let bounds = opaquePixelBounds(of: image) else {
            Issue.record("Expected a visible line")
            return
        }

        let expectedLength = Double(pixelSize) * model.heightRatio
        let expectedThickness = model.thickness * (Double(pixelSize) / 64.0)
        let renderedLength = Double(bounds.maxY - bounds.minY + 1)
        let renderedThickness = Double(bounds.maxX - bounds.minX + 1)

        #expect(abs(renderedLength - expectedLength) <= 2.0)
        #expect(abs(renderedThickness - expectedThickness) <= 2.0)
        #expect(bounds.minX > 0 && bounds.maxX < pixelSize - 1)
    }

    @Test func testLongLabelStaysInsideCanvas() {
        var model = DividerModel()
        model.style = .label
        model.labelMode = .text
        model.labelText = "WWWW"
        model.isVerticalText = false
        model.heightRatio = 0.65
        model.opacity = 1.0

        let pixelSize = 64
        guard let image = IconRenderer.renderCGImage(for: model, pixelSize: pixelSize),
              let bounds = opaquePixelBounds(of: image) else {
            Issue.record("Expected visible label text")
            return
        }

        let drawnWidth = bounds.maxX - bounds.minX + 1
        let drawnHeight = bounds.maxY - bounds.minY + 1
        #expect(drawnWidth <= Int(Double(pixelSize) * 0.95))
        #expect(drawnHeight <= Int(Double(pixelSize) * 0.95))
        #expect(bounds.minX >= 0 && bounds.maxX < pixelSize)
        #expect(bounds.minY >= 0 && bounds.maxY < pixelSize)
    }

    @Test func testRenderCacheIgnoresActionOnlyChanges() {
        RenderCache.shared.removeAll()

        var model = DividerModel()
        model.style = .dashed
        model.hoverLabel = "First"
        model.actionConfig.actionType = .shellCommand
        model.actionConfig.shellCommand = "echo first"

        let first = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(first != nil)
        #expect(RenderCache.shared.imageMisses == 1)

        model.hoverLabel = "Second"
        model.actionConfig.shellCommand = "echo second"

        let second = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(second === first)
        #expect(RenderCache.shared.imageMisses == 1)

        model.thickness = 3.0
        _ = IconRenderer.renderCGImage(for: model, pixelSize: 64)
        #expect(RenderCache.shared.imageMisses == 2)
    }

    @Test func testCustomImageProcessorDownsamplesLargeImages() throws {
        guard let pngData = makeTestPNGData(width: 2000, height: 1000) else {
            Issue.record("Failed to create a large test image")
            return
        }

        let processed = try CustomImageProcessor.process(data: pngData)
        #expect(processed.pixelWidth == 1024)
        #expect(processed.pixelHeight == 512)
        #expect(processed.data.count < pngData.count)
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
            outputDirectory: tempDir,
            registerWithLaunchServices: false
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
        #expect(plistObj?["CFBundleVersion"] as? String == "1.0")
        #expect(plistObj?["CFBundleShortVersionString"] as? String == "1.0")
        #expect(plistObj?["CFBundleInfoDictionaryVersion"] as? String == "6.0")
        #expect(plistObj?["NSHighResolutionCapable"] as? Bool == true)
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

        // 5. Every generated bundle carries an ownership marker
        let marker = BundleMarker.read(from: appURL)
        #expect(marker?.schemaVersion == BundleMarker.currentSchemaVersion)
        #expect(marker?.runnerVersion == BundleMarker.currentRunnerVersion)
        #expect(marker?.appVersion.isEmpty == false)
        #expect(BundleMarker.isDockDividerBundle(at: appURL))

        // 6. divider_runner executable exists and is executable
        let runnerURL = macosURL.appendingPathComponent("divider_runner")
        #expect(FileManager.default.fileExists(atPath: runnerURL.path))
        #expect(FileManager.default.isExecutableFile(atPath: runnerURL.path))

        // 7. Verify ad-hoc code signature passes launch verification
        let codesignProcess = Process()
        codesignProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesignProcess.arguments = ["--verify", appURL.path]
        let errPipe = Pipe()
        codesignProcess.standardError = errPipe
        try codesignProcess.run()
        codesignProcess.waitUntilExit()
        #expect(codesignProcess.terminationStatus == 0)
    }

    @Test func testHoverLabelSanitization() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        guard let iconData = IconRenderer.renderIconData(for: DividerModel()) else {
            Issue.record("Failed to create test icon data")
            return
        }

        // Test label with newlines, control characters, leading dot, and illegal path characters
        let dirtyLabel = "..My\nProject/Work:Space\u{0000}\u{0007}"
        let appURL = try BundleSynthesizer.createDividerApp(
            iconData: iconData,
            config: ActionConfig(actionType: .none),
            hoverLabel: dirtyLabel,
            outputDirectory: tempDir
        )

        #expect(FileManager.default.fileExists(atPath: appURL.path))
        #expect(!appURL.lastPathComponent.hasPrefix("."))

        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let plistData = try Data(contentsOf: infoPlistURL)
        let plistObj = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        let displayName = plistObj?["CFBundleDisplayName"] as? String ?? ""

        #expect(!displayName.hasPrefix("."))
        #expect(!displayName.contains("\n"))
        #expect(!displayName.contains("/"))
        #expect(!displayName.contains(":"))
        #expect(displayName.contains("MyProject-Work-Space"))
    }

    @Test func testImageStyleBundleStoresArtworkOutsideJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        guard let sourcePNG = makeTestPNGData(width: 96, height: 64, color: .systemPurple) else {
            Issue.record("Failed to create test artwork")
            return
        }
        let processed = try CustomImageProcessor.process(data: sourcePNG)

        var model = DividerModel()
        model.style = .image
        model.imageData = processed.data
        model.imageID = processed.imageID

        guard let iconData = IconRenderer.renderIconData(for: model) else {
            Issue.record("Failed to render image-style icon")
            return
        }

        let appURL = try BundleSynthesizer.createDividerApp(
            iconData: iconData,
            config: ActionConfig.none,
            hoverLabel: "Artwork",
            model: model,
            outputDirectory: tempDir,
            registerWithLaunchServices: false
        )

        let resourcesURL = appURL.appendingPathComponent("Contents/Resources")
        let customImageURL = resourcesURL.appendingPathComponent("CustomImage.png")
        let modelURL = resourcesURL.appendingPathComponent("DividerModel.json")

        #expect(FileManager.default.fileExists(atPath: customImageURL.path))
        #expect(try Data(contentsOf: customImageURL) == processed.data)

        let savedModelData = try Data(contentsOf: modelURL)
        let savedModel = try JSONDecoder().decode(DividerModel.self, from: savedModelData)
        #expect(savedModel.imageData == nil)
        #expect(savedModel.imageID == processed.imageID)

        let jsonObject = try JSONSerialization.jsonObject(with: savedModelData) as? [String: Any]
        #expect(jsonObject?["imageData"] == nil)
    }

    @Test func testDividerRunnerVersionMatchesMarker() throws {
        guard let runnerURL = BundleStagingService.locateRunnerExecutable() else {
            Issue.record("divider_runner was not found in the built products")
            return
        }

        let result = try runTestProcess(runnerURL, arguments: ["--version"])
        #expect(result.status == 0)
        #expect(result.output.contains("divider_runner \(BundleMarker.currentRunnerVersion)"))
    }

    @Test func testDividerRunnerNoneActionExitsPromptly() throws {
        guard let runnerURL = BundleStagingService.locateRunnerExecutable() else {
            Issue.record("divider_runner was not found in the built products")
            return
        }

        let bundle = try makeRunnerTestBundle(runnerURL: runnerURL, config: .none)
        defer { try? FileManager.default.removeItem(at: bundle.root) }

        let result = try runTestProcess(bundle.executableURL, arguments: [], timeout: 5)
        #expect(result.status == 0)
    }

    @Test func testDividerRunnerDoesNotWaitForShellCommand() async throws {
        guard let runnerURL = BundleStagingService.locateRunnerExecutable() else {
            Issue.record("divider_runner was not found in the built products")
            return
        }

        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockDividerRunner-\(UUID().uuidString)")
        var config = ActionConfig()
        config.actionType = .shellCommand
        config.shellCommand = "sleep 2; /usr/bin/touch '\(markerURL.path)'"

        let bundle = try makeRunnerTestBundle(runnerURL: runnerURL, config: config)
        defer {
            try? FileManager.default.removeItem(at: bundle.root)
            try? FileManager.default.removeItem(at: markerURL)
        }

        let started = Date()
        let result = try runTestProcess(bundle.executableURL, arguments: [], timeout: 5)
        let elapsed = Date().timeIntervalSince(started)

        #expect(result.status == 0)
        #expect(elapsed < 1.5, "divider_runner waited for the shell command")

        var markerExists = false
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: markerURL.path) {
                markerExists = true
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(markerExists, "The detached shell command never completed")
    }

    @Test @MainActor func testRepairUpdatesOutdatedRunner() async throws {
        guard BundleStagingService.locateRunnerExecutable() != nil else {
            Issue.record("divider_runner was not found in the built products")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = DividerModel()
        guard let iconData = IconRenderer.renderIconData(for: model) else {
            Issue.record("Failed to generate test icon data")
            return
        }

        let appURL = try BundleSynthesizer.createDividerApp(
            iconData: iconData,
            config: ActionConfig.none,
            hoverLabel: "Runner",
            model: model,
            outputDirectory: tempDir,
            registerWithLaunchServices: false
        )

        guard var marker = BundleMarker.read(from: appURL) else {
            Issue.record("Expected a bundle marker")
            return
        }
        marker.runnerVersion = "0"
        try BundleMarker.write(marker, to: appURL)

        let execURL = appURL.appendingPathComponent("Contents/MacOS/divider_runner")
        try Data("stale runner".utf8).write(to: execURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: execURL.path
        )

        let repairPlans = BundleSynthesizer.repairPlans(in: [tempDir])
        for plan in repairPlans {
            await BundleSynthesizer.applyRepair(plan)
        }

        #expect(BundleMarker.read(from: appURL)?.runnerVersion == BundleMarker.currentRunnerVersion)
        // Re-signing rewrites the executable's embedded signature, so compare
        // shape rather than exact bytes.
        let repairedRunnerData = try Data(contentsOf: execURL)
        #expect(repairedRunnerData != Data("stale runner".utf8))
        #expect(repairedRunnerData.count > 1024)
        #expect(FileManager.default.isExecutableFile(atPath: execURL.path))
    }

    @Test @MainActor func testRepairLeavesUnmarkedLegacyRunnerAlone() async throws {
        guard BundleStagingService.locateRunnerExecutable() != nil else {
            Issue.record("divider_runner was not found in the built products")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var model = DividerModel()
        model.orientation = DividerOrientation.currentSystemDockOrientation

        guard let iconData = IconRenderer.renderIconData(for: model) else {
            Issue.record("Failed to generate test icon data")
            return
        }

        let appURL = try BundleSynthesizer.createDividerApp(
            iconData: iconData,
            config: ActionConfig.none,
            hoverLabel: "Legacy",
            model: model,
            outputDirectory: tempDir,
            registerWithLaunchServices: false
        )

        // Simulate a bundle written before ownership markers existed.
        try FileManager.default.removeItem(at: BundleMarker.url(for: appURL))

        let iconForkURL = appURL.appendingPathComponent("Icon\r")
        if !FileManager.default.fileExists(atPath: iconForkURL.path) {
            FileManager.default.createFile(atPath: iconForkURL.path, contents: Data())
        }

        let execURL = appURL.appendingPathComponent("Contents/MacOS/divider_runner")
        let staleRunner = Data("legacy runner".utf8)
        try staleRunner.write(to: execURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: execURL.path
        )

        let repairPlans = BundleSynthesizer.repairPlans(in: [tempDir])
        for plan in repairPlans {
            await BundleSynthesizer.applyRepair(plan)
        }

        // A runner upgrade alone must not pull every legacy bundle into a
        // re-signing pass; another repair will migrate it later.
        #expect(!BundleMarker.exists(at: appURL))
        #expect(try Data(contentsOf: execURL) == staleRunner)
    }

    @Test @MainActor func testRepairPlansReportsOnlyBundlesThatNeedWork() async throws {
        guard BundleStagingService.locateRunnerExecutable() != nil else {
            Issue.record("divider_runner was not found in the built products")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var model = DividerModel()
        model.orientation = DividerOrientation.currentSystemDockOrientation

        guard let iconData = IconRenderer.renderIconData(for: model) else {
            Issue.record("Failed to generate test icon data")
            return
        }

        let appURL = try BundleSynthesizer.createDividerApp(
            iconData: iconData,
            config: ActionConfig.none,
            hoverLabel: "Healthy",
            model: model,
            outputDirectory: tempDir,
            registerWithLaunchServices: false
        )

        // A bundle written by the current build needs no work.
        #expect(BundleSynthesizer.repairPlans(in: [tempDir]).isEmpty)

        // An ownership marker from an older runner is enough to plan a repair.
        guard var marker = BundleMarker.read(from: appURL) else {
            Issue.record("Expected a bundle marker")
            return
        }
        marker.runnerVersion = "0"
        try BundleMarker.write(marker, to: appURL)

        let plans = BundleSynthesizer.repairPlans(in: [tempDir])
        #expect(plans.count == 1)
        #expect(plans.first?.bundleURL.standardizedFileURL == appURL.standardizedFileURL)
        #expect(plans.first?.copyRunner == true)
        #expect(plans.first?.writeMarker == true)
    }

    @Test @MainActor func testBundleRepairerThrottlesRepeatPasses() async throws {
        guard BundleStagingService.locateRunnerExecutable() != nil else {
            Issue.record("divider_runner was not found in the built products")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var model = DividerModel()
        model.orientation = DividerOrientation.currentSystemDockOrientation

        guard let iconData = IconRenderer.renderIconData(for: model) else {
            Issue.record("Failed to generate test icon data")
            return
        }

        let appURL = try BundleSynthesizer.createDividerApp(
            iconData: iconData,
            config: ActionConfig.none,
            hoverLabel: "Throttle",
            model: model,
            outputDirectory: tempDir,
            registerWithLaunchServices: false
        )

        func markStale() throws {
            guard var marker = BundleMarker.read(from: appURL) else {
                Issue.record("Expected a bundle marker")
                return
            }
            marker.runnerVersion = "0"
            try BundleMarker.write(marker, to: appURL)
        }

        // The injected provider keeps the pass inside the temporary folder and
        // away from the real legacy sandbox folder.
        let directoryOnlyProvider: @MainActor (URL) -> [URL] = { _ in [tempDir] }
        let repairer = BundleRepairer(
            isEnabled: true,
            minimumInterval: 3600,
            directories: directoryOnlyProvider
        )

        try markStale()
        await repairer.repairExistingBundles(in: tempDir, excluding: nil)
        #expect(BundleMarker.read(from: appURL)?.runnerVersion == BundleMarker.currentRunnerVersion)

        // A second activation inside the interval must not re-scan the folder.
        try markStale()
        await repairer.repairExistingBundles(in: tempDir, excluding: nil)
        #expect(BundleMarker.read(from: appURL)?.runnerVersion == "0")

        // A pass with no throttle still repairs it.
        let immediateRepairer = BundleRepairer(
            isEnabled: true,
            minimumInterval: 0,
            directories: directoryOnlyProvider
        )
        await immediateRepairer.repairExistingBundles(in: tempDir, excluding: nil)
        #expect(BundleMarker.read(from: appURL)?.runnerVersion == BundleMarker.currentRunnerVersion)
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

    @Test func testBundleSynthesizerDefaultOutputDirectory() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let dir = try BundleSynthesizer.defaultOutputDirectory(applicationSupportDirectory: tempRoot)
        #expect(FileManager.default.fileExists(atPath: dir.path))
        #expect(dir.lastPathComponent == StorageLayout.folderName)
        #expect(dir.path.hasPrefix(tempRoot.path))
    }

    // MARK: - AppState Isolation & Storage Tests

    @Test @MainActor func testAppStatePreStagingAndOrphanCleanup() async throws {
        let harness = try AppStateTestHarness()
        defer { harness.tearDown() }

        let appState = harness.appState
        appState.updateCustomStorageURL(harness.root)
        await appState.awaitStagingCompletion()

        // Verify pre-staged bundle was created in the dedicated subfolder
        guard let firstStagedURL = appState.stagedAppURL else {
            Issue.record("Expected stagedAppURL to be populated")
            return
        }
        #expect(FileManager.default.fileExists(atPath: firstStagedURL.path))
        #expect(firstStagedURL.deletingLastPathComponent().path == harness.expectedStorageDirectory.path)

        // When stageImmediately is called without consuming, the previous unconsumed bundle must be cleaned up
        appState.stageImmediately()
        #expect(appState.isStaging)
        await appState.awaitStagingCompletion()

        guard let secondStagedURL = appState.stagedAppURL else {
            Issue.record("Expected new stagedAppURL to be populated")
            return
        }
        #expect(secondStagedURL != firstStagedURL)
        #expect(FileManager.default.fileExists(atPath: secondStagedURL.path))
        // Verify orphan cleanup: first bundle should now be deleted from disk
        #expect(FileManager.default.fileExists(atPath: firstStagedURL.path) == false)
    }

    @Test @MainActor func testAppStateConsumeStagedBundlePreserved() async throws {
        let harness = try AppStateTestHarness()
        defer { harness.tearDown() }

        let appState = harness.appState
        appState.updateCustomStorageURL(harness.root)
        await appState.awaitStagingCompletion()

        // Consume staged bundle for drag
        guard let consumedURL = appState.consumeStagedBundleForDrag() else {
            Issue.record("Expected consumeStagedBundleForDrag to return a URL")
            return
        }
        #expect(FileManager.default.fileExists(atPath: consumedURL.path))
        #expect(appState.isStaging)

        await appState.awaitStagingCompletion()

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

    @Test @MainActor func testRapidEditsPublishOnlyLatestRevision() async throws {
        let harness = try AppStateTestHarness()
        defer { harness.tearDown() }

        let appState = harness.appState
        appState.updateCustomStorageURL(harness.root)
        await appState.awaitStagingCompletion()

        appState.draft.hoverLabel = "First"
        appState.stageImmediately()
        appState.draft.hoverLabel = "Second"
        appState.stageImmediately()

        await appState.awaitStagingCompletion()

        guard let stagedURL = appState.stagedAppURL else {
            Issue.record("Expected a staged bundle after rapid edits")
            return
        }

        let modelURL = stagedURL
            .appendingPathComponent("Contents/Resources/DividerModel.json")
        let data = try Data(contentsOf: modelURL)
        let stagedModel = try JSONDecoder().decode(DividerModel.self, from: data)
        #expect(stagedModel.hoverLabel == "Second")

        // Superseded passes must not leave bundles or temporary directories behind.
        let entries = try FileManager.default.contentsOfDirectory(
            at: harness.expectedStorageDirectory,
            includingPropertiesForKeys: nil
        )
        let bundles = entries.filter { $0.pathExtension == "app" }
        #expect(bundles.count == 1)
        #expect(!entries.contains { $0.lastPathComponent.hasPrefix(".staging-") })
    }

    @Test @MainActor func testCancelledDragRemovesConsumedBundle() async throws {
        let harness = try AppStateTestHarness()
        defer { harness.tearDown() }

        let appState = harness.appState
        appState.updateCustomStorageURL(harness.root)
        await appState.awaitStagingCompletion()

        guard let consumedURL = appState.consumeStagedBundleForDrag() else {
            Issue.record("Expected a bundle to drag")
            return
        }
        await appState.awaitStagingCompletion()

        appState.handleDragEnded(operation: [])

        #expect(FileManager.default.fileExists(atPath: consumedURL.path) == false)
        #expect(appState.stagedAppURL != nil)
    }

    @Test @MainActor func testSuccessfulDragPreservesConsumedBundle() async throws {
        let harness = try AppStateTestHarness()
        defer { harness.tearDown() }

        let appState = harness.appState
        appState.updateCustomStorageURL(harness.root)
        await appState.awaitStagingCompletion()

        guard let consumedURL = appState.consumeStagedBundleForDrag() else {
            Issue.record("Expected a bundle to drag")
            return
        }
        await appState.awaitStagingCompletion()

        appState.handleDragEnded(operation: .copy)

        // The Dock now owns this bundle, so it must never be deleted.
        #expect(FileManager.default.fileExists(atPath: consumedURL.path))
    }

    @Test @MainActor func testStagingLeavesNoTemporaryDirectories() async throws {
        let harness = try AppStateTestHarness()
        defer { harness.tearDown() }

        let appState = harness.appState
        appState.updateCustomStorageURL(harness.root)
        await appState.awaitStagingCompletion()

        #expect(appState.isStaging == false)
        #expect(appState.stagingError == nil)
        #expect(appState.stagedBundle?.kind == .appBundle)

        let entries = try FileManager.default.contentsOfDirectory(
            at: harness.expectedStorageDirectory,
            includingPropertiesForKeys: nil
        )
        #expect(!entries.contains { $0.lastPathComponent.hasPrefix(".staging-") })
    }

    @Test func testStagingErrorRetryPolicy() {
        #expect(StagingError.cancelled.allowsRetry == false)
        #expect(StagingError.iconRenderFailed.allowsRetry)
        #expect(StagingError.runnerUnavailable.allowsRetry)
        #expect(StagingError.iconRenderFailed.errorDescription?.isEmpty == false)
        #expect(StagingError.iconRenderFailed.recoverySuggestion?.isEmpty == false)

        let wrapped = StagingError.wrapping(StagingError.signingFailed("test"))
        #expect(wrapped == .signingFailed("test"))
    }

    @Test @MainActor func testAppStateCustomStorageDirectoryManagement() async throws {
        let harness = try AppStateTestHarness()
        defer { harness.tearDown() }

        let appState = harness.appState
        appState.updateCustomStorageURL(harness.root)
        await appState.awaitStagingCompletion()

        #expect(appState.customStorageURL?.path == harness.root.path)
        #expect(appState.effectiveStorageDirectory.path == harness.expectedStorageDirectory.path)
        #expect(appState.storageDisplayPath.contains(StorageLayout.folderName))

        // Reset storage directory
        appState.resetStorageDirectory()
        await appState.awaitStagingCompletion()
        #expect(appState.customStorageURL == nil)
        #expect(appState.effectiveStorageDirectory.lastPathComponent == StorageLayout.folderName)
    }

    @Test @MainActor func testCustomStorageNeverDoubleNestsDockDividersFolder() async throws {
        let harness = try AppStateTestHarness()
        defer { harness.tearDown() }

        let appState = harness.appState
        appState.updateCustomStorageURL(harness.root)
        await appState.awaitStagingCompletion()

        #expect(appState.effectiveStorageDirectory.path == harness.expectedStorageDirectory.path)

        // Selecting the DockDividers folder itself is treated as the storage folder.
        appState.updateCustomStorageURL(harness.expectedStorageDirectory)
        await appState.awaitStagingCompletion()
        #expect(appState.effectiveStorageDirectory.path == harness.expectedStorageDirectory.path)
    }

    @Test @MainActor func testStorageCleanupExcludesLiveAndFreshItems() async throws {
        let storageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: storageDir)
        }
        try FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)

        var model = DividerModel()
        model.id = UUID()
        guard let iconData = IconRenderer.renderIconData(for: model) else {
            Issue.record("Failed to generate test icon data")
            return
        }

        let liveURL = try BundleSynthesizer.createDividerApp(
            iconData: iconData,
            config: ActionConfig.none,
            hoverLabel: "LIVE",
            model: model,
            outputDirectory: storageDir,
            registerWithLaunchServices: false
        )
        let unusedURL = try BundleSynthesizer.createDividerApp(
            iconData: iconData,
            config: ActionConfig.none,
            hoverLabel: "UNUSED",
            model: model,
            outputDirectory: storageDir,
            registerWithLaunchServices: false
        )
        let spacerURL = try BundleSynthesizer.createNativeSpacerFile(
            size: .regular,
            outputDirectory: storageDir
        )

        StorageMaintenance.ensureReadme(in: storageDir)
        #expect(FileManager.default.fileExists(atPath: storageDir.appendingPathComponent("README.txt").path))

        let livePaths: Set<String> = [StoragePath.canonical(liveURL)]

        // Everything is fresh, so the grace period protects all items.
        let freshCensus = await StorageMaintenance.buildCensus(
            for: storageDir,
            liveSet: .known(livePaths),
            orphanGracePeriod: 60
        )
        #expect(freshCensus.items.count == 3)
        #expect(freshCensus.unusedItems.isEmpty)

        // With no grace period, only the live bundle is protected.
        let census = await StorageMaintenance.buildCensus(
            for: storageDir,
            liveSet: .known(livePaths),
            orphanGracePeriod: 0
        )
        #expect(census.items.count == 3)
        #expect(census.unusedItems.count == 2)
        #expect(census.unusedItems.contains { StoragePath.canonical($0.url) == StoragePath.canonical(unusedURL) })
        #expect(census.unusedItems.contains { StoragePath.canonical($0.url) == StoragePath.canonical(spacerURL) })
        #expect(!census.unusedItems.contains { StoragePath.canonical($0.url) == StoragePath.canonical(liveURL) })

        // If the Dock configuration cannot be read, cleanup must be disabled.
        let unavailableCensus = await StorageMaintenance.buildCensus(
            for: storageDir,
            liveSet: .unavailable,
            orphanGracePeriod: 0
        )
        #expect(unavailableCensus.liveSetAvailable == false)
        #expect(unavailableCensus.unusedItems.isEmpty)

        let removed = try StorageMaintenance.cleanUp(census.unusedItems, useTrash: false)
        #expect(removed == 2)
        #expect(FileManager.default.fileExists(atPath: liveURL.path))
        #expect(FileManager.default.fileExists(atPath: unusedURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: spacerURL.path) == false)
    }

    @Test func testUnrelatedAppIsNotManagedByDockDivider() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let unrelatedAppURL = tempDir.appendingPathComponent("Unrelated.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: unrelatedAppURL.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )

        #expect(BundleMarker.isDockDividerBundle(at: unrelatedAppURL) == false)
    }

    // MARK: - Onboarding & Presets

    @Test @MainActor func testOnboardingShowsOnlyUntilCompleted() throws {
        let harness = try AppStateTestHarness(showsOnboarding: true)
        defer { harness.tearDown() }

        #expect(harness.appState.isOnboardingPresented)

        harness.appState.completeOnboarding()
        #expect(harness.appState.isOnboardingPresented == false)
        #expect(harness.defaults.bool(forKey: AppState.onboardingDefaultsKey))

        let reloaded = harness.makeAppState(showsOnboarding: true)
        #expect(reloaded.isOnboardingPresented == false)
    }

    @Test @MainActor func testOnboardingStaysHiddenWhenDisabled() throws {
        let harness = try AppStateTestHarness(showsOnboarding: false)
        defer { harness.tearDown() }

        #expect(harness.appState.isOnboardingPresented == false)
    }

    // MARK: - UI & Integration Wiring

    @Test @MainActor func testChangingStorageWarnsWhenOldFolderStillBacksDockItems() async throws {
        var alerts: [(directory: URL, count: Int)] = []
        let harness = try AppStateTestHarness(storageMoveAlert: { directory, count in
            alerts.append((directory, count))
        })
        defer { harness.tearDown() }

        let oldDirectory = harness.appState.effectiveStorageDirectory
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        let spacerURL = try BundleSynthesizer.createNativeSpacerFile(
            size: .regular,
            outputDirectory: oldDirectory
        )

        let appState = harness.makeAppState(
            liveSet: .known([StoragePath.canonical(spacerURL)]),
            storageMoveAlert: { directory, count in
                alerts.append((directory, count))
            }
        )

        appState.updateCustomStorageURL(harness.root)
        await appState.awaitStagingCompletion()

        #expect(alerts.count == 1)
        #expect(alerts.first?.directory.standardizedFileURL == oldDirectory.standardizedFileURL)
        #expect(alerts.first?.count == 1)
    }

    @Test @MainActor func testChangingStorageStaysQuietWhenOldFolderHasNoLiveItems() async throws {
        var alertCount = 0
        let harness = try AppStateTestHarness(storageMoveAlert: { _, _ in
            alertCount += 1
        })
        defer { harness.tearDown() }

        let oldDirectory = harness.appState.effectiveStorageDirectory
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        _ = try BundleSynthesizer.createNativeSpacerFile(
            size: .regular,
            outputDirectory: oldDirectory
        )

        let appState = harness.makeAppState(
            liveSet: .known([]),
            storageMoveAlert: { _, _ in
                alertCount += 1
            }
        )

        appState.updateCustomStorageURL(harness.root)
        await appState.awaitStagingCompletion()

        #expect(alertCount == 0)
    }

    @Test @MainActor func testKeyboardRevealFallbackUsesStagedBundle() async throws {
        var revealed: [URL] = []
        let harness = try AppStateTestHarness(revealInFinder: { urls in
            revealed = urls
        })
        defer { harness.tearDown() }

        let appState = harness.appState
        appState.stageImmediately()
        await appState.awaitStagingCompletion()

        guard let stagedURL = appState.stagedAppURL else {
            Issue.record("Expected a staged bundle")
            return
        }

        // Exercise the accessibility fallback without hosting a SwiftUI window:
        // the drag source's press action must reveal the prepared bundle.
        let dragSource = DragSourceNSView()
        dragSource.onAccessibilityPress = {
            appState.revealStagedBundleInFinder()
        }

        #expect(dragSource.accessibilityPerformPress())
        #expect(revealed.map(StoragePath.canonical) == [StoragePath.canonical(stagedURL)])
    }

    // MARK: - UI & Control Tests

    @Test @MainActor func testDeferredBindingsApplyOnNextRunLoopTurn() async throws {
        var style = DividerStyle.line
        let binding = Binding(
            get: { style },
            set: { style = $0 }
        )
        let deferred = binding.deferred()

        // Deferred setters are used by the segmented pickers so their AppKit
        // actions never mutate SwiftUI state during a view update.
        deferred.wrappedValue = .dashed
        deferred.wrappedValue = .dot
        #expect(style == .line)

        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(style == .dot)
    }
}

// MARK: - Pixel Test Helpers

private struct OpaquePixelBounds {
    let minX: Int
    let maxX: Int
    let minY: Int
    let maxY: Int
}

private func opaquePixelBounds(of image: CGImage, alphaThreshold: UInt8 = 16) -> OpaquePixelBounds? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let didDraw = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
        guard let context = CGContext(
            data: rawBuffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard didDraw else { return nil }

    var minX = width
    var maxX = -1
    var minY = height
    var maxY = -1

    for y in 0..<height {
        for x in 0..<width {
            let alpha = pixels[(y * width + x) * 4 + 3]
            guard alpha > alphaThreshold else { continue }
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }

    guard maxX >= minX, maxY >= minY else { return nil }
    return OpaquePixelBounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
}

private func makeTestPNGData(
    width: Int,
    height: Int,
    color: NSColor = .systemBlue
) -> Data? {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }
    representation.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = context
    color.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    return representation.representation(using: .png, properties: [:])
}

// MARK: - Runner Test Helpers

private struct RunnerTestProcessResult {
    let status: Int32
    let output: String
}

private struct RunnerTestBundle {
    let root: URL
    let executableURL: URL
}

private func makeRunnerTestBundle(
    runnerURL: URL,
    config: ActionConfig
) throws -> RunnerTestBundle {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("DockDividerRunner-\(UUID().uuidString)", isDirectory: true)
    let appURL = root.appendingPathComponent("Runner.app", isDirectory: true)
    let macosURL = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
    let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)

    try FileManager.default.createDirectory(at: macosURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

    let executableURL = macosURL.appendingPathComponent("divider_runner")
    try FileManager.default.copyItem(at: runnerURL, to: executableURL)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executableURL.path
    )

    let configData = try JSONEncoder().encode(config)
    try configData.write(
        to: resourcesURL.appendingPathComponent("ActionConfig.json"),
        options: .atomic
    )

    return RunnerTestBundle(root: root, executableURL: executableURL)
}

private func runTestProcess(
    _ executableURL: URL,
    arguments: [String],
    timeout: TimeInterval = 5
) throws -> RunnerTestProcessResult {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe

    try process.run()

    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.01)
    }

    if process.isRunning {
        process.terminate()
        process.waitUntilExit()
        return RunnerTestProcessResult(status: -1, output: "Timed out after \(timeout)s")
    }

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return RunnerTestProcessResult(
        status: process.terminationStatus,
        output: String(data: outputData, encoding: .utf8) ?? ""
    )
}

/// Creates an `AppState` whose storage and defaults are fully isolated from the
/// developer's real ~/Library state.
@MainActor
private struct AppStateTestHarness {
    let root: URL
    let suiteName: String
    let defaults: UserDefaults
    let appState: AppState

    init(
        showsOnboarding: Bool = false,
        liveSet: StorageLiveSet = .unavailable,
        revealInFinder: (@MainActor ([URL]) -> Void)? = nil,
        storageMoveAlert: (@MainActor (URL, Int) -> Void)? = nil
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockDividerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let suiteName = "DockDividerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        self.root = root
        self.suiteName = suiteName
        self.defaults = defaults
        self.appState = Self.makeAppState(
            root: root,
            defaults: defaults,
            liveSet: liveSet,
            showsOnboarding: showsOnboarding,
            revealInFinder: revealInFinder,
            storageMoveAlert: storageMoveAlert
        )
    }

    func makeAppState(
        liveSet: StorageLiveSet = .unavailable,
        showsOnboarding: Bool = false,
        revealInFinder: (@MainActor ([URL]) -> Void)? = nil,
        storageMoveAlert: (@MainActor (URL, Int) -> Void)? = nil
    ) -> AppState {
        Self.makeAppState(
            root: root,
            defaults: defaults,
            liveSet: liveSet,
            showsOnboarding: showsOnboarding,
            revealInFinder: revealInFinder,
            storageMoveAlert: storageMoveAlert
        )
    }

    private static func makeAppState(
        root: URL,
        defaults: UserDefaults,
        liveSet: StorageLiveSet,
        showsOnboarding: Bool,
        revealInFinder: (@MainActor ([URL]) -> Void)?,
        storageMoveAlert: (@MainActor (URL, Int) -> Void)?
    ) -> AppState {
        var environment = AppEnvironment(
            userDefaults: defaults,
            applicationSupportDirectory: root.appendingPathComponent("ApplicationSupport", isDirectory: true),
            repairOnLaunch: false,
            stagesOnLaunch: false,
            stagesOnDraftChanges: false,
            registerWithLaunchServices: false,
            stagingDebounce: 0,
            liveSet: liveSet,
            showsOnboarding: showsOnboarding,
            appliesFinderIcons: false
        )
        if let revealInFinder {
            environment.revealInFinder = revealInFinder
        }
        if let storageMoveAlert {
            environment.presentStorageMoveAlert = storageMoveAlert
        }
        return AppState(environment: environment)
    }

    var expectedStorageDirectory: URL {
        root.appendingPathComponent(StorageLayout.folderName, isDirectory: true)
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}
