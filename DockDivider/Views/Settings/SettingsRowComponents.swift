//
//  SettingsRowComponents.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import SwiftUI

// MARK: - Binding Extensions

extension Binding where Value: Equatable {
    /// Returns a binding that defers mutations to the next runloop cycle to prevent
    /// "Publishing changes from within view updates is not allowed" warnings when
    /// controls backed by AppKit (such as NSSegmentedControl or NSSlider) fire action
    /// callbacks during view hierarchy evaluation or layout.
    func deferred() -> Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { newValue in
                guard newValue != self.wrappedValue else { return }
                DispatchQueue.main.async {
                    self.wrappedValue = newValue
                }
            }
        )
    }
}

// MARK: - Settings Layout Metrics

enum SettingsLayout {
    static let labelWidth: CGFloat = 110
    static let sliderValueWidth: CGFloat = 45
}

// MARK: - Settings Labeled Row

struct SettingsLabeledRow<Content: View>: View {
    let label: String
    var alignment: VerticalAlignment
    @ViewBuilder let content: () -> Content

    init(
        _ label: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        HStack(alignment: alignment) {
            Text(label)
                .frame(width: SettingsLayout.labelWidth, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Settings Card

/// Standard bordered background for a group of settings controls.
private struct SettingsCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func settingsCard() -> some View {
        modifier(SettingsCardModifier())
    }
}

// MARK: - Settings Info Box

/// Bordered explanation card shown beneath a control or group of controls.
struct SettingsInfoBox: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(message)
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
}

// MARK: - Settings Removable Row

/// A compact entry chip with a leading icon and a trailing remove button.
///
/// Used for the app and URL lists in the click-action editor so both rows keep
/// the same padding, background, and accessibility behavior.
struct SettingsRemovableRow<Icon: View>: View {
    let title: String
    let removeHelp: String
    let removeAccessibilityLabel: String
    let onRemove: () -> Void
    let icon: Icon

    init(
        title: String,
        removeHelp: String,
        removeAccessibilityLabel: String,
        onRemove: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.title = title
        self.removeHelp = removeHelp
        self.removeAccessibilityLabel = removeAccessibilityLabel
        self.onRemove = onRemove
        self.icon = icon()
    }

    var body: some View {
        HStack(spacing: 8) {
            icon

            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(removeHelp)
            .accessibilityLabel(removeAccessibilityLabel)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Settings Slider Row

struct SettingsSliderRow<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let label: String
    @Binding var value: V
    let range: ClosedRange<V>
    var step: V?
    let formattedValue: String

    init(
        _ label: String,
        value: Binding<V>,
        in range: ClosedRange<V>,
        step: V? = nil,
        formattedValue: String
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.formattedValue = formattedValue
    }

    private var safeValueBinding: Binding<V> {
        Binding(
            get: {
                min(max(value, range.lowerBound), range.upperBound)
            },
            set: { newValue in
                let clamped = min(max(newValue, range.lowerBound), range.upperBound)
                guard abs(Double(clamped - value)) > 1e-4 else { return }
                DispatchQueue.main.async {
                    value = clamped
                }
            }
        )
    }

    var body: some View {
        SettingsLabeledRow(label) {
            if let step = step {
                Slider(value: safeValueBinding, in: range, step: V.Stride(step))
                    .accessibilityLabel(label)
                    .accessibilityValue(formattedValue)
            } else {
                Slider(value: safeValueBinding, in: range)
                    .accessibilityLabel(label)
                    .accessibilityValue(formattedValue)
            }
            Text(formattedValue)
                .frame(width: SettingsLayout.sliderValueWidth, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
