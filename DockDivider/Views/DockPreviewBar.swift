//
//  DockPreviewBar.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import SwiftUI
import AppKit

struct DockPreviewBar: View {
    @Binding var model: DividerModel
    @State private var isDarkDock: Bool? = nil
    @State private var isHoveringDivider: Bool = false

    init(model: Binding<DividerModel>) {
        self._model = model
    }

    init(model: DividerModel) {
        self._model = .constant(model)
    }

    private var currentIsDarkDock: Bool {
        isDarkDock ?? !model.isDarkLuminance
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 10) {
            // Header with quick orientation segmented switch and Light/Dark toggle
            previewHeader

            Spacer(minLength: 4)

            // Desktop Canvas with Dock Glass & Wallpaper
            desktopCanvas

            Spacer(minLength: 4)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Header

    @ViewBuilder
    private var previewHeader: some View {
        ZStack {
            // Centered Orientation Switcher
            orientationSwitcher

            // Leading Title & Trailing Light/Dark Toggle
            HStack {
                Text("Preview")
                    .font(.headline)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDarkDock = !currentIsDarkDock
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: currentIsDarkDock ? "moon.fill" : "sun.max.fill")
                            .font(.system(size: 10))
                        Text(currentIsDarkDock ? "Dark" : "Light")
                            .font(.caption2)
                    }
                    .frame(width: 52)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    )
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help("Toggle Dock Preview Light/Dark Glass")
                .accessibilityLabel("Preview appearance")
                .accessibilityValue(currentIsDarkDock ? "Dark" : "Light")
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var orientationSwitcher: some View {
        Picker("Dock Position", selection: $model.orientation.deferred().animation(.easeInOut(duration: 0.15))) {
            Label("Bottom Dock", systemImage: "dock.rectangle").tag(DividerOrientation.vertical)
            Label("Side Dock", systemImage: "sidebar.left").tag(DividerOrientation.horizontal)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.regular)
    }

    // MARK: - Desktop Canvas Container

    @ViewBuilder
    private var desktopCanvas: some View {
        ZStack {
            desktopWallpaperBackdrop

            dockGlassContainer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(minHeight: 210, maxHeight: 250)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
        // The simulated Dock is decorative; read it as one sentence instead of
        // exposing placeholder app icons and the tooltip pill individually.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dock preview")
        .accessibilityValue(
            "\(model.style.displayName) divider, "
            + "\(model.orientation == .vertical ? "bottom" : "side") Dock, "
            + "\(currentIsDarkDock ? "dark" : "light") appearance"
        )
    }

    // MARK: - Desktop Wallpaper Backdrop (Aquatic Lake & Deep Water Theme)

    @ViewBuilder
    private var desktopWallpaperBackdrop: some View {
        ZStack {
            if currentIsDarkDock {
                // Deep Oceanic / Night Lake Water Base
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.09, blue: 0.16),
                        Color(red: 0.05, green: 0.14, blue: 0.22),
                        Color(red: 0.02, green: 0.06, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.00, green: 0.50, blue: 0.65).opacity(0.26),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 20,
                        endRadius: 180
                    )
                )
            } else {
                // Sunlit Azure / Crystal Lake Shallows Base
                LinearGradient(
                    colors: [
                        Color(red: 0.82, green: 0.93, blue: 0.97),
                        Color(red: 0.74, green: 0.89, blue: 0.95),
                        Color(red: 0.86, green: 0.95, blue: 0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.00, green: 0.65, blue: 0.80).opacity(0.20),
                            Color(red: 0.15, green: 0.82, blue: 0.78).opacity(0.12),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 20,
                        endRadius: 200
                    )
                )
            }

            // Procedural Water Caustic Refraction & Zen Ripple Overlay (0 KB bundle size)
            WaterPatternOverlay(isDark: currentIsDarkDock)
                .equatable()
        }
    }

    // MARK: - Dock Glass Container

    @ViewBuilder
    private var dockGlassContainer: some View {
        if model.orientation == .horizontal {
            verticalDockPreview
        } else {
            horizontalDockPreview
        }
    }

    // MARK: - Horizontal Bottom Dock Preview

    @ViewBuilder
    private var horizontalDockPreview: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 12) {
                dockAppIcon(
                    name: "Finder",
                    path: "/System/Library/CoreServices/Finder.app",
                    fallbackSystemName: "macwindow"
                )

                dockAppIcon(
                    name: "Safari",
                    path: "/Applications/Safari.app",
                    fallbackSystemName: "safari"
                )

                // Live Divider Preview Item with Simulated Native Tooltip
                dividerPreviewWithTooltip

                dockAppIcon(
                    name: "Messages",
                    path: "/System/Applications/Messages.app",
                    fallbackSystemName: "message.fill"
                )

                dockAppIcon(
                    name: "Settings",
                    path: "/System/Applications/System Settings.app",
                    fallbackSystemName: "gear"
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(dockGlassBackground(cornerRadius: 18))
        }
        .padding(.top, 44)
        .frame(height: 165, alignment: .top)
    }

    // MARK: - Vertical Side Dock Preview (Option A)

    @ViewBuilder
    private var verticalDockPreview: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                VStack(spacing: 8) {
                    dockAppIcon(
                        name: "Safari",
                        path: "/Applications/Safari.app",
                        fallbackSystemName: "safari"
                    )

                    // Live Horizontal Divider Preview Item with Side Tooltip
                    dividerPreviewWithTooltip

                    dockAppIcon(
                        name: "Messages",
                        path: "/System/Applications/Messages.app",
                        fallbackSystemName: "message.fill"
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .background(dockGlassBackground(cornerRadius: 18))
            }
        }
        .frame(height: 165)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Glass Background Helper

    @ViewBuilder
    private func dockGlassBackground(cornerRadius: CGFloat) -> some View {
        let fillColor = currentIsDarkDock ? Color(white: 0.14).opacity(0.88) : Color(white: 0.88).opacity(0.85)
        let strokeColor = currentIsDarkDock ? Color.white.opacity(0.14) : Color.black.opacity(0.12)

        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
    }

    // MARK: - Divider Preview & Tooltip

    @ViewBuilder
    private var dividerPreviewWithTooltip: some View {
        let trimmedLabel = model.hoverLabel.trimmingCharacters(in: .whitespaces)
        let showsTooltip = (model.style != .spacer || model.requiresAppBundleForSpacer)

        if model.orientation == .horizontal {
            dividerPreviewItem
                .scaleEffect(isHoveringDivider ? 1.05 : 1.0)
                .overlay(alignment: .leading) {
                    if showsTooltip {
                        sideTooltipPill(label: trimmedLabel)
                    }
                }
                .onHover { hovering in
                    guard isHoveringDivider != hovering else { return }
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.68)) {
                        isHoveringDivider = hovering
                    }
                }
        } else {
            dividerPreviewItem
                .scaleEffect(isHoveringDivider ? 1.05 : 1.0)
                .overlay(alignment: .top) {
                    if showsTooltip {
                        tooltipPill(label: trimmedLabel)
                    }
                }
                .onHover { hovering in
                    guard isHoveringDivider != hovering else { return }
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.68)) {
                        isHoveringDivider = hovering
                    }
                }
        }
    }

    @ViewBuilder
    private func tooltipPill(label: String) -> some View {
        let shape = DockTooltipShape(pointerEdge: .bottom, pointerWidth: 10, pointerHeight: 4, tipRadius: 1.5)
        let textColor = currentIsDarkDock ? Color.white.opacity(0.96) : Color.black.opacity(0.88)
        let horizontalPadding: CGFloat = label.isEmpty ? 0 : 10
        let minWidth: CGFloat = label.isEmpty ? 32 : 36
        let minHeight: CGFloat = 14

        Text(label)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: minWidth, minHeight: minHeight)
            .padding(.top, 2)
            .padding(.bottom, 6)
            .background(tooltipBackground(shape: shape))
            .fixedSize()
            .offset(y: -40)
    }

    @ViewBuilder
    private func sideTooltipPill(label: String) -> some View {
        let shape = DockTooltipShape(pointerEdge: .leading, pointerWidth: 10, pointerHeight: 4, tipRadius: 1.5)
        let textColor = currentIsDarkDock ? Color.white.opacity(0.96) : Color.black.opacity(0.88)
        let horizontalPadding: CGFloat = label.isEmpty ? 0 : 10
        let minWidth: CGFloat = label.isEmpty ? 32 : 36
        let minHeight: CGFloat = 16

        Text(label)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: minWidth, minHeight: minHeight)
            .padding(.leading, 5)
            .padding(.trailing, 3)
            .padding(.vertical, 2.5)
            .background(tooltipBackground(shape: shape))
            .fixedSize()
            .offset(x: 66)
    }

    @ViewBuilder
    private func tooltipBackground(shape: DockTooltipShape) -> some View {
        let fillColor = currentIsDarkDock ? Color(white: 0.18).opacity(0.84) : Color.white.opacity(0.82)
        let strokeColor = currentIsDarkDock ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
        let shadowOpacity: Double = currentIsDarkDock ? 0.30 : 0.15

        shape
            .fill(fillColor)
            .overlay(
                shape
                    .stroke(strokeColor, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 5, y: 1.5)
    }

    @ViewBuilder
    private var dividerPreviewItem: some View {
        let image = IconRenderer.renderNSImage(for: model, size: CGSize(width: 48, height: 48))
        let previewWidth: CGFloat = {
            guard model.style == .spacer, !model.requiresAppBundleForSpacer else { return 48 }
            switch model.spacerSize {
            case .small: return 24
            case .regular: return 48
            case .flex: return 72
            }
        }()
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: previewWidth, height: 48)
    }

    // MARK: - App Icons

    private static var iconCache: [String: NSImage] = [:]
    private static var missingIconPaths: Set<String> = []

    private func cachedSystemIcon(for path: String) -> NSImage? {
        if let cached = Self.iconCache[path] {
            return cached
        }
        if Self.missingIconPaths.contains(path) {
            return nil
        }
        guard FileManager.default.fileExists(atPath: path) else {
            Self.missingIconPaths.insert(path)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        Self.iconCache[path] = icon
        return icon
    }

    @ViewBuilder
    private func dockAppIcon(name: String, path: String, fallbackSystemName: String) -> some View {
        if let icon = cachedSystemIcon(for: path) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        } else {
            dockFallbackIcon(name, systemName: fallbackSystemName)
        }
    }

    @ViewBuilder
    private func dockFallbackIcon(_ title: String, systemName: String) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.8), Color.accentColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 48, height: 48)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
            )
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
    }
}

