//
//  DockDividerUITests.swift
//  DockDividerUITests
//

import XCTest

final class DockDividerUITests: XCTestCase {

    private var app: XCUIApplication!
    private var suiteName = ""
    private var storageDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false

        suiteName = "me.bogle.DockDivider.UITests.\(UUID().uuidString)"
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockDividerUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil

        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: storageDirectory)
    }

    // MARK: - Launch Helpers

    /// Launches the app in the isolated UI-test configuration.
    ///
    /// Storage, preferences, onboarding state, and launch side effects are
    /// redirected by `AppEnvironment.uiTest`, so these tests never read or
    /// mutate the developer's real Dock, bookmarks, or divider bundles.
    @discardableResult
    private func launchApp(showsOnboarding: Bool = false) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchEnvironment["DOCKDIVIDER_UI_TEST"] = "1"
        application.launchEnvironment["DOCKDIVIDER_UI_TEST_STORAGE"] = storageDirectory.path
        application.launchEnvironment["DOCKDIVIDER_UI_TEST_DEFAULTS_SUITE"] = suiteName
        if showsOnboarding {
            application.launchEnvironment["DOCKDIVIDER_UI_TEST_SHOW_ONBOARDING"] = "1"
        }
        application.launch()
        app = application
        return application
    }

    private func selectStyle(_ style: String, in app: XCUIApplication) {
        let group = app.radioGroups["style-picker"]
        XCTAssertTrue(
            group.waitForExistence(timeout: 5),
            "Could not find the style picker"
        )

        let option = group.radioButtons[style]
        XCTAssertTrue(
            option.waitForExistence(timeout: 2),
            "Could not find the \(style) style control"
        )
        option.click()
    }

    private func waitForDisappearance(
        of element: XCUIElement,
        timeout: TimeInterval = 5
    ) {
        XCTAssertTrue(
            element.waitForNonExistence(timeout: timeout),
            "\(element) was still visible after \(timeout) seconds"
        )
    }

    // MARK: - Tests

    @MainActor
    func testMainWindowShowsEditorPreviewAndDragWell() {
        let app = launchApp()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Click Behavior (Optional)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Drag Me to Dock"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.radioGroups["style-picker"].exists)
        XCTAssertTrue(app.buttons["dragWell"].exists)
        XCTAssertTrue(app.links["storage-cleanup-button"].exists)
    }

    @MainActor
    func testImageStyleShowsValidationWarningUntilItHasAnImage() {
        let app = launchApp()
        XCTAssertTrue(app.radioGroups["style-picker"].waitForExistence(timeout: 10))

        selectStyle("Image", in: app)

        let warning = app.staticTexts["validation-warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        let warningText = (warning.value as? String) ?? warning.label
        XCTAssertTrue(warningText.contains("Choose an image"))

        selectStyle("Line", in: app)
        waitForDisappearance(of: warning)
    }

    @MainActor
    func testOnboardingAppearsOnceAndStaysDismissedAfterRelaunch() {
        let app = launchApp(showsOnboarding: true)
        let welcome = app.staticTexts["Welcome to DockDivider"]

        XCTAssertTrue(welcome.waitForExistence(timeout: 10))

        let getStarted = app.buttons["onboarding-get-started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        getStarted.click()

        waitForDisappearance(of: welcome)
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))

        app.terminate()

        let relaunched = launchApp(showsOnboarding: true)
        XCTAssertTrue(relaunched.staticTexts["Appearance"].waitForExistence(timeout: 10))
        XCTAssertFalse(
            relaunched.staticTexts["Welcome to DockDivider"].waitForExistence(timeout: 2),
            "The welcome sheet should not return after it has been dismissed once"
        )
    }

    @MainActor
    func testStorageCleanupSheetOpensAndCloses() {
        let app = launchApp()

        let cleanupButton = app.links["storage-cleanup-button"]
        XCTAssertTrue(cleanupButton.waitForExistence(timeout: 10))
        cleanupButton.click()

        let title = app.staticTexts["Storage Cleanup"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))

        let closeButton = app.buttons["storage-cleanup-close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.click()

        waitForDisappearance(of: title)
    }
}
