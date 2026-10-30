//
//  StagingController.swift
//  DockDivider
//

import Foundation
import AppKit
import Combine

/// Owns the divider staging state machine.
///
/// Responsibilities:
/// - revisioned staging passes and cancellation of superseded passes
/// - the currently draggable artifact and drag ownership
/// - cleanup of replaced or cancelled bundles
/// - preview icon hand-off to `BundleSynthesizer`
///
/// `AppState` supplies the current draft and storage directory; views keep
/// observing `AppState`, which forwards this controller's published state.
@MainActor
final class StagingController: ObservableObject {

    // MARK: - Published State

    @Published private(set) var stagingState: StagingState = .idle

    /// Called after staging or cleanup changes the contents of the storage
    /// folder, so the owner can refresh its storage summary.
    var onStorageChanged: (@MainActor () -> Void)?

    // MARK: - Private State

    private let registerWithLaunchServices: Bool

    /// Last successfully published artifact. Kept separately from
    /// `stagingState` so a newer staging pass can still clean up the bundle it
    /// is replacing while the UI shows `Preparing…`.
    private var lastReadyBundle: StagedBundle?

    /// True after a bundle has been handed to a drag session and before the
    /// next staged replacement is published.
    private var isStagedBundleConsumed = false

    /// URL currently owned by an in-flight drag. Used to defer cleanup until the
    /// drag reports whether the Dock accepted it.
    private var activeDragURL: URL?

    private var stagingRevision: UInt64 = 0
    private var stagingTask: Task<Void, Never>?
    private var activeStagingTaskCount = 0
    private var pendingPreviewImages: [UInt64: NSImage] = [:]

    // MARK: - Init

    init(registerWithLaunchServices: Bool) {
        self.registerWithLaunchServices = registerWithLaunchServices
    }

    // MARK: - Derived State

    var stagedBundle: StagedBundle? {
        stagingState.bundle
    }

    var stagedAppURL: URL? {
        stagedBundle?.url
    }

    var isStaging: Bool {
        stagingState.isPreparing
    }

    var stagingError: StagingError? {
        stagingState.error
    }

    var isReadyForDrag: Bool {
        stagedBundle != nil
    }

    /// Bundle that repair must not touch because it is staged or owned by an
    /// in-flight drag.
    var storageExclusionURL: URL? {
        activeDragURL ?? lastReadyBundle?.url
    }

    /// Paths that must never be offered by storage cleanup: the last published
    /// bundle (which may still be referenced by the Dock) and any bundle owned
    /// by an in-flight drag.
    var storageExclusions: Set<String> {
        var paths = Set<String>()
        if let lastReadyBundle {
            paths.insert(StoragePath.canonical(lastReadyBundle.url))
        }
        if let activeDragURL {
            paths.insert(StoragePath.canonical(activeDragURL))
        }
        return paths
    }

    // MARK: - Staging

    /// Starts a staging pass for `draft`.
    ///
    /// Each pass gets a monotonically increasing revision. Results from older
    /// passes are discarded and deleted, so rapid edits can never publish a
    /// stale bundle or leave an orphan behind.
    func stage(draft: DividerModel, directory: URL) {
        let snapshot = draft
        let previous = isStagedBundleConsumed ? nil : lastReadyBundle

        stagingRevision &+= 1
        let revision = stagingRevision
        stagingTask?.cancel()
        stagingTask = nil

        stagingState = .preparing(revision: revision)
        StorageMaintenance.ensureReadme(in: directory)

        // When in Blank Spacer mode with no click action and no custom hover tooltip,
        // use native .dockspace / .docksmallspace / .dockflexspace trigger files so
        // Dock.app creates a true DOCKSpacerTile (zero tooltip bubble and zero clickability).
        let isPassiveNativeSpacer = (snapshot.style == .spacer)
            && (snapshot.actionConfig.actionType == .none)
            && snapshot.hoverLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if isPassiveNativeSpacer {
            launchStaging(
                revision: revision,
                previous: previous,
                kind: .nativeSpacer
            ) {
                try BundleStagingService.createNativeSpacer(
                    size: snapshot.spacerSize,
                    outputDirectory: directory
                )
            }
            return
        }

        guard let iconData = IconRenderer.renderIconData(for: snapshot) else {
            failStaging(revision: revision, previous: previous, error: .iconRenderFailed)
            return
        }

        // Use 256x256 pt (@2x = 512x512 px) for NSWorkspace.shared.setIcon so IconServices
        // never attempts to encode an invalid 1024x1024 @1x (2048px) slot.
        pendingPreviewImages[revision] = IconRenderer.renderNSImage(
            for: snapshot,
            size: CGSize(width: 256, height: 256)
        )

        launchStaging(
            revision: revision,
            previous: previous,
            kind: .appBundle
        ) {
            try BundleStagingService.createDividerApp(
                iconData: iconData,
                config: snapshot.actionConfig,
                hoverLabel: snapshot.hoverLabel,
                model: snapshot,
                outputDirectory: directory
            )
        }
    }