// MARK: - Native macOS Dock Tooltip Pill Shape with Soft Pointer Beak

enum TooltipPointerEdge {
    case bottom
    case leading
}

struct DockTooltipShape: Shape {
    var pointerEdge: TooltipPointerEdge = .bottom
    var pointerWidth: CGFloat = 10.0
    var pointerHeight: CGFloat = 4.0
    var tipRadius: CGFloat = 1.5

    func path(in rect: CGRect) -> Path {
        switch pointerEdge {
        case .bottom:
            return bottomPointerPath(in: rect)
        case .leading:
            return leadingPointerPath(in: rect)
        }
    }

    private func bottomPointerPath(in rect: CGRect) -> Path {
        var path = Path()

        let bubbleHeight = max(8.0, rect.height - pointerHeight)
        let r = bubbleHeight / 2.0
        let midX = rect.midX
        let halfPointer = pointerWidth / 2.0

        // Start top-left
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))

        // Top edge
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))

        // Right semicircle (capsule end)
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge toward pointer
        let beakRight = max(rect.minX + r, midX + halfPointer)
        path.addLine(to: CGPoint(x: beakRight, y: bubbleHeight))

        // Smooth curved downward pointer beak with rounded tip
        let beakTip = CGPoint(x: midX, y: rect.maxY)
        let beakLeft = min(rect.maxX - r, midX - halfPointer)

        path.addCurve(
            to: beakTip,
            control1: CGPoint(x: midX + halfPointer * 0.7, y: bubbleHeight),
            control2: CGPoint(x: midX + tipRadius, y: rect.maxY)
        )

        path.addCurve(
            to: CGPoint(x: beakLeft, y: bubbleHeight),
            control1: CGPoint(x: midX - tipRadius, y: rect.maxY),
            control2: CGPoint(x: midX - halfPointer * 0.7, y: bubbleHeight)
        )

        // Bottom edge to left semicircle
        path.addLine(to: CGPoint(x: rect.minX + r, y: bubbleHeight))

        // Left semicircle (capsule end)
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: bubbleHeight - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }

    private func leadingPointerPath(in rect: CGRect) -> Path {
        var path = Path()

        let bubbleLeft = rect.minX + pointerHeight
        let r = max(4.0, rect.height / 2.0)
        let midY = rect.midY
        let halfPointer = min(r * 0.85, pointerWidth / 2.0)

        let sinAlpha = halfPointer / r
        let cosAlpha = sqrt(max(0.0, 1.0 - sinAlpha * sinAlpha))
        let alphaDegrees = Angle(radians: Double(asin(sinAlpha))).degrees

        let centerLeft = CGPoint(x: bubbleLeft + r, y: midY)
        let centerRight = CGPoint(x: max(bubbleLeft + r, rect.maxX - r), y: midY)

        // Start at top edge
        path.move(to: CGPoint(x: centerLeft.x, y: rect.minY))

        // Top line
        path.addLine(to: CGPoint(x: centerRight.x, y: rect.minY))

        // Right semicircle
        path.addArc(
            center: centerRight,
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom line
        path.addLine(to: CGPoint(x: centerLeft.x, y: rect.maxY))

        // Bottom-left arc up to the beak start
        let beakStartAngle = 180.0 - alphaDegrees
        path.addArc(
            center: centerLeft,
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(beakStartAngle),
            clockwise: false
        )

        // Smooth curved leftward pointer beak with rounded tip
        let beakTip = CGPoint(x: rect.minX, y: midY)
        let beakEndAngle = 180.0 + alphaDegrees

        path.addCurve(
            to: beakTip,
            control1: CGPoint(x: bubbleLeft + (1.0 - cosAlpha) * r * 0.5, y: midY + halfPointer * 0.6),
            control2: CGPoint(x: rect.minX + tipRadius * 0.5, y: midY + tipRadius)
        )

        let endPointX = centerLeft.x - r * cosAlpha
        let endPointY = centerLeft.y - halfPointer

        path.addCurve(
            to: CGPoint(x: endPointX, y: endPointY),
            control1: CGPoint(x: rect.minX + tipRadius * 0.5, y: midY - tipRadius),
            control2: CGPoint(x: bubbleLeft + (1.0 - cosAlpha) * r * 0.5, y: midY - halfPointer * 0.6)
        )

        // Top-left arc from beak end to top edge
        path.addArc(
            center: centerLeft,
            radius: r,
            startAngle: .degrees(beakEndAngle),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - Procedural Water Wave Swells Overlay (Option 3 - 0 KB Bundle Size)

struct WaterPatternOverlay: View, Equatable {
    let isDark: Bool

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Wave layer configurations: (yPositionFraction, amplitude, frequency, opacityMultiplier)
            let waves: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0.82, 16, 1.2, 0.20),
                (0.64, 20, 1.6, 0.26),
                (0.44, 24, 1.3, 0.32),
                (0.24, 22, 1.8, 0.38)
            ]

            for (yFrac, amp, freq, alpha) in waves {
                let startY = yFrac * h

                // 1. Swell filled body
                var fillPath = Path()
                fillPath.move(to: CGPoint(x: 0, y: startY))

                var x: CGFloat = 0
                while x <= w + 16 {
                    let y = startY + sin((x / w) * .pi * 2 * freq) * amp + cos((x / w) * .pi * freq * 0.7) * (amp * 0.45)
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                    x += 6
                }
                fillPath.addLine(to: CGPoint(x: w, y: 0))
                fillPath.addLine(to: CGPoint(x: 0, y: 0))
                fillPath.closeSubpath()

                let fillColor: Color = isDark
                    ? Color(red: 0.01, green: 0.04, blue: 0.09).opacity(alpha * 0.45)
                    : Color(red: 0.00, green: 0.58, blue: 0.74).opacity(alpha * 0.28)

                context.fill(fillPath, with: .color(fillColor))

                // 2. Swell crest highlight line
                var crestPath = Path()
                crestPath.move(to: CGPoint(x: 0, y: startY))
                x = 0
                while x <= w + 16 {
                    let y = startY + sin((x / w) * .pi * 2 * freq) * amp + cos((x / w) * .pi * freq * 0.7) * (amp * 0.45)
                    crestPath.addLine(to: CGPoint(x: x, y: y))
                    x += 6
                }

                let crestColor: Color = isDark
                    ? Color(red: 0.20, green: 0.82, blue: 0.92).opacity(alpha * 0.42)
                    : Color.white.opacity(alpha * 0.85)

                context.stroke(crestPath, with: .color(crestColor), lineWidth: 1.8)
            }
        }
        .allowsHitTesting(false)
    }
}
