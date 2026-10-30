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
nonisolated struct AppEnvironment {
    var userDefaults: UserDefaults
    var applicationSupportDirectory: URL
    var repairOnLaunch: Bool
    var stagesOnLaunch: Bool
    var stagesOnDraftChanges: Bool
    var registerWithLaunchServices: Bool
    var stagingDebounce: TimeInterval
    var persistsDraft: Bool = true

    static var live: AppEnvironment {
        AppEnvironment(
            userDefaults: .standard,
            applicationSupportDirectory: FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!,
            repairOnLaunch: true,
            stagesOnLaunch: true,
            stagesOnDraftChanges: true,
            registerWithLaunchServices: true,
            stagingDebounce: 0.25
        )
    }
}

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published State

    @Published var draft: DividerModel = DividerModel()
    @Published private(set) var storageSummary: StorageSummary? = nil

    // MARK: - Collaborators

    private let environment: AppEnvironment
    private let storageLocation: StorageLocationStore
    private let staging: StagingController
    private let repairer: BundleRepairer
    private var cancellables = Set<AnyCancellable>()

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
        self.storageLocation = StorageLocationStore(
            userDefaults: environment.userDefaults,
            applicationSupportDirectory: environment.applicationSupportDirectory
        )
        self.staging = StagingController(
            registerWithLaunchServices: environment.registerWithLaunchServices
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
                    let directory = self.environment.applicationSupportDirectory
                    Task.detached(priority: .utility) {
                        DraftPersistence.save(draft, to: directory)
                    }
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

    // MARK: - Storage Directory Management

    func selectStorageDirectory() {
        guard storageLocation.selectStorageDirectory() else { return }
        handleStorageLocationChanged()
    }

    func resetStorageDirectory() {
        storageLocation.resetStorageDirectory()
        handleStorageLocationChanged()
    }

    func updateCustomStorageURL(_ url: URL?) {
        storageLocation.updateCustomStorageURL(url)
        handleStorageLocationChanged()
    }

    func revealStorageDirectoryInFinder() {
        storageLocation.revealInFinder()
    }

    private func handleStorageLocationChanged() {
        StorageMaintenance.ensureReadme(in: effectiveStorageDirectory)
        stageImmediately()
        refreshStorageSummary()
    }

    // MARK: - Storage Census & Cleanup

    /// Recomputes the small summary shown in the footer. The full item list is
    /// loaded on demand by the cleanup sheet.
    func refreshStorageSummary() {
        let directory = effectiveStorageDirectory
        let excludedPaths = staging.storageExclusions

        Task { [weak self] in
            let census = await StorageMaintenance.buildCensus(
                for: directory,
                excluding: excludedPaths
            )
            guard let self else { return }
            guard StoragePath.canonical(self.effectiveStorageDirectory) == StoragePath.canonical(directory) else {
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
            excluding: excludedPaths
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
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
        repairer.repairExistingBundles(
            in: effectiveStorageDirectory,
            excluding: staging.storageExclusionURL
        )
    }
}
