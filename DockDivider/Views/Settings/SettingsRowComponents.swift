//
//  SettingsRowComponents.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import SwiftUI

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

    init(
        label: String,
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

    init(
        label: String,
        value: Binding<V>,
        range: ClosedRange<V>,
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
            get: { value },
            set: { newValue in
                guard abs(Double(newValue - value)) > 1e-4 else { return }
                DispatchQueue.main.async {
                    value = newValue
                }
            }
        )
    }

    var body: some View {
        SettingsLabeledRow(label) {
            if let step = step {
                Slider(value: safeValueBinding, in: range, step: V.Stride(step))
            } else {
                Slider(value: safeValueBinding, in: range)
            }
            Text(formattedValue)
                .frame(width: SettingsLayout.sliderValueWidth, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
