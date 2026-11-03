//
//  AppState.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import Foundation
import Combine
import AppKit

/// Injectable dependencies for `AppState`.
///
/// Production uses `.live`. Unit tests inject a temporary application-support
/// folder and a dedicated `UserDefaults` suite so they never read or mutate the
/// developer's real divider storage, bookmark, or Dock configuration.
struct AppEnvironment {
    var userDefaults: UserDefaults
    var applicationSupportDirectory: URL
    var repairOnLaunch: Bool
    var stagesOnLaunch: Bool
    var stagesOnDraftChanges: Bool
    var registerWithLaunchServices: Bool
    var stagingDebounce: TimeInterval
    var persistsDraft: Bool = true
    /// Source of "what is currently in the Dock". Tests inject a known or
    /// unavailable set so they never read the developer's real Dock.
    var liveSet: StorageLiveSet = .currentDock
    /// Whether a fresh install may show the welcome sheet. Tests disable it so
    /// a sheet never interferes with window-level assertions.
    var showsOnboarding: Bool = true
    /// Presents the storage-move warning. Tests inject a recorder instead of
    /// putting a modal NSAlert on screen.
    var presentStorageMoveAlert: @MainActor (_ oldDirectory: URL, _ itemCount: Int) -> Void = { oldDirectory, itemCount in
        AppEnvironment.defaultStorageMoveAlert(oldDirectory, itemCount)
    }
    /// Reveals files in Finder. Tests inject a recorder so they never open
    /// Finder windows.
    var revealInFinder: @MainActor (_ urls: [URL]) -> Void = { urls in
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
    /// Whether a staged app bundle should receive a Finder custom icon.
    /// Tests disable this so IconServices never runs inside the test host.
    var appliesFinderIcons: Bool = true

    @MainActor
    static func defaultStorageMoveAlert(_ oldDirectory: URL, _ itemCount: Int) {
        let alert = NSAlert()
        alert.messageText = "Your existing Dock icons stay in the old folder"
        alert.informativeText = """
        \(itemCount) divider\(itemCount == 1 ? "" : "s") currently in your Dock still \
        point\(itemCount == 1 ? "s" : "") to:
        \(oldDirectory.path)

        They keep working. Clean Up only reviews the new folder, so remove those \
        icons from the Dock before deleting the old folder.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static var live: AppEnvironment {
        // The unit-test host must not stage into the real storage folder or
        // drive IconServices; its tests use an isolated AppEnvironment.
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        return AppEnvironment(
            userDefaults: .standard,
            applicationSupportDirectory: FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!,
            repairOnLaunch: !isRunningTests,
            stagesOnLaunch: !isRunningTests,
            stagesOnDraftChanges: !isRunningTests,
            registerWithLaunchServices: !isRunningTests,
            stagingDebounce: 0.25,
            persistsDraft: !isRunningTests,
            showsOnboarding: !isRunningTests,
            appliesFinderIcons: !isRunningTests
        )
    }
}

@MainActor
final class AppState: ObservableObject {

    static let onboardingDefaultsKey = "DockDivider.hasSeenWelcome"

    // MARK: - Published State

    @Published var draft: DividerModel = DividerModel()
    @Published private(set) var storageSummary: StorageSummary? = nil

    /// True until the welcome sheet has been shown once on a fresh install.
    @Published var isOnboardingPresented: Bool

    // MARK: - Collaborators

    private let environment: AppEnvironment
    private let storageLocation: StorageLocationStore
    private let staging: StagingController
    private let repairer: BundleRepairer
    private var cancellables = Set<AnyCancellable>()
    private var summaryRefreshTask: Task<Void, Never>?

    // MARK: - Forwarded State

    /// The artifact that can currently be dragged, if any.
    var stagedBundle: StagedBundle? {
        staging.stagedBundle
    }

    var stagedAppURL: URL? {
        staging.stagedAppURL
    }

    var stagingState: StagingState {
        staging.stagingState
    }

    var isStaging: Bool {
        staging.isStaging
    }

    var stagingError: StagingError? {
        staging.stagingError
    }

    var isReadyForDrag: Bool {
        staging.isReadyForDrag && validationWarning == nil
    }

    /// Explains why the current design cannot be dragged yet.
    var validationWarning: String? {
        draft.validationWarning
    }

    var customStorageURL: URL? {
        storageLocation.customStorageURL
    }

    /// Folder that actually contains generated bundles. A custom selection is
    /// treated as a root, and generated content is placed in a `DockDividers`
    /// subfolder so `~/Applications` never fills with invisible app bundles.
    var effectiveStorageDirectory: URL {
        storageLocation.effectiveStorageDirectory
    }

    var storageDisplayPath: String {
        storageLocation.storageDisplayPath
    }

    var isUsingDefaultStorageLocation: Bool {
        storageLocation.isUsingDefaultStorageLocation
    }

    var storageLocationWarning: String? {
        storageLocation.storageLocationWarning
    }

    // MARK: - Initialization & Lifecycle

    init(environment: AppEnvironment = .live) {
        self.environment = environment
        self.isOnboardingPresented = environment.showsOnboarding
            && !environment.userDefaults.bool(forKey: Self.onboardingDefaultsKey)
        self.storageLocation = StorageLocationStore(
            userDefaults: environment.userDefaults,
            applicationSupportDirectory: environment.applicationSupportDirectory
        )
        self.staging = StagingController(
            registerWithLaunchServices: environment.registerWithLaunchServices,
            appliesFinderIcons: environment.appliesFinderIcons
        )
        self.repairer = BundleRepairer(isEnabled: environment.repairOnLaunch)

        if environment.persistsDraft,
           let savedDraft = DraftPersistence.load(from: environment.applicationSupportDirectory) {
            draft = savedDraft
        } else {
            draft.orientation = DividerOrientation.currentSystemDockOrientation
        }

        setUpObservations()

        repairExistingDividerBundles()

        if environment.stagesOnLaunch {
            DispatchQueue.main.async { [weak self] in
                self?.stageImmediately()
            }
        }

        refreshStorageSummary()
    }

    private func setUpObservations() {
        // Forward collaborator changes so views observing `AppState` re-render
        // when staging or storage selection changes.
        storageLocation.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        staging.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        staging.onStorageChanged = { [weak self] in
            self?.refreshStorageSummary()
        }

        if environment.stagesOnDraftChanges {
            $draft
                .dropFirst()
                .debounce(
                    for: .milliseconds(max(0, Int(environment.stagingDebounce * 1000))),
                    scheduler: DispatchQueue.main
                )
                .sink { [weak self] _ in
                    self?.stageImmediately()
                }
                .store(in: &cancellables)
        }

        if environment.persistsDraft {
            $draft
                .dropFirst()
                .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
                .sink { [weak self] draft in
                    guard let self else { return }
                    // Saving on the main actor keeps writes ordered: a newer
                    // draft can never be overwritten by a slower, older save.
                    DraftPersistence.save(
                        draft,
                        to: self.environment.applicationSupportDirectory
                    )
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
                .sink { [weak self] _ in
                    guard let self else { return }
                    DraftPersistence.save(self.draft, to: self.environment.applicationSupportDirectory)
                }
                .store(in: &cancellables)
        }

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.repairExistingDividerBundles()
                self.refreshStorageSummary()
            }
            .store(in: &cancellables)
    }

    // MARK: - Onboarding

    /// Marks the welcome sheet as seen so it never returns.
    func completeOnboarding() {
        isOnboardingPresented = false
        environment.userDefaults.set(true, forKey: Self.onboardingDefaultsKey)
    }

    // MARK: - Storage Directory Management

    func selectStorageDirectory() {
        let previous = effectiveStorageDirectory
        guard storageLocation.selectStorageDirectory() else { return }
        handleStorageLocationChanged(from: previous)
    }

    func resetStorageDirectory() {
        let previous = effectiveStorageDirectory
        storageLocation.resetStorageDirectory()
        handleStorageLocationChanged(from: previous)
    }

    func updateCustomStorageURL(_ url: URL?) {
        let previous = effectiveStorageDirectory
        storageLocation.updateCustomStorageURL(url)
        handleStorageLocationChanged(from: previous)
    }

    func revealStorageDirectoryInFinder() {
        storageLocation.revealInFinder()
    }

    private func handleStorageLocationChanged(from previous: URL) {
        let newDirectory = effectiveStorageDirectory
        StorageMaintenance.ensureReadme(in: newDirectory)

        // Cleanup only ever looks at the current folder. Dock icons placed
        // before the switch keep pointing at the old one, so say so instead of
        // letting those bundles look like they vanished. Ask before staging so
        // the modal alert cannot delay the first artifact in the new folder.
        if StoragePath.canonical(previous) != StoragePath.canonical(newDirectory),
           let livePaths = environment.liveSet.resolvedPaths() {
            let liveCount = StorageMaintenance.liveManagedItemCount(
                in: previous,
                livePaths: livePaths
            )
            if liveCount > 0 {
                environment.presentStorageMoveAlert(previous, liveCount)
            }
        }

        stageImmediately()
        refreshStorageSummary()
    }

    // MARK: - Storage Census & Cleanup

    /// Recomputes the small summary shown in the footer. The full item list is
    /// loaded on demand by the cleanup sheet.
    ///
    /// Staging publishes a new artifact on every debounced edit, so this is
    /// coalesced: a burst of staging changes produces one census pass instead
    /// of walking every bundle directory dozens of times.
    func refreshStorageSummary() {
        summaryRefreshTask?.cancel()
        summaryRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }

            let directory = self.effectiveStorageDirectory
            let excludedPaths = self.staging.storageExclusions
            let census = await StorageMaintenance.buildCensus(
                for: directory,
                excluding: excludedPaths,
                liveSet: self.environment.liveSet
            )

            guard !Task.isCancelled,
                  StoragePath.canonical(self.effectiveStorageDirectory) == StoragePath.canonical(directory) else {
                return
            }
            self.storageSummary = census.summary
        }
    }

    func loadStorageCensus() async -> StorageCensus {
        let directory = effectiveStorageDirectory
        let excludedPaths = staging.storageExclusions
        return await StorageMaintenance.buildCensus(
            for: directory,
            excluding: excludedPaths,
            liveSet: environment.liveSet
        )
    }

    @discardableResult
    func cleanUpStorage(_ items: [StorageItem]) async throws -> Int {
        let removed = try await Task.detached(priority: .userInitiated) {
            try StorageMaintenance.cleanUp(items)
        }.value
        refreshStorageSummary()
        return removed
    }

    // MARK: - Bundle Staging

    /// Starts a staging pass for the current draft.
    func stageImmediately() {
        staging.stage(draft: draft, directory: effectiveStorageDirectory)
    }

    /// Returns the current staged file and immediately begins preparing the
    /// replacement. Returns `nil` while staging so the drag source cannot hand
    /// an outdated artifact to the Dock.
    func consumeStagedBundleForDrag() -> URL? {
        staging.consumeStagedBundleForDrag(
            draft: draft,
            directory: effectiveStorageDirectory
        )
    }

    /// Called by the drag source when a session ends.
    func handleDragEnded(operation: NSDragOperation) {
        staging.handleDragEnded(operation: operation)
    }

    /// Keyboard-accessible fallback for users who cannot drag. Reveals the
    /// prepared bundle so it can be dragged from Finder.
    func revealStagedBundleInFinder() {
        guard let url = stagedAppURL else { return }
        environment.revealInFinder([url])
    }

    func retryStaging() {
        staging.retryStaging(draft: draft, directory: effectiveStorageDirectory)
    }

    func dismissStagingError() {
        staging.dismissStagingError()
    }

    /// Test/support hook that waits until every staging pass (including
    /// superseded passes that are cleaning up) has finished.
    func awaitStagingCompletion(timeout: TimeInterval = 15) async {
        await staging.awaitStagingCompletion(timeout: timeout)
    }

    // MARK: - Bundle Maintenance & Repair

    private func repairExistingDividerBundles() {
        let directory = effectiveStorageDirectory
        let exclusion = staging.storageExclusionURL

        // The scan and signing can take a while in a large folder; keep launch
        // and activation responsive by running the pass as a task.
        Task { [weak self] in
            await self?.repairer.repairExistingBundles(
                in: directory,
                excluding: exclusion
            )
        }
    }
}