    /// Returns the current staged file and immediately begins preparing the
    /// replacement. Returns `nil` while staging so the drag source cannot hand
    /// an outdated artifact to the Dock.
    func consumeStagedBundleForDrag(draft: DividerModel, directory: URL) -> URL? {
        guard let bundle = stagedBundle, !isStagedBundleConsumed else {
            return nil
        }

        guard FileManager.default.fileExists(atPath: bundle.url.path) else {
            lastReadyBundle = nil
            stagingState = .failed(.stagedFileMissing)
            stage(draft: draft, directory: directory)
            return nil
        }

        isStagedBundleConsumed = true
        activeDragURL = bundle.url
        stagingState = .idle
        stage(draft: draft, directory: directory)
        onStorageChanged?()
        return bundle.url
    }

    /// Called by the drag source when a session ends.
    ///
    /// An empty operation means the drag was cancelled or rejected before the
    /// Dock took ownership, so the consumed bundle is removed. A successful
    /// drop preserves it because the Dock now references it.
    func handleDragEnded(operation: NSDragOperation) {
        guard let draggedURL = activeDragURL else { return }
        activeDragURL = nil

        if operation.isEmpty {
            try? FileManager.default.removeItem(at: draggedURL)
            if lastReadyBundle?.url.standardizedFileURL == draggedURL.standardizedFileURL {
                lastReadyBundle = nil
            }
        }

        onStorageChanged?()
    }

    func retryStaging(draft: DividerModel, directory: URL) {
        stage(draft: draft, directory: directory)
    }

    func dismissStagingError() {
        guard case .failed = stagingState else { return }
        stagingState = .idle
    }

    /// Test/support hook that waits until every staging pass (including
    /// superseded passes that are cleaning up) has finished.
    func awaitStagingCompletion(timeout: TimeInterval = 15) async {
        let deadline = Date().addingTimeInterval(timeout)
        while activeStagingTaskCount > 0 || isStaging {
            if Date() >= deadline {
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: - Staging Internals

    private func launchStaging(
        revision: UInt64,
        previous: StagedBundle?,
        kind: StagedBundle.Kind,
        work: @escaping @Sendable () throws -> URL
    ) {
        activeStagingTaskCount += 1
        stagingTask = Task { [weak self] in
            let result: Result<URL, StagingError>
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try work()
                }.value
                result = .success(url)
            } catch {
                result = .failure(StagingError.wrapping(error))
            }

            guard let self else {
                if case .success(let url) = result {
                    try? FileManager.default.removeItem(at: url)
                }
                return
            }

            defer { self.activeStagingTaskCount -= 1 }
            self.finishStaging(
                revision: revision,
                previous: previous,
                kind: kind,
                result: result
            )
        }
    }

    private func finishStaging(
        revision: UInt64,
        previous: StagedBundle?,
        kind: StagedBundle.Kind,
        result: Result<URL, StagingError>
    ) {
        // A newer staging pass owns the UI and cleanup now.
        guard stagingRevision == revision else {
            pendingPreviewImages.removeValue(forKey: revision)
            if case .success(let url) = result {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }

        switch result {
        case .success(let url):
            let bundle = StagedBundle(url: url, kind: kind, revision: revision)
            lastReadyBundle = bundle
            isStagedBundleConsumed = false
            stagingState = .ready(bundle)

            if let previous,
               previous.url.standardizedFileURL != url.standardizedFileURL {
                try? FileManager.default.removeItem(at: previous.url)
            }

            if kind == .appBundle, let previewImage = pendingPreviewImages.removeValue(forKey: revision) {
                BundleSynthesizer.applyCustomIconAndNotify(previewImage, at: url)
            } else {
                BundleSynthesizer.notifyFileSystemChanged(at: url)
            }

            if kind == .appBundle, registerWithLaunchServices {
                Task.detached(priority: .utility) {
                    BundleStagingService.registerWithLaunchServices(at: url)
                }
            }

            onStorageChanged?()

        case .failure(let error):
            pendingPreviewImages.removeValue(forKey: revision)
            guard error != .cancelled else { return }
            failStaging(revision: revision, previous: previous, error: error)
        }
    }

    private func failStaging(
        revision: UInt64,
        previous: StagedBundle?,
        error: StagingError
    ) {
        guard stagingRevision == revision else {
            pendingPreviewImages.removeValue(forKey: revision)
            return
        }

        if let previous, !isStagedBundleConsumed {
            try? FileManager.default.removeItem(at: previous.url)
        }
        if lastReadyBundle?.url == previous?.url {
            lastReadyBundle = nil
        }

        stagingState = .failed(error)
        onStorageChanged?()
    }
}
