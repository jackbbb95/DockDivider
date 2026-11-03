//
//  StagingModels.swift
//  DockDivider
//

import Foundation

/// A generated artifact that is ready to be dragged into the Dock.
struct StagedBundle: Equatable, Sendable {
    enum Kind: String, Sendable {
        case appBundle
        case nativeSpacer
    }

    let url: URL
    let kind: Kind
    let revision: UInt64
}

/// High-level state of the background staging pipeline.
///
/// `preparing` intentionally hides the previously staged bundle: a drag must
/// never start with content that no longer matches the current draft.
enum StagingState: Equatable, Sendable {
    case idle
    case preparing(revision: UInt64)
    case ready(StagedBundle)
    case failed(StagingError)

    var bundle: StagedBundle? {
        if case .ready(let bundle) = self {
            return bundle
        }
        return nil
    }

    var isPreparing: Bool {
        if case .preparing = self {
            return true
        }
        return false
    }

    var error: StagingError? {
        if case .failed(let error) = self {
            return error
        }
        return nil
    }
}

/// Errors surfaced while preparing a divider for drag.
///
/// These are deliberately user-facing: the view shows `errorDescription`,
/// offers `recoverySuggestion`, and exposes a Retry button when `allowsRetry`
/// is true.
enum StagingError: Error, Equatable, LocalizedError, Sendable {
    case iconRenderFailed
    case runnerUnavailable
    case storageUnavailable(String)
    case writeFailed(String)
    case signingFailed(String)
    case finalizeFailed(String)
    case stagedFileMissing
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .iconRenderFailed:
            return "DockDivider couldn’t render the divider image."
        case .runnerUnavailable:
            return "The divider runner is missing from DockDivider."
        case .storageUnavailable(let detail):
            return "DockDivider couldn’t access its storage folder. \(detail)"
        case .writeFailed(let detail):
            return "DockDivider couldn’t write the divider to disk. \(detail)"
        case .signingFailed(let detail):
            return "The divider was created but couldn’t be signed. \(detail)"
        case .finalizeFailed(let detail):
            return "The divider was created but couldn’t be moved into place. \(detail)"
        case .stagedFileMissing:
            return "The prepared divider is no longer on disk."
        case .cancelled:
            return "Preparing the divider was cancelled."
        case .unknown(let detail):
            return detail.isEmpty ? "Preparing the divider failed." : detail
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .iconRenderFailed:
            return "Try a different style, size, or image."
        case .runnerUnavailable:
            return "Reinstall DockDivider, then try again."
        case .storageUnavailable:
            return "Choose a different storage folder in the footer, then try again."
        case .writeFailed, .signingFailed, .finalizeFailed, .stagedFileMissing:
            return "Try again. If it keeps failing, choose a different storage folder."
        case .cancelled:
            return nil
        case .unknown:
            return "Try again."
        }
    }

    var allowsRetry: Bool {
        if case .cancelled = self {
            return false
        }
        return true
    }

    /// Preserves a typed `StagingError` while wrapping any unexpected error.
    static func wrapping(_ error: Error) -> StagingError {
        if let error = error as? StagingError {
            return error
        }
        let nsError = error as NSError
        return .unknown(nsError.localizedDescription)
    }
}
