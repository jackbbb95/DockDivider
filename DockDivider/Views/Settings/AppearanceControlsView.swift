//
//  AppearanceControlsView.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AppearanceControlsView: View {
    @Binding var model: DividerModel
    @State private var isImageDropTargeted: Bool = false
    @State private var isShowingSymbolPicker: Bool = false
    @State private var isProcessingImage: Bool = false
    @State private var imageImportError: String?
    @State private var imageImportRevision: UInt64 = 0

    private let popularSymbols = [
        "star.fill",
        "sparkles",
        "chevron.left.forwardslash.chevron.right",
        "terminal.fill",
        "folder.fill",
        "briefcase.fill",
        "music.note"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection

            if model.style == .spacer {
                spacerSection
            } else {
                colorSection
                dimensionsSection
                if model.style == .label {
                    labelStyleSection
                }
                if model.style == .image {
                    imageStyleSection
                }
                tooltipSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 12) {
            Text("Appearance")
                .font(.headline)
            Spacer()

            Button {
                sampleNativeDividerColor()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "eyedropper")
                    Text("Sample Color…")
                }
            }
            .buttonStyle(.link)
            .font(.caption)
            .help(supportsSampledColor ? "Pick a color from anywhere on screen and apply it to this divider" : "")
            .opacity(supportsSampledColor ? 1.0 : 0.0)
            .allowsHitTesting(supportsSampledColor)
            .accessibilityHidden(!supportsSampledColor)
            .animation(.easeInOut(duration: 0.22), value: supportsSampledColor)

            Button("Reset Appearance") {
                model.resetAppearance()
            }
            .buttonStyle(.link)
            .font(.caption)
            .help("Reset color, opacity, thickness, height, offset, and image corners without changing the divider style or click action")
        }
    }

    /// Spacer and image styles do not use the divider tint.
    private var supportsSampledColor: Bool {
        model.style != .spacer && model.style != .image
    }

    // MARK: - Spacer Section

    @ViewBuilder
    private var spacerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                SettingsLabeledRow("Spacer Width:") {
                    Picker("Spacer Width", selection: $model.spacerSize.deferred()) {
                        ForEach(SpacerSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.requiresAppBundleForSpacer)
                }

                if model.requiresAppBundleForSpacer {
                    Text("Locked to Full width while a Tooltip or Click Action is present.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, SettingsLayout.labelWidth)
                }
            }

            SettingsLabeledRow("Tooltip:") {
                TextField("Empty by default", text: $model.hoverLabel)
                    .textFieldStyle(.roundedBorder)
            }

            spacerInfoBox
        }
    }

    @ViewBuilder
    private var spacerInfoBox: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text("Native macOS Spacer Tile")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("With no Click Action or Tooltip set, this drags a true native macOS Dock spacer (`spacer-tile`) with zero tooltip and zero clickability. Adding a Click Action or Tooltip automatically converts it into an Invisible App Hider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Color Section

    @ViewBuilder
    private var colorSection: some View {
        if model.style != .image {
            SettingsLabeledRow("Color / Tint:") {
                Picker("Color Preset", selection: $model.colorPreset.deferred()) {
                    ForEach(ColorPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if model.colorPreset == .custom {
                SettingsLabeledRow("Custom Color:") {
                    ColorPicker("", selection: Binding(
                        get: {
                            model.effectiveColor
                        },
                        set: { newColor in
                            model.updateCustomColor(from: newColor)
                        }
                    ))
                    .labelsHidden()
                    .accessibilityLabel("Custom divider color")
                }
            }
        }

        SettingsSliderRow(
            "Opacity:",
            value: $model.opacity,
            in: 0.10...1.0,
            step: 0.05,
            formattedValue: "\(Int(model.opacity * 100))%"
        )
    }

    // MARK: - Dimensions Section

    @ViewBuilder
    private var dimensionsSection: some View {
        if model.style == .line || model.style == .dashed || model.style == .dot {
            SettingsSliderRow(
                "Thickness:",
                value: $model.thickness,
                in: 1.0...8.0,
                step: 0.5,
                formattedValue: String(format: "%.1f pt", model.thickness)
            )
        }

        if model.style == .line || model.style == .dashed || model.style == .label || model.style == .image {
            let labelText = (model.style == .image || model.style == .label)
                ? "Scale:"
                : (model.orientation == .horizontal ? "Width:" : "Height:")
            let range = (model.style == .image) ? 0.10...1.50 : 0.20...1.0

            SettingsSliderRow(
                labelText,
                value: $model.heightRatio,
                in: range,
                step: 0.05,
                formattedValue: "\(Int(model.heightRatio * 100))%"
            )
            .id("height-ratio-slider")
        }

        SettingsSliderRow(
            "Vertical Offset:",
            value: $model.verticalOffset,
            in: -0.25...0.25,
            step: 0.01,
            formattedValue: String(format: "%+.0f%%", model.verticalOffset * 100)
        )
    }

    // MARK: - Label Style Section

    @ViewBuilder
    private var labelStyleSection: some View {
        SettingsLabeledRow("Label Mode:") {
            Picker("Label Mode", selection: $model.labelMode.deferred()) {
                ForEach(LabelMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }

        switch model.labelMode {
        case .text:
            SettingsLabeledRow("Label Text:") {
                TextField("DEV, AI, >_, etc.", text: $model.labelText)
                    .textFieldStyle(.roundedBorder)
            }

            SettingsLabeledRow("") {
                Toggle("Stack Vertically", isOn: $model.isVerticalText)
                    .font(.subheadline)
            }

        case .symbol:
            let isValidSymbol = NSImage(systemSymbolName: model.symbolName, accessibilityDescription: nil) != nil

            SettingsLabeledRow("SF Symbol:") {
                HStack(spacing: 8) {
                    TextField("SF Symbol name (e.g. star.fill)", text: $model.symbolName)
                        .textFieldStyle(.roundedBorder)

                    if !model.symbolName.isEmpty && !isValidSymbol {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("Symbol not found in SF Symbols")
                    }

                    Button {
                        isShowingSymbolPicker.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            if isValidSymbol {
                                Image(systemName: model.symbolName)
                                    .foregroundStyle(.primary)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "square.grid.2x2")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16, height: 16)
                            }
                            Text("Browse…")
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .help("Open the built-in macOS SF Symbols browser")
                    .popover(isPresented: $isShowingSymbolPicker, arrowEdge: .bottom) {
                        if isShowingSymbolPicker {
                            SFSymbolPickerPopover(
                                selectedSymbol: $model.symbolName,
                                isPresented: $isShowingSymbolPicker
                            )
                        }
                    }
                }
            }

            if !model.symbolName.isEmpty && !isValidSymbol {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Symbol '\(model.symbolName)' not recognized by system SF Symbols")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, SettingsLayout.labelWidth)
            }

            SettingsLabeledRow("Popular:", alignment: .top) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], spacing: 6) {
                    ForEach(popularSymbols, id: \.self) { symbol in
                        Button {
                            model.symbolName = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 13))
                                .frame(width: 32, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(model.symbolName == symbol ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(model.symbolName == symbol ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                        .accessibilityLabel(symbol)
                        .accessibilityValue(model.symbolName == symbol ? "Selected" : "")
                    }
                }
            }
        }
    }

    // MARK: - Image Style Section

    @ViewBuilder
    private var imageStyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsLabeledRow("Image File:") {
                if let data = model.imageData, let nsImage = IconRenderer.cachedSourceImage(for: model) {
                    HStack(spacing: 8) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )

                        Text("\(data.count / 1024) KB")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if isProcessingImage {
                            ProgressView()
                                .controlSize(.small)
                            Text("Processing…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Replace...") {
                                selectImageFile()
                            }
                            .font(.caption)

                            Button("Clear") {
                                clearImage()
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                    }
                } else if isProcessingImage {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Processing image…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        selectImageFile()
                    } label: {
                        Label("Choose Image...", systemImage: "photo")
                    }
                }
            }

            if let imageImportError {
                Label(imageImportError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, SettingsLayout.labelWidth)
            }

            // Drag and Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isImageDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isImageDropTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
                    )
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .foregroundStyle(.secondary)
                    Text("or drop an image file here (PNG, SVG, JPEG, HEIC, TIFF)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .onDrop(of: [.fileURL, .image], isTargeted: $isImageDropTargeted) { providers in
                handleImageDrop(providers: providers)
            }
            .padding(.leading, SettingsLayout.labelWidth)

            // Rounded Corners controls for custom images
            SettingsLabeledRow("Corner Style:") {
                Toggle("Rounded Corners", isOn: $model.roundImageCorners)
                    .font(.subheadline)
                if model.roundImageCorners && abs(model.imageCornerRadiusRatio - 0.225) > 0.005 {
                    Spacer()
                    Button("App Icon (22.5%)") {
                        model.imageCornerRadiusRatio = 0.225
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            if model.roundImageCorners {
                let cornerRadiusFormatted = abs(model.imageCornerRadiusRatio - 0.225) < 0.005
                    ? "22.5%"
                    : "\(Int((model.imageCornerRadiusRatio * 100).rounded()))%"

                SettingsSliderRow(
                    "Corner Radius:",
                    value: $model.imageCornerRadiusRatio,
                    in: 0.05...0.50,
                    step: 0.025,
                    formattedValue: cornerRadiusFormatted
                )
            }
        }
    }

    // MARK: - Tooltip Section

    @ViewBuilder
    private var tooltipSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsLabeledRow("Tooltip:") {
                TextField("Empty by default", text: $model.hoverLabel)
                    .textFieldStyle(.roundedBorder)
            }

            tooltipInfoBox
        }
    }

    @ViewBuilder
    private var tooltipInfoBox: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text("macOS Dock Tooltips")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("macOS does not allow hiding the tooltip completely; leaving this empty will display a small blank pill on hover.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Image Helpers

    private func sampleNativeDividerColor() {
        NSColorSampler().show { selectedColor in
            guard let selectedColor = selectedColor else { return }
            Task { @MainActor in
                model.colorPreset = .custom
                model.updateCustomColor(from: Color(nsColor: selectedColor))
            }
        }
    }

    private func selectImageFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .svg, .heic, .tiff, .image]
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            loadImage(from: url)
        }
    }

    private enum ImageImportResult: Sendable {
        case success(ProcessedImage)
        case failure(String)
    }

    private func loadImage(from url: URL) {
        let revision = beginImageImport()

        Task { @MainActor in
            let result: ImageImportResult = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(try CustomImageProcessor.process(fileURL: url))
                } catch let error as ImageProcessingError {
                    return .failure(error.errorDescription ?? "DockDivider couldn’t read that image.")
                } catch {
                    return .failure(error.localizedDescription)
                }
            }.value

            // SVG and other vector formats that ImageIO cannot decode are
            // rasterized by AppKit on the main actor as a fallback.
            if case .failure = result,
               let image = NSImage(contentsOf: url),
               let processed = CustomImageProcessor.rasterize(image: image) {
                finishImageImport(.success(processed), revision: revision)
            } else {
                finishImageImport(result, revision: revision)
            }
        }
    }

    private func importImageData(_ data: Data) {
        let revision = beginImageImport()

        Task { @MainActor in
            let result: ImageImportResult = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(try CustomImageProcessor.process(data: data))
                } catch let error as ImageProcessingError {
                    return .failure(error.errorDescription ?? "DockDivider couldn’t read that image.")
                } catch {
                    return .failure(error.localizedDescription)
                }
            }.value

            if case .failure = result,
               let image = NSImage(data: data),
               let processed = CustomImageProcessor.rasterize(image: image) {
                finishImageImport(.success(processed), revision: revision)
            } else {
                finishImageImport(result, revision: revision)
            }
        }
    }

    private func beginImageImport() -> UInt64 {
        imageImportRevision &+= 1
        isProcessingImage = true
        imageImportError = nil
        return imageImportRevision
    }

    private func finishImageImport(_ result: ImageImportResult, revision: UInt64) {
        // A newer import (or Clear) superseded this one.
        guard revision == imageImportRevision else { return }

        isProcessingImage = false
        switch result {
        case .success(let image):
            model.imageData = image.data
            model.imageID = image.imageID
        case .failure(let message):
            imageImportError = message
        }
    }

    private func clearImage() {
        imageImportRevision &+= 1
        isProcessingImage = false
        imageImportError = nil
        model.imageData = nil
        model.imageID = nil
    }

    private func handleImageDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var targetURL: URL?
                if let url = item as? URL {
                    targetURL = url
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    targetURL = url
                }
                if let url = targetURL {
                    DispatchQueue.main.async {
                        self.loadImage(from: url)
                    }
                }
            }
            return true
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                if let data {
                    DispatchQueue.main.async {
                        self.importImageData(data)
                    }
                }
            }
            return true
        }
        return false
    }
}
