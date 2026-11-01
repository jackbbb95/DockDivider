//
//  DragWellView.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import SwiftUI
import AppKit

struct DragWellView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    let model: DividerModel
    @State private var isHovering: Bool = false

    // MARK: - Computed Properties

    /// Whether the divider graphic needs a light contrasting backdrop to remain clearly visible.
    private var needsLightPreviewBackdrop: Bool {
        model.style != .spacer && model.isDarkLuminance
    }

    /// Adaptive background for the outer "Drag Me to Dock" box that shifts to a contrasting
    /// surface when the divider color would otherwise blend into the current appearance mode.
    private var wellBackgroundColor: Color {
        if isHovering {
            return Color.accentColor.opacity(0.08)
        }
        if needsLightPreviewBackdrop && colorScheme == .dark {
            return Color.white.opacity(0.14)
        } else if !needsLightPreviewBackdrop && model.style != .spacer && colorScheme == .light {
            return Color.black.opacity(0.07)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(wellBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isHovering ? Color.accentColor : Color.secondary.opacity(0.3),
                                style: StrokeStyle(lineWidth: isHovering ? 2 : 1.5, dash: [6, 4])
                            )
                    )

                HStack(spacing: 16) {
                    let image = IconRenderer.renderNSImage(for: model, size: CGSize(width: 56, height: 56))
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 52, height: 52)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 11)
                                .fill(
                                    model.style == .spacer
                                        ? Color.secondary.opacity(0.08)
                                        : (needsLightPreviewBackdrop
                                            ? Color(white: 0.88)
                                            : Color(white: 0.16))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11)
                                        .strokeBorder(
                                            needsLightPreviewBackdrop
                                                ? Color.black.opacity(0.12)
                                                : Color.white.opacity(0.14),
                                            lineWidth: 1
                                        )
                                )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Drag Me to Dock")
                                .font(.headline)

                            switch appState.stagingState {
                            case .preparing:
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text("Preparing…")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            case .ready:
                                if appState.validationWarning == nil {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                        Text("Ready")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                        Text("Needs Setup")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            case .failed:
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text("Needs Attention")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            case .idle:
                                EmptyView()
                            }
                        }

                        Text("Drop directly onto your macOS Dock.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "hand.draw")
                        .font(.title2)
                        .foregroundStyle(isHovering ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .frame(height: 80)
            .overlay(
                TransparentFileDragSource(
                    model: model,
                    canStartDrag: { appState.isReadyForDrag },
                    onHoverChange: { hovering in
                        isHovering = hovering
                    },
                    provideFileURL: {
                        appState.consumeStagedBundleForDrag()
                    },
                    onDragEnded: { operation in
                        appState.handleDragEnded(operation: operation)
                    },
                    onAccessibilityPress: {
                        appState.revealStagedBundleInFinder()
                    }
                )
            )

            // Error Banner
            if let error = appState.stagingError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)

                        if let suggestion = error.recoverySuggestion {
                            Text(suggestion)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    if error.allowsRetry {
                        Button("Retry") {
                            appState.retryStaging()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button {
                        appState.dismissStagingError()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss this error")
                    .accessibilityLabel("Dismiss error")
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red.opacity(0.25), lineWidth: 1)
                        )
                )
            }

            // Configuration warning: the divider is staged, but it would do
            // nothing when clicked or has no image to draw.
            if appState.stagingError == nil, let warning = appState.validationWarning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(.top, 1)

                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                        )
                )
            }

            Text("To remove a divider later, right click > Options > Remove from Dock, or drag it out.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - AppKit Transparent File Drag Source

private struct TransparentFileDragSource: NSViewRepresentable {
    let model: DividerModel
    let canStartDrag: () -> Bool
    let onHoverChange: (Bool) -> Void
    let provideFileURL: () -> URL?
    let onDragEnded: (NSDragOperation) -> Void
    let onAccessibilityPress: () -> Void

    func makeNSView(context: Context) -> DragSourceNSView {
        let view = DragSourceNSView()
        view.model = model
        view.canStartDrag = canStartDrag
        view.onHoverChange = onHoverChange
        view.provideFileURL = provideFileURL
        view.onDragEnded = onDragEnded
        view.onAccessibilityPress = onAccessibilityPress
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Divider drag well")
        view.setAccessibilityHelp("Drag the prepared divider to the Dock, or press to reveal it in Finder.")
        view.setAccessibilityIdentifier("dragWell")
        return view
    }

    func updateNSView(_ nsView: DragSourceNSView, context: Context) {
        nsView.model = model
        nsView.canStartDrag = canStartDrag
        nsView.onHoverChange = onHoverChange
        nsView.provideFileURL = provideFileURL
        nsView.onDragEnded = onDragEnded
        nsView.onAccessibilityPress = onAccessibilityPress
    }
}

// MARK: - Drag Source NSView

final class DragSourceNSView: NSView, NSDraggingSource {
    var model: DividerModel = DividerModel()
    var canStartDrag: (() -> Bool)?
    var onHoverChange: ((Bool) -> Void)?
    var provideFileURL: (() -> URL?)?
    var onDragEnded: ((NSDragOperation) -> Void)?
    var onAccessibilityPress: (() -> Void)?

    private var mouseDownEvent: NSEvent?
    private var didStartDrag: Bool = false
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            if existing.rect == bounds { return }
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
        NSCursor.openHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
        NSCursor.closedHand.set()
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        didStartDrag = false
        NSCursor.openHand.set()
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onAccessibilityPress else { return false }
        onAccessibilityPress()
        return true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, let startEvent = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - startEvent.locationInWindow.x
        let dy = event.locationInWindow.y - startEvent.locationInWindow.y
        guard hypot(dx, dy) >= 3.0 else { return }

        didStartDrag = true

        guard canStartDrag?() ?? true else {
            NSCursor.operationNotAllowed.set()
            return
        }

        guard let fileURL = provideFileURL?() else {
            NSCursor.operationNotAllowed.set()
            return
        }

        let dragSize = CGSize(width: 64, height: 64)
        let dragImage = IconRenderer.renderNSImage(for: model, size: dragSize)
        let localPoint = convert(event.locationInWindow, from: nil)
        let dragFrame = NSRect(
            x: localPoint.x - dragSize.width / 2.0,
            y: localPoint.y - dragSize.height / 2.0,
            width: dragSize.width,
            height: dragSize.height
        )

        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        draggingItem.setDraggingFrame(dragFrame, contents: dragImage)

        let session = beginDraggingSession(with: [draggingItem], event: startEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .every
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        mouseDownEvent = nil
        didStartDrag = false
        NSCursor.arrow.set()
        onDragEnded?(operation)
    }
}
